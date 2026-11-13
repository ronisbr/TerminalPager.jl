## Description #############################################################################
#
# Visual mode: the visual line, the range anchor, and the marked lines.
#
############################################################################################

"""
    _toggle_visual_mode!(pagerd::Pager) -> Nothing

Enter or leave the visual mode of `pagerd` and request a redraw. Leaving it clears the marks
and the range anchor, and moves the visual line back to the top of the view.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_mode!(pagerd::Pager)
    pagerd.visual_mode = !pagerd.visual_mode

    if !pagerd.visual_mode
        pagerd.visual_mode_line = 1
        empty!(pagerd.visual_mode_selected_lines)
        pagerd.visual_anchor = 0
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _visual_line_index(pagerd::Pager) -> Int

Return the line of the text under the visual line of `pagerd`.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
_visual_line_index(pagerd::Pager) = pagerd.visual_mode_line + pagerd.start_row - 1

"""
    _visual_range(pagerd::Pager) -> UnitRange{Int}

Return the lines between the range anchor of `pagerd` and its visual line, in both
directions, or an empty range when there is no anchor.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _visual_range(pagerd::Pager)
    anchor = pagerd.visual_anchor
    anchor == 0 && return 1:0

    # The anchor is a source line, whereas the range is made of rows. A hidden anchor is
    # moved to the first visible line after it.
    anchor_row = _first_row_at_or_after(pagerd, anchor)
    visual_row = _visual_line_index(pagerd)

    return min(anchor_row, visual_row):max(anchor_row, visual_row)
end

"""
    _toggle_visual_anchor!(pagerd::Pager) -> Nothing

Anchor a range at the visual line of `pagerd`, or drop the anchor if there is one, and
request a redraw. Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_anchor!(pagerd::Pager)
    pagerd.visual_mode || return nothing
    pagerd.visual_anchor =
        pagerd.visual_anchor == 0 ? _source_line(pagerd, _visual_line_index(pagerd)) : 0
    _request_redraw!(pagerd)
    return nothing
end

"""
    _selected_line_ids(pagerd::Pager) -> Vector{Int}

Return the source lines selected in the visual mode of `pagerd`, sorted and without
repetitions: the visual line, the range between the anchor and the visual line, and the
marked lines that are not hidden by the filter. The result is empty outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _selected_line_ids(pagerd::Pager)
    pagerd.visual_mode || return Int[]

    ids = Int[_source_line(pagerd, _visual_line_index(pagerd))]

    for row in _visual_range(pagerd)
        push!(ids, _source_line(pagerd, row))
    end

    # A mark hidden by the filter is not drawn, so it is not copied either.
    for line in pagerd.visual_mode_selected_lines
        (_first_row_of_line(pagerd, line) == 0) && continue
        push!(ids, line)
    end

    return sort!(unique!(ids))
end

"""
    _selected_text(pagerd::Pager) -> ViewLayout, Vector{Int}

Return the layout and the indices of the lines that the commands acting on the text of
`pagerd` must use: the source layout and the lines selected in the visual mode, or the
layout of the visible rows and all of them outside it.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _selected_text(pagerd::Pager)
    # The selection is made of source lines, whereas the whole text is the visible rows.
    pagerd.visual_mode && return pagerd.source_layout, _selected_line_ids(pagerd)
    return pagerd.text_layout, collect(1:pagerd.num_lines)
end

"""
    _num_selected_lines(pagerd::Pager) -> Int

Return the number of lines selected in the visual mode of `pagerd` without allocating, which
is the length of [`_selected_line_ids`](@ref).

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _num_selected_lines(pagerd::Pager)
    pagerd.visual_mode || return 0

    visual_row = _visual_line_index(pagerd)
    range = _visual_range(pagerd)
    num_selected = isempty(range) ? 1 : length(range)

    # The marks outside the range are counted once. A mark can only be in the list once, and
    # it stores a source line, which is mapped to its row. A hidden mark is not counted.
    for line in pagerd.visual_mode_selected_lines
        row = _first_row_of_line(pagerd, line)
        ((row == 0) || (row in range) || (row == visual_row)) && continue
        num_selected += 1
    end

    return num_selected
end

"""
    _mouse_select!(pagerd::Pager) -> Nothing

Move the visual line of `pagerd` to the row of the last mouse click, or mark it if the click
was on the visual line, and request a redraw. Clicks outside the scrollable rows of the text
and outside the visual mode are ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _mouse_select!(pagerd::Pager)
    pagerd.visual_mode || return nothing

    view_rows = _view_rows(pagerd)
    clicked_line = pagerd.mouse_row - _column_ruler_rows(pagerd) - pagerd.frozen_rows
    last_line = min(view_rows, pagerd.num_lines - pagerd.start_row + 1)

    (1 <= clicked_line <= last_line) || return nothing

    if clicked_line == pagerd.visual_mode_line
        _toggle_visual_line!(pagerd)
    else
        pagerd.visual_mode_line = clicked_line
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _toggle_visual_line!(pagerd::Pager) -> Nothing

Mark the visual line of `pagerd`, or unmark it if it is already marked, and request a
redraw. Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_line!(pagerd::Pager)
    if pagerd.visual_mode
        # With an anchor, the whole range is marked and the anchor is dropped.
        if pagerd.visual_anchor != 0
            for row in _visual_range(pagerd)
                line = _source_line(pagerd, row)
                (line in pagerd.visual_mode_selected_lines) ||
                    push!(pagerd.visual_mode_selected_lines, line)
            end

            pagerd.visual_anchor = 0
            _request_redraw!(pagerd)
            return nothing
        end

        visual_str_id = _source_line(pagerd, _visual_line_index(pagerd))

        # If the line is already selected, we will deselect it. Notice that a line can only
        # be in the list once, so `findfirst` is enough and does not allocate.
        id = findfirst(==(visual_str_id), pagerd.visual_mode_selected_lines)

        if isnothing(id)
            push!(pagerd.visual_mode_selected_lines, visual_str_id)
        else
            deleteat!(pagerd.visual_mode_selected_lines, id)
        end

        # Without this, marking a line produced no feedback until the user happened to
        # press another key.
        _request_redraw!(pagerd)
    end

    return nothing
end
