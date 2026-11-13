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
const _MODE_FREEZE = "FREEZE"
const _MODE_TITLES = "TITLES"
const _MODE_FILTER = "FILTER"
const _MODE_WIDTH = 6

const _NO_MATCH = "no match"
const _NO_MATCH_WIDTH = textwidth(_NO_MATCH)
const _RULER = "ruler"
const _RULER_WIDTH = textwidth(_RULER)

# Position tokens, like the ones of `vim`. Every token, including a percentage, is three
# columns wide. The line style writes `L` and the top row over the number of lines instead.
const _POSITION_ALL = "All"
const _POSITION_TOP = "Top"
const _POSITION_BOTTOM = "Bot"
const _POSITION_WIDTH = 3
const _POSITION_LINE_PREFIX = "L"

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
# help action, of the search mode, of the visual mode, of the freeze selection mode, and of
# the normal mode with an active filter, with and without the help action.
const _STATUS_HINTS =
    Ref{Tuple{Int, String, String, String, String, String, String, String}}((
        -1, "", "", "", "", "", "", ""
    ))

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
    _prompt_key!(pagerd::Pager, prompt::String) -> Union{Nothing, Char}

Show `prompt` on the status row of `pagerd`, wait for one keystroke, and return its
character, or `nothing` if the keystroke is ESC, CTRL-C, or not a printable character
without modifiers. The screen is repainted if the display size changes while waiting, and
the caller must request a redraw to restore the status row.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.
- `prompt::String`: Prompt shown on the status row.
"""
function _prompt_key!(pagerd::Pager, prompt::String)
    redraw = true

    while true
        if redraw
            out = _screen_buffer!(pagerd)
            _move_cursor(out, pagerd.display_size[1], 1)
            _clear_to_eol(out)
            write(out, prompt)
            _flush_screen!(pagerd)
            redraw = false
        end

        # A change of the display size repaints the view and the prompt without waiting for
        # the keystroke.
        if !_wait_for_input!(pagerd)
            _update_display_size!(pagerd)
            _paint_view!(pagerd)
            redraw = true
            continue
        end

        k = _read_keystroke!(pagerd.input)
        ((k.value == "<esc>") || (k.ctrl && (k.value == "c"))) && return nothing
        _is_printable_keystroke(k) || return nothing
        return only(k.value)
    end
end

"""
    _prompt_position!(pagerd::Pager, prefix::String) -> Tuple{Symbol, Symbol, Int}

Prompt for a position with `prefix` and return the status, the kind, and the value. The
status is `:value`, `:cancel`, `:empty`, or `:invalid`, like [`_prompt_number!`](@ref),
which also sets the error message. The kind is `:absolute` for a line number, `:percent` for
a number followed by `%`, `:relative` for a number starting with `+` or `-`, or `:end` for
`\$` or `end`, whose value is zero.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.
- `prefix::String`: Prompt displayed before the position.
"""
function _prompt_position!(pagerd::Pager, prefix::String)
    cmd_input = _read_cmd!(pagerd; prefix = prefix)
    isnothing(cmd_input) && return :cancel, :absolute, 0

    input = strip(cmd_input)
    isempty(input) && return :empty, :absolute, 0
    ((input == "\$") || (input == "end")) && return :value, :end, 0

    kind = if endswith(input, '%')
        input = input[1:prevind(input, lastindex(input))]
        :percent
    elseif startswith(input, '+') || startswith(input, '-')
        :relative
    else
        :absolute
    end

    # `tryparse` accepts a leading sign, so the relative offsets parse as they are typed.
    value = tryparse(Int, input; base = 10)

    if isnothing(value)
        _set_message!(pagerd, "Not a number: $cmd_input"; kind = :error)
        return :invalid, :absolute, 0
    end

    return :value, kind, value
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

Return the key hints of the status line for `mode`, which is `:normal`, `:search`,
`:visual`, `:freeze`, or `:filter`, like `?:help  q:quit` or `n:next  N:prev  Esc:clear`.

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
        # Enter is not an action in the freeze selection mode, so its hint is assembled by
        # hand.
        freeze_apply = _KEY_NAMES["<enter>"] * ":apply"
        freeze_cancel = _join_hints((:quit_search, "cancel"))
        freeze_hint = if isempty(freeze_cancel)
            freeze_apply
        else
            freeze_apply * " "^_ITEM_GAP * freeze_cancel
        end

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
                (:toggle_visual_anchor, "range"),
                (:yank, "yank"),
                (:toggle_visual_mode, "leave"),
            ),
            freeze_hint,
            _join_hints(
                (:help, "help"),
                (:filter, "filter"),
                (:quit_search, "clear"),
                (:quit, "quit"),
            ),
            _join_hints((:filter, "filter"), (:quit_search, "clear"), (:quit, "quit")),
        )
        _STATUS_HINTS[] = cached
    end

    mode === :search && return cached[4]
    mode === :visual && return cached[5]
    mode === :freeze && return cached[6]
    mode === :filter && return with_help ? cached[7] : cached[8]
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
normal mode, or with the colored name of the search, the visual, or the freeze selection
mode, followed by the active match, the number of selected lines, or the selected rows and
columns. The right side
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
    rows, cols = pagerd.display_size
    use_color = get(pagerd.term.out_stream, :color, true)::Bool

    out = _screen_buffer!(pagerd)

    # Move the cursor to the last row. The row must be cleared explicitly, because nothing
    # else overwrites the text left behind by the command editor.
    _move_cursor(out, rows, 1)
    _clear_to_eol(out)

    if cols > 0
        use_color && write(out, pagerd.display_config.status_bar)
        _write_status_line!(out, pagerd, cols, use_color)
        use_color && write(out, _SGR_RESET)
        _move_cursor(out, rows, 1)
    end

    _flush_screen!(pagerd)

    return nothing
end

"""
    _write_status_line!(out::IOBuffer, pagerd::Pager, cols::Int, use_color::Bool) -> Nothing

Write the content of the status line of `pagerd` to `out`, which must already hold the
cursor movement to the last row, the clear, and the base face. The content is `cols`
columns wide, and the faces are written only if `use_color` is `true`.

# Arguments

- `out::IOBuffer`: Buffer assembling everything sent to the terminal.
- `pagerd::Pager`: Pager state to draw.
- `cols::Int`: Number of columns of the display.
- `use_color::Bool`: Whether the terminal supports color.
"""
function _write_status_line!(out::IOBuffer, pagerd::Pager, cols::Int, use_color::Bool)
    num_lines = pagerd.num_lines
    display_config = pagerd.display_config
    base = display_config.status_bar

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
    position_style = pagerd.status_position
    start_row = pagerd.start_row
    w_position = _position_width(position_style, start_row, num_lines)

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
            _write_position(
                out, position_style, start_row, num_lines, at_top, at_bottom, percentage
            )
        end

        return nothing
    end

    # == Segment Widths ====================================================================

    # Everything but the numbers is constant, so the widths are computed from the number of
    # digits. Assembling strings here allocated at every keystroke.
    # The prompt is written in the base face, whereas the mode names have their own faces.
    # The on-screen selections take over the row while they are active.
    in_freeze = pagerd.mode == :freeze_selection
    in_titles = pagerd.mode == :title_selection
    in_selection = in_freeze || in_titles
    in_visual = pagerd.visual_mode && !in_selection
    in_search = pagerd.mode == :searching
    show_mode = in_selection || in_visual || in_search
    w_mode = show_mode ? _MODE_WIDTH : _PROMPT_WIDTH
    mode_name = if in_freeze
        _MODE_FREEZE
    elseif in_titles
        _MODE_TITLES
    elseif in_visual
        _MODE_VISUAL
    elseif in_search
        _MODE_SEARCH
    else
        _PROMPT
    end
    mode_face = if in_selection
        display_config.mode_freeze
    elseif in_visual
        display_config.mode_visual
    else
        display_config.mode_search
    end

    # Details of the mode: "r×c", "t", "n lines", "match i/n", or "no match". The search
    # restricted to a range of columns shows the range, like "@12:20", before the matches.
    selection_rows = pagerd.freeze_selection_rows
    selection_columns = pagerd.freeze_selection_columns
    num_selected = _num_selected_lines(pagerd)
    num_matches = length(pagerd.ordered_search_matches)
    match_id = pagerd.active_search_match_id
    search_columns = pagerd.search_columns
    w_columns = in_search ? _column_range_width(search_columns) : 0
    w_detail = if in_freeze
        ndigits(selection_rows) + 1 + ndigits(selection_columns)
    elseif in_titles
        ndigits(selection_rows)
    elseif in_visual
        ndigits(num_selected) + (num_selected == 1 ? 5 : 6)
    elseif in_search
        (w_columns > 0 ? w_columns + _ITEM_GAP : 0) +
        (num_matches > 0 ? 7 + ndigits(match_id) + ndigits(num_matches) : _NO_MATCH_WIDTH)
    else
        0
    end

    # Feature tags: "frozen r×c", "titles t", and "ruler". The frozen tag is hidden while
    # an on-screen selection is active, because the detail shows the selection instead.
    frozen_columns = pagerd.frozen_columns
    show_frozen = !in_selection && ((frozen_rows > 0) || (frozen_columns > 0))
    w_frozen = show_frozen ? 8 + ndigits(frozen_rows) + ndigits(frozen_columns) : 0
    title_rows = pagerd.title_rows
    w_titles = title_rows > 0 ? 7 + ndigits(title_rows) : 0
    w_ruler = pagerd.show_ruler ? _RULER_WIDTH : 0
    num_tags = (w_frozen > 0) + (w_titles > 0) + (w_ruler > 0)
    w_tags = w_frozen + w_titles + w_ruler + max(num_tags - 1, 0) * _ITEM_GAP

    # The active filter is shown after the mode details, with its pattern and the visible
    # lines over the total.
    filter_active = !isnothing(pagerd.filter_regex)
    total_lines = length(pagerd.source_layout)
    w_filter = if filter_active
        _MODE_WIDTH + 1 + textwidth(pagerd.filter_pattern) + 1 + ndigits(num_lines) + 1 +
        ndigits(total_lines)
    else
        0
    end

    # Key hints of the current mode.
    hint_mode = if in_selection
        :freeze
    elseif in_visual
        :visual
    elseif in_search
        :search
    elseif filter_active
        :filter
    else
        :normal
    end
    hint = _status_hint(hint_mode, :help ∈ pagerd.features)
    w_hint = textwidth(hint)

    # Hidden text: "‹" when the view is scrolled to the right and "›" when the text is cut
    # at the right edge. Notice that the hints follow the last rendered frame.
    hidden_left = pagerd.start_column > _first_scrollable_column(pagerd)
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
        return nothing
    end

    left = w_mode
    gap = 1

    show_position = left + gap + w_position <= cols
    right = show_position ? w_position : 0

    show_detail = (w_detail > 0) && (left + _ITEM_GAP + w_detail + gap + right <= cols)
    show_detail && (left += _ITEM_GAP + w_detail)

    show_filter = (w_filter > 0) && (left + _ITEM_GAP + w_filter + gap + right <= cols)
    show_filter && (left += _ITEM_GAP + w_filter)

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

        if in_freeze
            _write_decimal(out, selection_rows)
            write(out, "×")
            _write_decimal(out, selection_columns)
        elseif in_titles
            _write_decimal(out, selection_rows)
        elseif in_visual
            _write_decimal(out, num_selected)
            write(out, num_selected == 1 ? " line" : " lines")
        else
            if w_columns > 0
                _write_column_range(out, search_columns)
                _write_blanks(out, _ITEM_GAP)
            end

            if num_matches > 0
                write(out, "match ")
                _write_decimal(out, match_id)
                write(out, UInt8('/'))
                _write_decimal(out, num_matches)
            else
                write(out, _NO_MATCH)
            end
        end
    end

    if show_filter
        _write_blanks(out, _ITEM_GAP)
        use_color && write(out, display_config.mode_filter)
        write(out, _MODE_FILTER)
        use_color && write(out, base)
        write(out, UInt8(' '))
        write(out, pagerd.filter_pattern)
        write(out, UInt8(' '))
        _write_decimal(out, num_lines)
        write(out, UInt8('/'))
        _write_decimal(out, total_lines)
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

    show_position && _write_position(
        out, position_style, start_row, num_lines, at_top, at_bottom, percentage
    )

    return nothing
end

"""
    _column_range_width(columns::UnitRange{Int}) -> Int

Return the width of the search column range tag written by [`_write_column_range`](@ref),
which is zero when the search is not restricted.

# Arguments

- `columns::UnitRange{Int}`: Printable columns in which a match must start.
"""
function _column_range_width(columns::UnitRange{Int})
    first_column = first(columns)
    last_column = Base.last(columns)
    ((first_column <= 1) && (last_column == typemax(Int))) && return 0

    # `@`, the first column unless it is the first one, `:`, and the last column unless the
    # range is open.
    return 2 + (first_column > 1 ? ndigits(first_column) : 0) +
           (last_column < typemax(Int) ? ndigits(last_column) : 0)
end

"""
    _write_column_range(io::IO, columns::UnitRange{Int}) -> Nothing

Write the search column range tag to `io`: `@a:b`, `@a:` for an open end, or `@:b` for a
range starting at the first column.

# Arguments

- `io::IO`: Output stream to update.
- `columns::UnitRange{Int}`: Printable columns in which a match must start.
"""
function _write_column_range(io::IO, columns::UnitRange{Int})
    first_column = first(columns)
    last_column = Base.last(columns)
    write(io, UInt8('@'))
    (first_column > 1) && _write_decimal(io, first_column)
    write(io, UInt8(':'))
    (last_column < typemax(Int)) && _write_decimal(io, last_column)
    return nothing
end

"""
    _position_width(style::Symbol, start_row::Int, num_lines::Int) -> Int

Return the width of the position of the status line for `style`, which is `:percent`,
`:line`, or `:both`, when the view starts at `start_row` and the text has `num_lines` lines.

# Arguments

- `style::Symbol`: Style of the position.
- `start_row::Int`: First visible row.
- `num_lines::Int`: Number of lines of the text.
"""
function _position_width(style::Symbol, start_row::Int, num_lines::Int)
    style === :percent && return _POSITION_WIDTH

    # `L`, the row, `/`, and the number of lines.
    w_line = 2 + ndigits(start_row) + ndigits(num_lines)
    style === :line && return w_line

    return w_line + 1 + _POSITION_WIDTH
end

"""
    _write_position(
        io::IO,
        style::Symbol,
        start_row::Int,
        num_lines::Int,
        at_top::Bool,
        at_bottom::Bool,
        percentage::Int
    ) -> Nothing

Write the position of the status line to `io` with the `style` `:percent`, `:line`, or
`:both`. The percent token is always three columns wide: `All` if the whole text is visible,
`Top`, `Bot`, or `percentage` right-aligned before `%`. The line token is `L`, `start_row`,
`/`, and `num_lines`. Both tokens are separated by one blank in the style `:both`.

# Arguments

- `io::IO`: Output stream to update.
- `style::Symbol`: Style of the position.
- `start_row::Int`: First visible row.
- `num_lines::Int`: Number of lines of the text.
- `at_top::Bool`: Whether the view shows the first scrollable line.
- `at_bottom::Bool`: Whether the view shows the last line.
- `percentage::Int`: Percentage of the text above the bottom of the view.
"""
function _write_position(
    io::IO,
    style::Symbol,
    start_row::Int,
    num_lines::Int,
    at_top::Bool,
    at_bottom::Bool,
    percentage::Int,
)
    if style !== :percent
        write(io, _POSITION_LINE_PREFIX)
        _write_decimal(io, start_row)
        write(io, UInt8('/'))
        _write_decimal(io, num_lines)
        style === :line && return nothing
        write(io, UInt8(' '))
    end

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

# Paths confirmed at the save prompt in this session, from the oldest to the newest.
const _SAVE_HISTORY = String[]
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
- `on_change::Any`: Callable object invoked with the command whenever its text changes and
    no other keystroke is buffered, or `nothing`. It must return a `String`, which is shown
    at the right of the prompt row when it fits, for example a live match count.
    (**Default**: `nothing`)
- `on_key::Any`: Callable object invoked with every `Keystroke` before the editor handles
    it, or `nothing`. It must return `true` if it consumed the keystroke, in which case the
    command is treated as changed, so that `on_change` runs and the prompt is repainted.
    (**Default**: `nothing`)
"""
function _read_cmd!(
    pagerd::Pager;
    prefix::String = "/",
    history::Union{Nothing, Vector{String}} = nothing,
    on_change = nothing,
    on_key = nothing,
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

            # A change of the display size repaints the view and the prompt without waiting
            # for a keystroke.
            if !_wait_for_input!(pagerd)
                _update_display_size!(pagerd)
                _paint_view!(pagerd)
                display_size = pagerd.display_size
                redraw = true
                continue
            end

            k = _read_keystroke!(pagerd.input)
            value = k.value

            if !isnothing(on_key) && on_key(k)::Bool
                # The caller handled the keystroke, for example a toggle of a search option,
                # which can change the result of the command without changing its text.
                changed = true

            elseif value == "<enter>"
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

            # A changed command is processed only when no other keystroke is buffered.
            # Otherwise, a pasted pattern ran the callback, which can search the whole text,
            # once per character, although only the last result was shown.
            if changed && !_has_buffered_input(pagerd.input)
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
