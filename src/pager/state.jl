## Description #############################################################################
#
# State of a pager session: the sizes of the view, the mapping between the rows of the view
# and the lines of the text, the viewport limits, and the messages.
#
############################################################################################

"""
    _get_pager_display_size(p::Pager) -> Tuple{Int, Int}

Return the available pager rows and columns after reserving the status bar row and the
scrollbar column, if it is shown.

# Arguments

- `p::Pager`: Pager state whose display size is queried.
"""
function _get_pager_display_size(p::Pager)
    rows, cols = p.display_size

    # We need to remove one row due to the status bar, two rows due to the column ruler, and
    # one column due to the scrollbar. Notice that a degenerate terminal must not produce
    # negative sizes.
    rows = max(rows - 1 - _column_ruler_rows(p), 0)
    p.show_scrollbar && (cols = max(cols - 1, 0))

    return rows, cols
end

"""
    _ruler_width(num_lines::Int) -> Int
    _ruler_width(p::Pager) -> Int

Return the number of columns the line-number ruler occupies for `num_lines` lines, or for the
text of `p`.

# Arguments

- `num_lines::Int`: Number of lines in the pager text.
- `p::Pager`: Pager state whose ruler is measured.
"""
function _ruler_width(num_lines::Int)
    # This must match how `_textview` sizes the ruler. Notice that `ndigits` is defined for
    # 0, whereas `floor(Int, log10(num_lines))` throws an `InexactError` for an empty text.
    return ndigits(num_lines) + 3
end

_ruler_width(p::Pager) = _ruler_width(_ruler_line_count(p))

"""
    _ruler_line_count(p::Pager) -> Int

Return the largest number written in the line-number ruler of `p`, which is the source line
of the last row when a filter is active, or the number of rows.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
function _ruler_line_count(p::Pager)
    row_to_line = p.row_to_line
    isnothing(row_to_line) && return p.num_lines
    return isempty(row_to_line) ? 0 : row_to_line[end]
end

"""
    _shown_ruler_width(p::Pager) -> Int

Return the number of columns of the display of `p` taken by the line-number ruler, which is
`0` if it is hidden.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_shown_ruler_width(p::Pager) = p.show_ruler ? _ruler_width(p) : 0

"""
    _first_scrollable_column(p::Pager) -> Int

Return the first printable column of the text of `p` that scrolls, which is the one after
the frozen columns.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_first_scrollable_column(p::Pager) = max(1, p.frozen_columns + 1)

"""
    _clamp_row(p::Pager, row::Int) -> Int

Return `row` moved into the rows of the text of `p` that scroll, which are the ones after
the frozen rows.

# Arguments

- `p::Pager`: Pager state to inspect.
- `row::Int`: Row of the view.
"""
function _clamp_row(p::Pager, row::Int)
    min_row = _first_scrollable_row(p)
    return clamp(row, min_row, max(min_row, p.num_lines))
end

"""
    _reset_crop!(p::Pager) -> Nothing

Reset the numbers of lines and columns of `p` cropped by the last frame. They describe a
view that does not exist anymore, so they must be computed again by the next
[`_view!`](@ref) instead of being used by the movements.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _reset_crop!(p::Pager)
    p.cropped_lines = 0
    p.cropped_columns = 0
    return nothing
end

"""
    _empty_result() -> PagerResult

Return the result of a text that was printed instead of shown by a pager session.
"""
_empty_result() = PagerResult(String[], 1, 1, "")

"""
    _source_line(p::Pager, row::Int) -> Int

Return the source line shown at the `row` of the view of `p`, which is the row itself when
no filter is active.

# Arguments

- `p::Pager`: Pager state to inspect.
- `row::Int`: Row of the view.
"""
function _source_line(p::Pager, row::Int)
    row_to_line = p.row_to_line
    isnothing(row_to_line) && return row
    return (1 <= row <= length(row_to_line)) ? row_to_line[row] : row
end

"""
    _first_row_of_line(p::Pager, line::Int) -> Int

Return the row of the view of `p` showing the source `line`, or `0` if the line is hidden by
the filter. The row is the line itself when no filter is active.

# Arguments

- `p::Pager`: Pager state to inspect.
- `line::Int`: Source line.
"""
function _first_row_of_line(p::Pager, line::Int)
    line_to_row = p.line_to_row
    isnothing(line_to_row) && return line
    return (1 <= line <= length(line_to_row)) ? line_to_row[line] : 0
end

"""
    _first_row_at_or_after(p::Pager, line::Int) -> Int

Return the first row of the view of `p` showing the source `line` or a line after it, or the
last row if every line after it is hidden. The row is the line itself when no filter is
active.

# Arguments

- `p::Pager`: Pager state to inspect.
- `line::Int`: Source line.
"""
function _first_row_at_or_after(p::Pager, line::Int)
    row_to_line = p.row_to_line
    isnothing(row_to_line) && return line
    isempty(row_to_line) && return 1
    return min(searchsortedfirst(row_to_line, line), length(row_to_line))
end

"""
    _rebuild_view_layout!(p::Pager; top_line::Int = _source_line(p, p.start_row)) -> Nothing

Rebuild the rows shown by `p` from its source lines and its filter, and update everything
that depends on them: the number of rows, the width of the text, the viewport, which keeps
`top_line` or the first visible line after it at the top, the visual line, and the search
matches. The frame is invalidated, so that the next redraw repaints the whole screen.

# Arguments

- `p::Pager`: Pager state to update.

# Keywords

- `top_line::Int`: Source line to keep at the top of the view.
    (**Default**: the source line at the top of the view)
"""
function _rebuild_view_layout!(p::Pager; top_line::Int = _source_line(p, p.start_row))
    source = p.source_layout
    regex = p.filter_regex

    if isnothing(regex)
        p.text_layout = source
        p.row_to_line = nothing
        p.line_to_row = nothing
    else
        # The frozen and the title rows are always shown.
        kept_rows = max(p.frozen_rows, p.title_rows)
        rows = _filter_rows(source, regex, p.filter_inverted, kept_rows)
        line_to_row = zeros(Int, length(source))

        for (row, line) in enumerate(rows)
            line_to_row[line] = row
        end

        p.text_layout = ViewLayout(source, rows)
        p.row_to_line = rows
        p.line_to_row = line_to_row
    end

    p.num_lines = length(p.text_layout)
    p.text_width = -1
    _reset_crop!(p)

    p.start_row = _clamp_row(p, _first_row_at_or_after(p, top_line))
    _clamp_viewport!(p)
    _clamp_visual_line!(p)

    # The matches are computed over the rows, so the search runs again. The active match is
    # the first one at or after the top of the view.
    search_regex = p.search_regex

    if !isnothing(search_regex)
        _find_matches!(p, search_regex; columns = p.search_columns)
        num_matches = length(p.ordered_search_matches)
        p.active_search_match_id =
            num_matches == 0 ? 0 : min(p.active_search_match_id + 1, num_matches)
    end

    _invalidate_frame!(p)
    _request_redraw!(p)

    return nothing
end

"""
    _request_redraw!(p::Pager) -> Bool

Mark `p` for redraw and return the assigned value, `true`.

# Arguments

- `p::Pager`: Pager state to mark for redraw.
"""
_request_redraw!(p::Pager) = (p.redraw = true)

"""
    _set_message!(p::Pager, message::String; kind::Symbol = :info) -> Nothing

Show `message` on the command line of `p` until the next keystroke and request a redraw.

Unlike a modal message, the next keystroke is processed normally instead of being consumed
to dismiss the message.

# Arguments

- `p::Pager`: Pager state to update.
- `message::String`: Message to show.

# Keywords

- `kind::Symbol`: Kind of the message, `:info` or `:error`, which selects its decoration.
    (**Default**: `:info`)
"""
function _set_message!(p::Pager, message::String; kind::Symbol = :info)
    p.message = message
    p.message_kind = kind
    _request_redraw!(p)
    return nothing
end

"""
    _clear_message!(p::Pager) -> Nothing

Remove the command line message of `p`, if any, and request a redraw in that case.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _clear_message!(p::Pager)
    isempty(p.message) && return nothing
    p.message = ""
    p.message_kind = :info
    _request_redraw!(p)
    return nothing
end

"""
    _first_scrollable_row(p::Pager) -> Int

Return the first row of the text of `p` that scrolls, which is the one after the frozen
rows.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_first_scrollable_row(p::Pager) = max(1, p.frozen_rows + 1)

"""
    _view_rows(p::Pager) -> Int

Return the number of rows of the display of `p` that show scrolling text, that is, without
the status line, the column ruler, and the frozen rows.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_view_rows(p::Pager) = p.display_size[1] - 1 - _column_ruler_rows(p) - p.frozen_rows

"""
    _column_ruler_rows(p::Pager) -> Int

Return the number of rows of the display of `p` taken by the column ruler, which is `2` when
it is shown and `0` otherwise.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_column_ruler_rows(p::Pager) = p.show_column_ruler ? 2 : 0

"""
    _selecting_on_screen(p::Pager) -> Bool

Return whether `p` is in one of the on-screen selection modes, which draw the guides over the
view.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
function _selecting_on_screen(p::Pager)
    return (p.mode == :freeze_selection) || (p.mode == :title_selection)
end

"""
    _frame_rows(p::Pager) -> Int

Return the number of screen rows of the frame of `p`, which are the rows of the view plus the
column ruler.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_frame_rows(p::Pager) = _get_pager_display_size(p)[1] + _column_ruler_rows(p)

"""
    _update_display_size!(p::Pager) -> Nothing

Update the recorded display size and request a redraw when the terminal size changes.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _update_display_size!(p::Pager)
    # If the terminal size has changed, then we need to redraw the view.
    newdsize::Tuple{Int, Int} = displaysize(p.term.out_stream)

    if newdsize != p.display_size
        p.display_size = newdsize
        _clamp_viewport!(p)

        # If the display shrinks, the visual line can be below the last row of the view.
        # In this case, the view is scrolled so that the visual line stays on the same line
        # of the text, at the last row. Otherwise, it would not be shown, and the commands
        # would not agree on which line it is.
        if p.visual_mode
            overflow = p.visual_mode_line - max(_view_rows(p), 1)

            if overflow > 0
                p.start_row += overflow
                p.visual_mode_line -= overflow
            end

            _clamp_visual_line!(p)
        end

        # The terminal dropped or revealed rows, so we no longer know what is on screen.
        _invalidate_frame!(p)
        _request_redraw!(p)
    end

    return nothing
end

"""
    _clamp_viewport!(p::Pager) -> Nothing

Keep the viewport of `p` inside the text after the display size changed.

A view that ends past the last line or past the last column is pulled back so that the
screen stays full, like `less` does. The first visible row and column never move into the
frozen region.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _clamp_viewport!(p::Pager)
    rows, cols = _get_pager_display_size(p)
    ((rows <= 0) || (cols <= 0)) && return nothing

    min_row = _first_scrollable_row(p)
    view_rows = _view_rows(p)
    max_row = max(min_row, p.num_lines - view_rows + 1)
    p.start_row = clamp(p.start_row, min_row, max_row)

    _clamp_start_column!(p)

    return nothing
end

"""
    _clamp_start_column!(p::Pager) -> Nothing

Keep the first visible column of `p` between the first column that scrolls and the one that
shows the end of the widest line at the right edge of the view, so that the view neither
enters the frozen columns nor ends past the text. Nothing happens if the view has no
columns.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _clamp_start_column!(p::Pager)
    cols = _get_pager_display_size(p)[2]
    cols <= 0 && return nothing

    min_col = _first_scrollable_column(p)
    view_cols = cols - p.frozen_columns - _shown_ruler_width(p)
    max_col = max(min_col, _text_width(p) - view_cols + 1)
    p.start_column = clamp(p.start_column, min_col, max_col)

    return nothing
end

"""
    _text_width(p::Pager) -> Int

Return the printable width of the widest line of `p`, computing and caching it on the first
call.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
function _text_width(p::Pager)
    if p.text_width < 0
        # The layout measured every line while it was prepared.
        p.text_width = maximum(p.text_layout.printable_widths; init = 0)
    end

    return p.text_width
end
