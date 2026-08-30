## Description #############################################################################
#
# Functions related to the command line.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The status line is assembled from constant pieces and numbers, so that it does not
# allocate at every keystroke. The normal mode shows a prompt glyph, which must not be `:`
# because that is the prompt of the go to line command, and the other modes show their
# names, which have the same width.
const _PROMPT = "❯"
const _PROMPT_WIDTH = 1
const _MODE_SEARCH = "SEARCH"
const _MODE_VISUAL = "VISUAL"
const _MODE_WIDTH = 6

const _NO_MATCH = "no match"
const _NO_MATCH_WIDTH = textwidth(_NO_MATCH)
const _RULER = "ruler"
const _RULER_WIDTH = textwidth(_RULER)

# Position tokens, like the ones of `vim`. Every token, including a percentage, is three
# columns wide.
const _POSITION_ALL = "All"
const _POSITION_TOP = "Top"
const _POSITION_BOTTOM = "Bot"
const _POSITION_WIDTH = 3

# Hints telling that the text continues beyond the left and the right edges of the view.
# They occupy a slot of two columns whenever one of them is shown, so that the segments at
# their left do not move while the view scrolls horizontally.
const _HIDDEN_LEFT = "‹"
const _HIDDEN_RIGHT = "›"
const _HIDDEN_WIDTH = 2

# Icons telling the kind of a message at a glance. Both have a display width of one.
const _MESSAGE_INFO_ICON = "✓"
const _MESSAGE_ERROR_ICON = "✗"

# Gaps of the status line: between the items of a group, like the feature tags, and between
# the groups, like the key hints and the position.
const _ITEM_GAP = 2
const _GROUP_GAP = 3

# Key hints of the status line, rebuilt when the key bindings change. The entries are the
# generation they were built for, and the hints of the normal mode with and without the
# help action, of the search mode, and of the visual mode.
const _STATUS_HINTS = Ref{Tuple{Int, String, String, String, String}}((-1, "", "", "", ""))

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
    _prompt_number!(pagerd::Pager, prefix::String) -> Tuple{Symbol, Int}

Prompt for an integer on the command line of `pagerd` and return the status and the number
typed by the user. The prompt shows `label` and the `current` value in brackets, or the raw
`prefix`.

The status is `:value` when a number was typed, `:empty` when the prompt was left empty,
`:cancel` when the prompt was cancelled, and `:invalid` when the input is not a number. In
the last case, an error message is shown on the command line until the next keystroke. The
number is `0` unless the status is `:value`.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.
- `label::String`: Description of the requested number, shown in the prompt.
- `current::Int`: Current value, shown in the prompt.
- `prefix::String`: Prompt displayed before the number.
"""
function _prompt_number!(pagerd::Pager, label::String, current::Int)
    return _prompt_number!(pagerd, "$label [$current] › ")
end

function _prompt_number!(pagerd::Pager, prefix::String)
    cmd_input = _read_cmd!(pagerd; prefix = prefix)
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
    _status_hint(mode::Symbol, with_help::Bool) -> String

Return the key hints of the status line for `mode`, which is `:normal`, `:search`, or
`:visual`, like `?:help  q:quit` or `n:next  N:prev  Esc:clear`.

The hints are rebuilt only when the key bindings change, so that the status line does not
allocate at every frame.

# Arguments

- `mode::Symbol`: Mode whose hints are returned.
- `with_help::Bool`: Include the hint of the help action in the normal mode.
"""
function _status_hint(mode::Symbol, with_help::Bool)
    generation = _KEYBINDINGS_GENERATION[]
    cached = _STATUS_HINTS[]

    if cached[1] != generation
        cached = (
            generation,
            _join_hints((:help, "help"), (:quit, "quit")),
            _join_hints((:quit, "quit")),
            _join_hints(
                (:next_match, "next"),
                (:previous_match, "prev"),
                (:quit_search, "clear"),
            ),
            _join_hints(
                (:select_visual_mode_line, "mark"),
                (:yank, "yank"),
                (:toggle_visual_mode, "leave"),
            ),
        )
        _STATUS_HINTS[] = cached
    end

    mode === :search && return cached[4]
    mode === :visual && return cached[5]
    return with_help ? cached[2] : cached[3]
end

"""
    _join_hints(entries::Tuple{Symbol, String}...) -> String

Join the key hints of `entries`, each one an action and its label, like `n:next`, using the
shortest key bound to the action and skipping the unbound ones.

# Arguments

- `entries::Tuple{Symbol, String}...`: Actions and their labels.
"""
function _join_hints(entries::Tuple{Symbol, String}...)
    buf = IOBuffer()

    for (action, label) in entries
        key = _primary_key(action)
        isnothing(key) && continue
        (position(buf) > 0) && _write_blanks(buf, _ITEM_GAP)
        write(buf, key, ':', label)
    end

    return String(take!(buf))
end

"""
    _redraw_status_bar!(pagerd::Pager) -> Nothing

Redraw the status line of `pagerd` on the last row of the display.

The row is quiet: nothing is drawn with a background. It begins with the prompt `❯` in the
normal mode, or with the colored name of the search or the visual mode, followed by the
active match or the number of selected lines. The right side
holds, from the left, the tags of the enabled features, the key hints of the current mode,
the hints that the text continues beyond the left or the right edge of the view, which
keep a slot of two columns so that the key hints do not move while the view scrolls
horizontally, and the position, which is `All` when the whole text is visible, `Top`,
`Bot`, or the percentage of the text above the bottom of the view. A pending message
replaces the left side. When the display is too narrow, the key hints are dropped first,
then the feature tags, the hidden text hints, and the mode details, so that the mode name
and the position survive longest.

# Arguments

- `pagerd::Pager`: Pager state to redraw.
"""
function _redraw_status_bar!(pagerd::Pager)
    term = pagerd.term
    rows, cols = pagerd.display_size
    num_lines = pagerd.num_lines
    use_color = get(term.out_stream, :color, true)::Bool
    display_config = pagerd.display_config
    base = display_config.status_bar

    out = _screen_buffer!(pagerd)

    # Move the cursor to the last row. The row must be cleared explicitly, because nothing
    # else overwrites the text left behind by the command editor.
    _move_cursor(out, rows, 1)
    _clear_to_eol(out)

    if cols <= 0
        _flush_screen!(pagerd)
        return nothing
    end

    use_color && write(out, base)

    # == Position ==========================================================================

    # `All`, `Top`, `Bot`, or `NN%`. The percentage never reaches 100, because the bottom of
    # the text has its own token, and an empty text has nothing to scroll.
    frozen_rows = pagerd.frozen_rows
    cropped_lines = pagerd.cropped_lines
    at_top = pagerd.start_row <= _first_scrollable_row(pagerd)
    at_bottom = cropped_lines == 0
    percentage = if num_lines > 0
        clamp(round(Int, 100 * (1 - cropped_lines / num_lines)), 1, 99)
    else
        0
    end
    w_position = _POSITION_WIDTH

    # == Message ===========================================================================

    message = pagerd.message

    if !isempty(message)
        # The message replaces the left side until the next keystroke. It is shown with an
        # icon and a color that tell its kind at a glance. The position is kept if it fits.
        is_error = pagerd.message_kind === :error
        show_position = 1 + 1 + w_position <= cols
        available = cols - (show_position ? w_position + 1 : 0)
        width = 0

        message_face = is_error ? display_config.message_error : display_config.message_info
        use_color && write(out, message_face)

        if available >= 1
            write(out, is_error ? _MESSAGE_ERROR_ICON : _MESSAGE_INFO_ICON)
            width += 1
        end

        if available >= 3
            write(out, UInt8(' '))
            width += 1

            for c in message
                character_width = textwidth(c)
                (width + character_width > available) && break
                write(out, c)
                width += character_width
            end
        end

        use_color && write(out, base)

        if show_position
            _write_blanks(out, cols - width - w_position)
            _write_position(out, num_lines, at_top, at_bottom, percentage)
        end

        use_color && write(out, _SGR_RESET)
        _move_cursor(out, rows, 1)
        _flush_screen!(pagerd)
        return nothing
    end

    # == Segment Widths ====================================================================

    # Everything but the numbers is constant, so the widths are computed from the number of
    # digits. Assembling strings here allocated at every keystroke.
    # The prompt is written in the base face, whereas the mode names have their own faces.
    in_visual = pagerd.visual_mode
    in_search = pagerd.mode == :searching
    show_mode = in_visual || in_search
    w_mode = show_mode ? _MODE_WIDTH : _PROMPT_WIDTH
    mode_name = in_visual ? _MODE_VISUAL : (in_search ? _MODE_SEARCH : _PROMPT)
    mode_face = in_visual ? display_config.mode_visual : display_config.mode_search

    # Details of the mode: "n selected", "match i/n", or "no match".
    num_selected = length(pagerd.visual_mode_selected_lines)
    num_matches = length(pagerd.ordered_search_matches)
    match_id = pagerd.active_search_match_id
    w_detail = if in_visual
        ndigits(num_selected) + 9
    elseif in_search
        num_matches > 0 ? 7 + ndigits(match_id) + ndigits(num_matches) : _NO_MATCH_WIDTH
    else
        0
    end

    # Feature tags: "frozen r×c", "titles t", and "ruler".
    frozen_columns = pagerd.frozen_columns
    show_frozen = (frozen_rows > 0) || (frozen_columns > 0)
    w_frozen = show_frozen ? 8 + ndigits(frozen_rows) + ndigits(frozen_columns) : 0
    title_rows = pagerd.title_rows
    w_titles = title_rows > 0 ? 7 + ndigits(title_rows) : 0
    w_ruler = pagerd.show_ruler ? _RULER_WIDTH : 0
    num_tags = (w_frozen > 0) + (w_titles > 0) + (w_ruler > 0)
    w_tags = w_frozen + w_titles + w_ruler + max(num_tags - 1, 0) * _ITEM_GAP

    # Key hints of the current mode.
    hint_mode = in_visual ? :visual : (in_search ? :search : :normal)
    hint = _status_hint(hint_mode, :help ∈ pagerd.features)
    w_hint = textwidth(hint)

    # Hidden text: "‹" when the view is scrolled to the right and "›" when the text is cut
    # at the right edge. Notice that the hints follow the last rendered frame.
    hidden_left = pagerd.start_column > max(1, frozen_columns + 1)
    hidden_right = pagerd.cropped_columns > 0
    w_arrows = (hidden_left || hidden_right) ? _HIDDEN_WIDTH : 0

    # == Fit ===============================================================================

    # The segments are added from the most to the least important one: the prompt or the
    # mode name, the position, the mode details, the hidden text hints, the feature tags,
    # and the key hints. At least one blank separates the left and the right sides.
    if w_mode > cols
        # Only a mode name can be cut, because the prompt is one column wide and the display
        # has at least one. Every mode name is ASCII, so the bytes are the columns.
        (use_color && show_mode) && write(out, mode_face)
        GC.@preserve mode_name unsafe_write(out, pointer(mode_name), UInt(cols))
        use_color && write(out, _SGR_RESET)
        _move_cursor(out, rows, 1)
        _flush_screen!(pagerd)
        return nothing
    end

    left = w_mode
    gap = 1

    show_position = left + gap + w_position <= cols
    right = show_position ? w_position : 0

    show_detail = (w_detail > 0) && (left + _ITEM_GAP + w_detail + gap + right <= cols)
    show_detail && (left += _ITEM_GAP + w_detail)

    show_arrows =
        (w_arrows > 0) &&
        show_position &&
        (left + gap + right + w_arrows + _ITEM_GAP <= cols)
    show_arrows && (right += w_arrows + _ITEM_GAP)

    show_tags =
        (w_tags > 0) &&
        show_position &&
        (left + gap + right + w_tags + _GROUP_GAP <= cols)
    show_tags && (right += w_tags + _GROUP_GAP)

    show_hint =
        (w_hint > 0) &&
        show_position &&
        (left + gap + right + w_hint + _GROUP_GAP <= cols)
    show_hint && (right += w_hint + _GROUP_GAP)

    # == Rendering =========================================================================

    (use_color && show_mode) && write(out, mode_face)
    write(out, mode_name)
    (use_color && show_mode) && write(out, base)

    if show_detail
        _write_blanks(out, _ITEM_GAP)

        if in_visual
            _write_decimal(out, num_selected)
            write(out, " selected")
        elseif num_matches > 0
            write(out, "match ")
            _write_decimal(out, match_id)
            write(out, UInt8('/'))
            _write_decimal(out, num_matches)
        else
            write(out, _NO_MATCH)
        end
    end

    _write_blanks(out, cols - left - right)

    hint_face = display_config.status_hint

    if show_tags
        use_color && write(out, hint_face)
        written = 0

        if show_frozen
            write(out, "frozen ")
            _write_decimal(out, frozen_rows)
            write(out, "×")
            _write_decimal(out, frozen_columns)
            written += 1
        end

        if w_titles > 0
            (written > 0) && _write_blanks(out, _ITEM_GAP)
            write(out, "titles ")
            _write_decimal(out, title_rows)
            written += 1
        end

        if w_ruler > 0
            (written > 0) && _write_blanks(out, _ITEM_GAP)
            write(out, _RULER)
        end

        use_color && write(out, base)
        _write_blanks(out, _GROUP_GAP)
    end

    if show_hint
        use_color && write(out, hint_face)
        write(out, hint)
        use_color && write(out, base)
        _write_blanks(out, _GROUP_GAP)
    end

    if show_arrows
        use_color && write(out, hint_face)
        hidden_left ? write(out, _HIDDEN_LEFT) : write(out, UInt8(' '))
        hidden_right ? write(out, _HIDDEN_RIGHT) : write(out, UInt8(' '))
        use_color && write(out, base)
        _write_blanks(out, _ITEM_GAP)
    end

    show_position && _write_position(out, num_lines, at_top, at_bottom, percentage)

    use_color && write(out, _SGR_RESET)
    _move_cursor(out, rows, 1)

    _flush_screen!(pagerd)

    return nothing
end

"""
    _write_position(
        io::IO,
        num_lines::Int,
        at_top::Bool,
        at_bottom::Bool,
        percentage::Int
    ) -> Nothing

Write the position of the status line to `io`, which is always three columns wide: `All`
if the whole text is visible, `Top`, `Bot`, or `percentage` right-aligned before `%`.

# Arguments

- `io::IO`: Output stream to update.
- `num_lines::Int`: Number of lines of the text.
- `at_top::Bool`: Whether the view shows the first scrollable line.
- `at_bottom::Bool`: Whether the view shows the last line.
- `percentage::Int`: Percentage of the text above the bottom of the view.
"""
function _write_position(
    io::IO,
    num_lines::Int,
    at_top::Bool,
    at_bottom::Bool,
    percentage::Int,
)
    if (num_lines == 0) || (at_top && at_bottom)
        write(io, _POSITION_ALL)
    elseif at_top
        write(io, _POSITION_TOP)
    elseif at_bottom
        write(io, _POSITION_BOTTOM)
    else
        _write_blanks(io, 2 - ndigits(percentage))
        _write_decimal(io, percentage)
        write(io, UInt8('%'))
    end

    return nothing
end

# Search patterns confirmed in this session, from the oldest to the newest, recalled with
# the up and down keys at the search prompt.
const _SEARCH_HISTORY = String[]
const _MAX_HISTORY = 100

"""
    _push_history!(history::Vector{String}, entry::String) -> Nothing

Append `entry` to `history` as its newest element, removing a previous copy of it and the
oldest entries beyond `_MAX_HISTORY`. An empty entry is ignored.

# Arguments

- `history::Vector{String}`: History to update.
- `entry::String`: Command to record.
"""
function _push_history!(history::Vector{String}, entry::String)
    isempty(entry) && return nothing
    filter!(!=(entry), history)
    push!(history, entry)

    while length(history) > _MAX_HISTORY
        popfirst!(history)
    end

    return nothing
end

"""
    _read_cmd!(pagerd::Pager; kwargs...) -> Union{Nothing, String}

Read and edit one command from the pager input, returning `nothing` if the user cancels it
with ESC or CTRL-C.

The editor supports the cursor keys, Home, End, Backspace, Delete, CTRL-A and CTRL-E to jump
to the beginning and to the end of the command, CTRL-W to delete the word before the cursor,
CTRL-U to clear the command, and the up and down keys to recall the commands in `history`.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.

# Keywords

- `prefix::String`: Prompt displayed before the command.
    (**Default**: `"/"`)
- `history::Union{Nothing, Vector{String}}`: Previous commands, from the oldest to the
    newest, or `nothing` to disable the recall.
    (**Default**: `nothing`)
- `on_change::Any`: Callable object invoked with the command whenever its text changes, or
    `nothing`. It must return a `String`, which is shown at the right of the prompt row
    when it fits, for example a live match count.
    (**Default**: `nothing`)
"""
function _read_cmd!(
    pagerd::Pager;
    prefix::String = "/",
    history::Union{Nothing, Vector{String}} = nothing,
    on_change = nothing,
)
    term = pagerd.term
    use_color = get(term.out_stream, :color, true)::Bool
    # Unpack values.
    display_size = pagerd.display_size

    # The command is edited as a vector of characters. Rebuilding a `String` at every
    # keypress made the cursor position and the string disagree whenever they were tracked
    # separately.
    chars = Char[]
    cursor = 1
    prefix_width = textwidth(prefix)
    redraw = true
    changed = false
    status = ""

    # The history is browsed from the newest entry to the oldest one. The command typed
    # before the browsing started is kept, so that it is restored when going past the newest
    # entry.
    history_length = isnothing(history) ? 0 : length(history)
    history_index = history_length + 1
    draft = Char[]

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

                # The status is right-aligned after the command when it fits.
                status_width = textwidth(status)

                if (status_width > 0) && (column + status_width <= display_size[2])
                    _write_blanks(out, display_size[2] - status_width - column + 1)
                    use_color && write(out, pagerd.display_config.command_status)
                    write(out, status)
                    use_color && write(out, _SGR_RESET)
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
            value = k.value

            if value == "<enter>"
                break

            elseif (value == "<esc>") || (k.ctrl && (value == "c"))
                # A cancelled command is different from an empty one: the callers keep their
                # current state instead of applying an empty value. Notice that the raw mode
                # delivers CTRL-C as a keystroke instead of raising an interrupt.
                return nothing

            elseif (value == "<backspace>") || (k.ctrl && (value == "h"))
                # Some terminals send CTRL-H for the Backspace key.
                if isempty(chars)
                    break
                elseif cursor > 1
                    # Delete the character before the cursor, not the last one.
                    deleteat!(chars, cursor - 1)
                    cursor -= 1
                    changed = true
                end

            elseif value == "<delete>"
                if cursor <= length(chars)
                    deleteat!(chars, cursor)
                    changed = true
                end

            elseif value == "<left>"
                if cursor > 1
                    cursor -= 1
                    redraw = true
                end

            elseif value == "<right>"
                if cursor <= length(chars)
                    cursor += 1
                    redraw = true
                end

            elseif (value == "<home>") || (k.ctrl && (value == "a"))
                cursor = 1
                redraw = true

            elseif (value == "<end>") || (k.ctrl && (value == "e"))
                cursor = length(chars) + 1
                redraw = true

            elseif value == "<shiftin>"
                # CTRL-U clears the command. Notice that the raw mode reports the key with
                # this name.
                empty!(chars)
                cursor = 1
                changed = true

            elseif k.ctrl && (value == "w")
                # Delete the word before the cursor together with the spaces after it.
                stop = cursor - 1

                while (stop >= 1) && isspace(chars[stop])
                    stop -= 1
                end

                while (stop >= 1) && !isspace(chars[stop])
                    stop -= 1
                end

                if stop < cursor - 1
                    deleteat!(chars, (stop + 1):(cursor - 1))
                    cursor = stop + 1
                    changed = true
                end

            elseif (value == "<up>") && !isnothing(history)
                if history_index > 1
                    (history_index == history_length + 1) && (draft = copy(chars))
                    history_index -= 1
                    chars = collect(history[history_index])
                    cursor = length(chars) + 1
                    changed = true
                end

            elseif (value == "<down>") && !isnothing(history)
                if history_index <= history_length
                    history_index += 1

                    chars = if history_index > history_length
                        draft
                    else
                        collect(history[history_index])
                    end

                    cursor = length(chars) + 1
                    changed = true
                end

            elseif _is_printable_keystroke(k)
                insert!(chars, cursor, only(value))
                cursor += 1
                changed = true
            end

            # Every other keystroke is ignored. Otherwise, names such as `<F1>` would be
            # inserted verbatim into the command.

            if changed
                changed = false
                redraw = true
                isnothing(on_change) || (status = on_change(String(chars))::String)
            end
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
