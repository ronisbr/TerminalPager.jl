## Description #############################################################################
#
# Functions related to the command line.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The status bar is assembled from constant pieces and numbers, so that it does not allocate
# at every keystroke. Every badge has the same width.
const _BADGE_NORMAL = " NORMAL "
const _BADGE_SEARCH = " SEARCH "
const _BADGE_VISUAL = " VISUAL "
const _BADGE_NORMAL_PLAIN = "[NORMAL]"
const _BADGE_SEARCH_PLAIN = "[SEARCH]"
const _BADGE_VISUAL_PLAIN = "[VISUAL]"
const _BADGE_WIDTH = 8

const _EMPTY = " empty "
const _EMPTY_WIDTH = textwidth(_EMPTY)
const _NO_MATCH = " no match "
const _NO_MATCH_WIDTH = textwidth(_NO_MATCH)
const _RULER = " ruler "
const _RULER_WIDTH = textwidth(_RULER)

# The bar is drawn in reverse video, so that it works with light and dark themes. The badges
# and the messages reset it and select their own colors.
const _CRAYON_BAR = "$(CSI)0;7m"
const _CRAYON_BADGE_NORMAL = "$(CSI)0;1;97;44m"
const _CRAYON_BADGE_SEARCH = "$(CSI)0;1;30;43m"
const _CRAYON_BADGE_VISUAL = "$(CSI)0;1;97;45m"
const _CRAYON_MESSAGE_INFO = "$(CSI)0;1;97;42m"
const _CRAYON_MESSAGE_ERROR = "$(CSI)0;1;97;41m"

# Icons telling the kind of a message at a glance. Both have a display width of one.
const _MESSAGE_INFO_ICON = "✓"
const _MESSAGE_ERROR_ICON = "✗"

# Key hints of the status bar, rebuilt when the key bindings change. The entries are the
# generation they were built for, the hints with the help action, and without it.
const _STATUS_HINTS = Ref{Tuple{Int, String, String}}((-1, "", ""))

# Padding is written directly from the bytes of this string, so that right-aligning the
# hint does not allocate a full-width string at every frame.
const _BLANKS = " "^512

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _write_blanks(io::IO, n::Int) -> Int

Write `n` spaces to `io` without allocating.

# Arguments

- `io::IO`: Output stream to update.
- `n::Int`: Number of spaces to write.
"""
function _write_blanks(io::IO, n::Int)
    n <= 0 && return 0

    written = 0

    while written < n
        chunk = min(n - written, length(_BLANKS))
        written += GC.@preserve _BLANKS unsafe_write(io, pointer(_BLANKS), UInt(chunk))
    end

    return written
end

"""
    _prompt_number!(pagerd::Pager, label::String, current::Int) -> Tuple{Symbol, Int}

Prompt for an integer on the command line of `pagerd`, showing `label` and the `current`
value, and return the status and the number typed by the user.

The status is `:value` when a number was typed, `:empty` when the prompt was left empty,
`:cancel` when the prompt was cancelled, and `:invalid` when the input is not a number. In
the last case, an error message is shown on the command line until the next keystroke. The
number is `0` unless the status is `:value`.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.
- `label::String`: Description of the requested number, shown in the prompt.
- `current::Int`: Current value, shown in the prompt.
"""
function _prompt_number!(pagerd::Pager, label::String, current::Int)
    cmd_input = _read_cmd!(pagerd; prefix = "$label [$current] › ")
    isnothing(cmd_input) && return :cancel, 0
    isempty(cmd_input) && return :empty, 0

    value = tryparse(Int, cmd_input; base = 10)

    if isnothing(value)
        _set_message!(pagerd, "Not a number: $cmd_input"; kind = :error)
        return :invalid, 0
    end

    return :value, value
end

"""
    _status_hint(with_help::Bool) -> String

Return the key hints shown at the right of the status bar, such as `?:help  q:quit`.

The hints are rebuilt only when the key bindings change, so that the status bar does not
allocate at every frame.

# Arguments

- `with_help::Bool`: Include the hint of the help action.
"""
function _status_hint(with_help::Bool)
    generation = _KEYBINDINGS_GENERATION[]
    cached = _STATUS_HINTS[]

    if cached[1] != generation
        quit = _primary_key(:quit)
        help = _primary_key(:help)
        without_help = isnothing(quit) ? "" : quit * ":quit"

        hint_with_help = if isnothing(help)
            without_help
        elseif isempty(without_help)
            help * ":help"
        else
            help * ":help  " * without_help
        end

        cached = (generation, hint_with_help, without_help)
        _STATUS_HINTS[] = cached
    end

    return with_help ? cached[2] : cached[3]
end

"""
    _redraw_status_bar!(pagerd::Pager) -> Nothing

Redraw the status bar of `pagerd` on the last row of the display.

The bar shows the mode badge, the visible lines and columns, the search and visual mode
state, the enabled features, the scroll position, and the key hints. When the display is too
narrow, the key hints are dropped first, then the segments from the least to the most
important one. A pending message replaces every segment but the badge.

# Arguments

- `pagerd::Pager`: Pager state to redraw.
"""
function _redraw_status_bar!(pagerd::Pager)
    term = pagerd.term
    rows, cols = pagerd.display_size
    num_lines = pagerd.num_lines
    mode = pagerd.mode
    use_color = get(term.out_stream, :color, true)::Bool

    out = _screen_buffer!(pagerd)

    # Move the cursor to the last row. The row must be cleared explicitly, because nothing
    # else overwrites the text left behind by the command editor.
    _move_cursor(out, rows, 1)
    _clear_to_eol(out)

    if cols <= 0
        _flush_screen!(pagerd)
        return nothing
    end

    # == Badge =============================================================================

    badge, badge_crayon = if pagerd.visual_mode
        use_color ? (_BADGE_VISUAL, _CRAYON_BADGE_VISUAL) : (_BADGE_VISUAL_PLAIN, "")
    elseif mode == :searching
        use_color ? (_BADGE_SEARCH, _CRAYON_BADGE_SEARCH) : (_BADGE_SEARCH_PLAIN, "")
    else
        use_color ? (_BADGE_NORMAL, _CRAYON_BADGE_NORMAL) : (_BADGE_NORMAL_PLAIN, "")
    end

    use_color && write(out, badge_crayon)

    if cols < _BADGE_WIDTH
        # Every badge is ASCII, so the bytes are the columns.
        GC.@preserve badge unsafe_write(out, pointer(badge), UInt(cols))
        use_color && write(out, _CRAYON_RESET)
        _move_cursor(out, rows, 1)
        _flush_screen!(pagerd)
        return nothing
    end

    write(out, badge)
    use_color && write(out, _CRAYON_BAR)
    used = _BADGE_WIDTH

    # == Message ===========================================================================

    message = pagerd.message

    if !isempty(message)
        # The message replaces every other segment until the next keystroke. It is shown
        # like a toast, with an icon and a color that tell its kind at a glance.
        available = cols - used
        width = 0
        is_error = pagerd.message_kind === :error

        use_color && write(out, is_error ? _CRAYON_MESSAGE_ERROR : _CRAYON_MESSAGE_INFO)

        if available >= 3
            write(out, UInt8(' '))
            write(out, is_error ? _MESSAGE_ERROR_ICON : _MESSAGE_INFO_ICON)
            write(out, UInt8(' '))
            width += 3
        end

        for c in message
            character_width = textwidth(c)
            (width + character_width > available) && break
            write(out, c)
            width += character_width
        end

        _write_blanks(out, available - width)
        use_color && write(out, _CRAYON_RESET)
        _move_cursor(out, rows, 1)
        _flush_screen!(pagerd)
        return nothing
    end

    # == Segment Widths ====================================================================

    # Everything but the numbers is constant, so the widths are computed from the number of
    # digits. Assembling strings here allocated at every keystroke.

    # Visible lines: " lines a–b/N ".
    last_line = num_lines - pagerd.cropped_lines
    first_line = min(pagerd.start_row, last_line)
    w_lines = if num_lines == 0
        _EMPTY_WIDTH
    else
        10 + ndigits(first_line) + ndigits(last_line) + ndigits(num_lines)
    end

    # Search: " match i/n " or " no match ".
    num_matches = length(pagerd.ordered_search_matches)
    match_id = pagerd.active_search_match_id
    w_search = if mode != :searching
        0
    elseif num_matches > 0
        9 + ndigits(match_id) + ndigits(num_matches)
    else
        _NO_MATCH_WIDTH
    end

    # Visual mode: " n selected ".
    num_selected = length(pagerd.visual_mode_selected_lines)
    w_visual = pagerd.visual_mode ? 11 + ndigits(num_selected) : 0

    # Visible columns: " cols a–b/W ", only when the text is wider than the view.
    frozen_columns = pagerd.frozen_columns
    ruler_width = pagerd.show_ruler ? _ruler_width(num_lines) : 0
    view_cols = cols - frozen_columns - ruler_width
    text_width = _text_width(pagerd)
    first_col = pagerd.start_column
    last_col = min(text_width, first_col + view_cols - 1)
    show_cols = (text_width > view_cols) && (last_col >= first_col)
    w_cols = if show_cols
        9 + ndigits(first_col) + ndigits(last_col) + ndigits(text_width)
    else
        0
    end

    # Features: " frozen r×c ", " titles t ", and " ruler ".
    frozen_rows = pagerd.frozen_rows
    show_frozen = (frozen_rows > 0) || (frozen_columns > 0)
    w_frozen = show_frozen ? 10 + ndigits(frozen_rows) + ndigits(frozen_columns) : 0
    title_rows = pagerd.title_rows
    w_titles = title_rows > 0 ? 9 + ndigits(title_rows) : 0
    w_ruler = pagerd.show_ruler ? _RULER_WIDTH : 0

    # Scroll position: " NNN% ". Notice that an empty text has nothing left to scroll, so we
    # must not divide by `num_lines` here.
    percentage = if num_lines > 0
        clamp(round(Int, 100 * (1 - pagerd.cropped_lines / num_lines)), 0, 100)
    else
        100
    end

    # Key hints: " ?:help  q:quit  NNN% ".
    hint = _status_hint(:help ∈ pagerd.features)

    # == Fit ===============================================================================

    # The scroll position is kept whenever it fits next to the visible lines. The remaining
    # segments are added from the most to the least important one, and the key hints only
    # take the space that is left at the end.
    right = (used + w_lines + 6 <= cols) ? 6 : 0

    show_lines = used + w_lines + right <= cols
    show_lines && (used += w_lines)

    show_search = (w_search > 0) && (used + w_search + right <= cols)
    show_search && (used += w_search)

    show_visual = (w_visual > 0) && (used + w_visual + right <= cols)
    show_visual && (used += w_visual)

    show_cols &= used + w_cols + right <= cols
    show_cols && (used += w_cols)

    show_frozen &= used + w_frozen + right <= cols
    show_frozen && (used += w_frozen)

    show_titles = (w_titles > 0) && (used + w_titles + right <= cols)
    show_titles && (used += w_titles)

    show_ruler = (w_ruler > 0) && (used + w_ruler + right <= cols)
    show_ruler && (used += w_ruler)

    show_hint = !isempty(hint) && (right > 0) && (used + textwidth(hint) + 8 <= cols)
    show_hint && (right = textwidth(hint) + 8)

    # == Rendering =========================================================================

    if show_lines
        if num_lines == 0
            write(out, _EMPTY)
        else
            write(out, " lines ")
            _write_decimal(out, first_line)
            write(out, "–")
            _write_decimal(out, last_line)
            write(out, UInt8('/'))
            _write_decimal(out, num_lines)
            write(out, UInt8(' '))
        end
    end

    if show_search
        if num_matches > 0
            write(out, " match ")
            _write_decimal(out, match_id)
            write(out, UInt8('/'))
            _write_decimal(out, num_matches)
            write(out, UInt8(' '))
        else
            write(out, _NO_MATCH)
        end
    end

    if show_visual
        write(out, UInt8(' '))
        _write_decimal(out, num_selected)
        write(out, " selected ")
    end

    if show_cols
        write(out, " cols ")
        _write_decimal(out, first_col)
        write(out, "–")
        _write_decimal(out, last_col)
        write(out, UInt8('/'))
        _write_decimal(out, text_width)
        write(out, UInt8(' '))
    end

    if show_frozen
        write(out, " frozen ")
        _write_decimal(out, frozen_rows)
        write(out, "×")
        _write_decimal(out, frozen_columns)
        write(out, UInt8(' '))
    end

    if show_titles
        write(out, " titles ")
        _write_decimal(out, title_rows)
        write(out, UInt8(' '))
    end

    show_ruler && write(out, _RULER)

    _write_blanks(out, cols - used - right)

    if right > 0
        write(out, UInt8(' '))

        if show_hint
            write(out, hint)
            write(out, "  ")
        end

        _write_blanks(out, 3 - ndigits(percentage))
        _write_decimal(out, percentage)
        write(out, "% ")
    end

    use_color && write(out, _CRAYON_RESET)
    _move_cursor(out, rows, 1)

    _flush_screen!(pagerd)

    return nothing
end

"""
    _read_cmd!(pagerd::Pager; prefix::String = "/") -> Union{Nothing, String}

Read and edit one command from the pager input, returning `nothing` if the user cancels it
with ESC or CTRL-C.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.

# Keywords

- `prefix::String`: Prompt displayed before the command.
    (**Default**: `"/"`)
"""
function _read_cmd!(pagerd::Pager; prefix::String = "/")
    # Unpack values.
    display_size = pagerd.display_size

    # The command is edited as a vector of characters. Rebuilding a `String` at every
    # keypress made the cursor position and the string disagree whenever they were tracked
    # separately.
    chars = Char[]
    cursor = 1
    prefix_width = textwidth(prefix)
    redraw = true

    try
        while true
            if redraw
                out = _screen_buffer!(pagerd)

                # Clear the command line and write the prompt and the command. The cursor
                # is hidden during the session, so it must be shown while the command is
                # edited.
                _move_cursor(out, display_size[1], 1)
                _clear_to_eol(out)
                write(out, _SHOW_CURSOR)
                write(out, prefix)

                # The command must be truncated at the right edge of the display. Otherwise,
                # the terminal wraps the last row, the whole screen scrolls, and the frame
                # snapshot no longer describes what is on it.
                column = prefix_width + 1

                for character in chars
                    character_width = textwidth(character)
                    column + character_width > display_size[2] + 1 && break
                    write(out, character)
                    column += character_width
                end

                _move_cursor(
                    out,
                    display_size[1],
                    _cmd_cursor_column(chars, cursor, prefix_width, display_size[2]),
                )

                _flush_screen!(pagerd)

                redraw = false
            end

            k = _read_keystroke!(pagerd.input)

            if k.value == "<enter>"
                break

            elseif (k.value == "<esc>") || (k.ctrl && (k.value == "c"))
                # A cancelled command is different from an empty one: the callers keep their
                # current state instead of applying an empty value. Notice that the raw mode
                # delivers CTRL-C as a keystroke instead of raising an interrupt.
                return nothing

            elseif k.value == "<backspace>"
                if isempty(chars)
                    break
                elseif cursor > 1
                    # Delete the character before the cursor, not the last one.
                    deleteat!(chars, cursor - 1)
                    cursor -= 1
                    redraw = true
                end

            elseif k.value == "<delete>"
                if cursor <= length(chars)
                    deleteat!(chars, cursor)
                    redraw = true
                end

            elseif k.value == "<left>"
                if cursor > 1
                    cursor -= 1
                    redraw = true
                end

            elseif k.value == "<right>"
                if cursor <= length(chars)
                    cursor += 1
                    redraw = true
                end

            elseif k.value == "<home>"
                cursor = 1
                redraw = true

            elseif k.value == "<end>"
                cursor = length(chars) + 1
                redraw = true

            elseif _is_printable_keystroke(k)
                insert!(chars, cursor, only(k.value))
                cursor += 1
                redraw = true
            end

            # Every other keystroke is ignored. Otherwise, names such as `<up>` or `<F1>`
            # would be inserted verbatim into the command.
        end
    finally
        # The cursor is hidden for the rest of the session.
        _hide_cursor(pagerd.term.out_stream)
    end

    return String(chars)
end

"""
    _is_printable_keystroke(k::Keystroke) -> Bool

Return whether `k` represents a single printable character that can be typed into a command.

# Arguments

- `k::Keystroke`: Keystroke to inspect.
"""
function _is_printable_keystroke(k::Keystroke)
    (k.alt || k.ctrl) && return false
    length(k.value) == 1 || return false
    return isprint(only(k.value))
end

"""
    _cmd_cursor_column(chars::Vector{Char}, cursor::Int, prefix_width::Int,
        display_width::Int) -> Int

Return the display column of the command line cursor.

Notice that the column is a display width and not a character count, so that the cursor
stays under the insertion point when the command contains wide characters.

# Arguments

- `chars::Vector{Char}`: Characters of the command being edited.
- `cursor::Int`: One-based insertion index in `chars`.
- `prefix_width::Int`: Display width of the prompt.
- `display_width::Int`: Number of columns the terminal has.
"""
function _cmd_cursor_column(
    chars::Vector{Char}, cursor::Int, prefix_width::Int, display_width::Int
)
    column = prefix_width + 1

    @inbounds for i in 1:(cursor - 1)
        column += textwidth(chars[i])
    end

    # A command longer than the display is truncated at the right edge, so the cursor must
    # be clamped to the command line as well.
    return min(column, max(1, display_width))
end
