## Description #############################################################################
#
# Positions in the text: the go to line command, the bookmarks, the position restored from
# a previous session, and the position report.
#
############################################################################################

"""
    _goto_line!(pagerd::Pager) -> Nothing

Prompt for a position and show that line at the top of the view of `pagerd`, like `less`
does, and request a redraw. The position is a line number, a percentage of the text like
`50%`, an offset from the current top row like `+10` or `-5`, or `\$` or `end` for the last
page. The view never moves into the frozen rows, and an invalid or cancelled position keeps
it.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _goto_line!(pagerd::Pager)
    status, kind, value = _prompt_position!(pagerd, ":")

    if status === :value
        _remember_position!(pagerd)
        num_lines = pagerd.num_lines

        # The offset and the percentage are typed by the user, so that they are limited to
        # the values that can change the result. Otherwise, a very large one overflows.
        line = if kind === :relative
            pagerd.start_row + clamp(value, -num_lines, num_lines)
        elseif kind === :percent
            round(Int, num_lines * clamp(value, 0, 100) / 100)
        elseif kind === :end
            num_lines - _view_rows(pagerd) + 1
        elseif !isnothing(pagerd.row_to_line)
            # A line number is a source line. A hidden one is reported, and the view goes to
            # the first visible line after it.
            target = clamp(value, 1, max(1, length(pagerd.source_layout)))
            row = _first_row_of_line(pagerd, target)

            if row == 0
                row = _first_row_at_or_after(pagerd, target)
                _set_message!(pagerd, "Line $target is hidden by the filter")
            end

            row
        else
            value
        end

        pagerd.start_row = _clamp_row(pagerd, line)
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _restore_state!(pagerd::Pager, result::PagerResult) -> Nothing

Restore in `pagerd` the viewport and the search recorded in `result` by a previous session
over the same text. The viewport is clamped to the text and to the frozen rows and columns,
and a search pattern that is not valid anymore is ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `result::PagerResult`: Result of the previous session.
"""
function _restore_state!(pagerd::Pager, result::PagerResult)
    pagerd.start_row = _clamp_row(pagerd, result.start_row)
    pagerd.start_column = max(result.start_column, pagerd.frozen_columns + 1)
    _clamp_viewport!(pagerd)

    if !isempty(result.search_pattern)
        parsed = _parse_search_input(result.search_pattern)

        if !isnothing(parsed) && !isempty(parsed[1])
            regex = _try_regex(parsed[1]; literal = pagerd.literal_search)

            # The search is applied like when it is confirmed at the prompt, except that
            # the view is not moved to the active match, which is the first one at or after
            # the top of the view. A regex that fails while matching is also ignored.
            if !isnothing(regex)
                try
                    _find_matches!(pagerd, regex; columns = parsed[2])
                    _change_active_match!(pagerd, true)
                    pagerd.search_regex = regex
                    pagerd.search_pattern = result.search_pattern
                    pagerd.mode = :searching
                catch err
                    isnothing(_regex_error(err)) && rethrow()
                end
            end
        end
    end

    return nothing
end

"""
    _remember_position!(pagerd::Pager) -> Nothing

Record the first visible row and column of `pagerd` as the position before a jump, so that
`''` returns to it.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _remember_position!(pagerd::Pager)
    pagerd.last_position = (pagerd.start_row, pagerd.start_column)
    return nothing
end

"""
    _set_bookmark!(pagerd::Pager) -> Nothing

Prompt for a letter and bookmark the first visible row of `pagerd`, or the visual line in
the visual mode, together with the first visible column. A cancelled prompt keeps the
bookmarks, and a key that is not a letter is reported.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _set_bookmark!(pagerd::Pager)
    c = _prompt_key!(pagerd, "m")
    _request_redraw!(pagerd)
    isnothing(c) && return nothing

    if !isletter(c)
        _set_message!(pagerd, "Bookmarks are letters"; kind = :error)
        return nothing
    end

    row = pagerd.visual_mode ? _visual_line_index(pagerd) : pagerd.start_row
    pagerd.bookmarks[c] = (_source_line(pagerd, row), pagerd.start_column)
    _set_message!(pagerd, "Mark $c set")

    return nothing
end

"""
    _goto_bookmark!(pagerd::Pager) -> Nothing

Prompt for a letter and move the view of `pagerd` to its bookmark, or back to the position
before the last jump when the key is `'`. The bookmarked line is shown at the top of the
view, where the visual line is placed too. A missing bookmark is reported.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _goto_bookmark!(pagerd::Pager)
    c = _prompt_key!(pagerd, "'")
    _request_redraw!(pagerd)
    isnothing(c) && return nothing

    target = if c == '\''
        pagerd.last_position
    else
        get(pagerd.bookmarks, c, (0, 0))
    end

    if target == (0, 0)
        message = c == '\'' ? "No previous position" : "Mark $c not set"
        _set_message!(pagerd, message; kind = :error)
        return nothing
    end

    _remember_position!(pagerd)

    # The bookmarks store source lines, whereas the previous position is a row.
    row = c == '\'' ? target[1] : _first_row_at_or_after(pagerd, target[1])
    pagerd.start_row = _clamp_row(pagerd, row)
    pagerd.start_column = max(target[2], pagerd.frozen_columns + 1)
    pagerd.visual_mode_line = 1

    return nothing
end

"""
    _bookmark_rows(pagerd::Pager) -> Union{Nothing, Set{Int}}

Return the rows marked in the line-number ruler of `pagerd`, which are its bookmarked lines,
or `nothing` if there is none.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _bookmark_rows(pagerd::Pager)
    isempty(pagerd.bookmarks) && return nothing
    rows = Set{Int}()

    for position in values(pagerd.bookmarks)
        row = _first_row_of_line(pagerd, first(position))
        (row > 0) && push!(rows, row)
    end

    return rows
end

"""
    _show_position!(pagerd::Pager) -> Nothing

Show a message with the lines and the columns of the text that are visible in `pagerd`, the
totals, and the percentage of the text above the bottom of the view.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _show_position!(pagerd::Pager)
    num_lines = pagerd.num_lines
    view_rows = max(_view_rows(pagerd), 0)
    first_row = min(pagerd.start_row, num_lines)
    last_row = min(pagerd.start_row + view_rows - 1, num_lines)
    percentage = num_lines > 0 ? round(Int, 100 * last_row / num_lines) : 0

    cols = _get_pager_display_size(pagerd)[2]
    view_cols = max(cols - pagerd.frozen_columns - _shown_ruler_width(pagerd), 0)
    text_width = _text_width(pagerd)
    first_col = min(pagerd.start_column, text_width)
    last_col = min(pagerd.start_column + view_cols - 1, text_width)

    _set_message!(
        pagerd,
        "Lines $first_row-$last_row of $num_lines ($percentage%) · " *
            "Columns $first_col-$last_col of $text_width",
    )

    return nothing
end
