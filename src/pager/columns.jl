## Description #############################################################################
#
# Selection on the screen of the range of columns that restricts a search.
#
############################################################################################

"""
    _select_columns_key!(pagerd::Pager, k::Keystroke, chars::Vector{Char}, cursor::Int) -> Int

Select on the screen the range of columns of the search input in `chars` if `k` is a second
`@` typed right after the one that begins the input, and return the new index of the cursor
in `chars`, or `0` if `k` is another keystroke.

The selected range replaces the one written in `chars`, as `@a:b `, keeping the pattern
after it, and the cursor moves to the end of the input. A cancelled selection leaves `chars`
as they are. A pasted `@` is not a request to select the columns, so nothing happens while
other keystrokes are buffered.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.
- `k::Keystroke`: Keystroke typed at the search prompt.
- `chars::Vector{Char}`: Characters of the search input, which are modified.
- `cursor::Int`: One-based insertion index of the cursor in `chars`.
"""
function _select_columns_key!(pagerd::Pager, k::Keystroke, chars::Vector{Char}, cursor::Int)
    ((k.value == "@") && !k.alt && !k.ctrl) || return 0
    ((cursor == 2) && (chars[1] == '@')) || return 0
    _has_buffered_input(pagerd.input) && return 0

    input = String(chars)
    columns = _select_columns!(pagerd, _typed_columns(input))
    isnothing(columns) && return cursor

    empty!(chars)
    append!(chars, _replace_typed_columns(input, columns))

    return length(chars) + 1
end

"""
    _select_columns!(pagerd::Pager, initial::UnitRange{Int}) ->
        Union{Nothing, UnitRange{Int}}

Select a range of printable columns of the text of `pagerd` on the screen and return it, or
`nothing` if the selection was cancelled or if there is nothing to select.

A cursor marks one column with the background of the face `search_columns`. It starts at the
first column of `initial`, or at the first visible column if `initial` is empty. The
horizontal movement keys move the cursor, scrolling the view when it leaves it. The first
Enter fixes the column under the cursor, the movements then extend the range from it, and
the second Enter applies the range. A mouse press fixes the column under the pointer and a
drag extends the range from it. The keys bound to `:quit`, `:quit_search`, and `:quit_eot`
cancel the selection. In every case, the mode and the first visible column of the pager are
restored.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `initial::UnitRange{Int}`: Range of columns written in the search input, or an empty
    range.
"""
function _select_columns!(pagerd::Pager, initial::UnitRange{Int})
    max_column = _max_selectable_column(pagerd)
    max_column < 1 && return nothing

    saved_mode = pagerd.mode
    saved_columns = pagerd.highlighted_columns
    start_column = pagerd.start_column

    first_visible = pagerd.frozen_columns > 0 ? 1 : start_column

    pagerd.mode = :column_selection
    pagerd.column_selection_anchor = 0
    pagerd.column_selection_cursor = clamp(
        isempty(initial) ? first_visible : first(initial), 1, max_column
    )
    _show_column_selection!(pagerd)
    _request_redraw!(pagerd)

    # The prompt shows the cursor of the terminal, which is not used by the selection.
    _hide_cursor(pagerd.term.out_stream)

    selected = nothing

    try
        while true
            pagerd.redraw && _paint!(pagerd)

            # A change of the display size repaints the view without waiting for a
            # keystroke. The cursor must stay inside the columns that can be shown.
            if !_wait_for_input!(pagerd)
                _update_display_size!(pagerd)
                _move_column_selection!(pagerd, nothing, _INCOMPLETE_KEYSTROKE)
                _request_redraw!(pagerd)
                continue
            end

            k = _read_keystroke!(pagerd.input)

            # Enter is bound to a movement, so it must be checked before the bindings.
            if (k.value == "<enter>") || (k.value == "<keypad_enter>")
                anchor = pagerd.column_selection_anchor
                cursor = pagerd.column_selection_cursor

                if anchor > 0
                    selected = min(anchor, cursor):max(anchor, cursor)
                    break
                end

                pagerd.column_selection_anchor = cursor
                _request_redraw!(pagerd)
                continue
            end

            action = _pager_action(k)

            if (action === :quit) || (action === :quit_search) || (action === :quit_eot)
                break
            end

            _move_column_selection!(pagerd, action, k)
        end
    finally
        pagerd.mode = saved_mode
        pagerd.highlighted_columns = saved_columns
        pagerd.column_selection_anchor = 0
        pagerd.column_selection_cursor = 0

        # Notice that the display size can have changed while the selection was active.
        pagerd.start_column = start_column
        _clamp_start_column!(pagerd)
        _request_redraw!(pagerd)
    end

    return selected
end

"""
    _max_selectable_column(pagerd::Pager) -> Int

Return the last printable column the column selection of `pagerd` can reach, which is the
width of the widest line, or `0` if no column can be selected because the text or the view
is empty. If only frozen columns fit in the view, the columns after the view cannot be
shown, so they cannot be selected.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _max_selectable_column(pagerd::Pager)
    rows, cols = _get_pager_display_size(pagerd)
    width = cols - _shown_ruler_width(pagerd)
    ((rows <= 0) || (width <= 0)) && return 0

    text_width = _text_width(pagerd)
    return width > pagerd.frozen_columns ? text_width : min(text_width, width)
end

"""
    _show_column_selection!(pagerd::Pager) -> Nothing

Highlight the columns of the column selection of `pagerd`, which are the one under the
cursor or the range between the fixed column and the cursor, and scroll the view
horizontally so that the cursor is visible.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _show_column_selection!(pagerd::Pager)
    anchor = pagerd.column_selection_anchor
    cursor = pagerd.column_selection_cursor

    pagerd.highlighted_columns = if anchor > 0
        min(anchor, cursor):max(anchor, cursor)
    else
        cursor:cursor
    end

    # The frozen columns are always visible.
    frozen_columns = pagerd.frozen_columns
    cursor <= frozen_columns && return nothing

    cols = _get_pager_display_size(pagerd)[2]
    view_cols = cols - frozen_columns - _shown_ruler_width(pagerd)
    view_cols <= 0 && return nothing

    start_column = max(pagerd.start_column, frozen_columns + 1)

    if cursor < start_column
        pagerd.start_column = cursor
    elseif cursor > start_column + view_cols - 1
        pagerd.start_column = cursor - view_cols + 1
    end

    return nothing
end

"""
    _move_column_selection!(pagerd::Pager, action::Union{Nothing, Symbol}, k::Keystroke) ->
        Nothing

Move the cursor of the column selection of `pagerd` according to the movement `action` or to
the position of the mouse event `k`, keep it inside the columns that can be selected, and
request a redraw if the selection changed.

The single movements move the cursor by one column, the fast ones by ten columns, and
`:bol` and `:eol` move it to the first and to the last column of the text. A mouse press
inside the view or on the column ruler fixes the column under the pointer, and a drag moves
the cursor to it, which extends the range. Every other keystroke is ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `action::Union{Nothing, Symbol}`: Resolved pager action of `k`.
- `k::Keystroke`: Keystroke to process.
"""
function _move_column_selection!(pagerd::Pager, action, k::Keystroke)
    anchor = pagerd.column_selection_anchor
    cursor = pagerd.column_selection_cursor
    max_column = max(_max_selectable_column(pagerd), 1)

    if (k.value == "<mouse_press>") || (k.value == "<mouse_drag>")
        column = _column_at(pagerd, k.x, k.y)

        if column > 0
            cursor = column
            (k.value == "<mouse_press>") && (anchor = clamp(column, 1, max_column))
        end
    elseif action === :left
        cursor -= 1
    elseif action === :right
        cursor += 1
    elseif action === :fastleft
        cursor -= 10
    elseif action === :fastright
        cursor += 10
    elseif action === :bol
        cursor = 1
    elseif action === :eol
        cursor = max_column
    end

    cursor = clamp(cursor, 1, max_column)
    (anchor > 0) && (anchor = clamp(anchor, 1, max_column))

    if (cursor != pagerd.column_selection_cursor) ||
        (anchor != pagerd.column_selection_anchor)
        pagerd.column_selection_cursor = cursor
        pagerd.column_selection_anchor = anchor
        _show_column_selection!(pagerd)
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _column_at(pagerd::Pager, x::Int, y::Int) -> Int

Return the printable column of the text of `pagerd` shown at the column `x` and the row `y`
of the display, both one-based, or `0` if the position is on the line-number ruler, on the
scrollbar, or on the status line. A position on the column ruler is the column it numbers.

# Arguments

- `pagerd::Pager`: Pager state with the viewport.
- `x::Int`: One-based column of the display.
- `y::Int`: One-based row of the display.
"""
function _column_at(pagerd::Pager, x::Int, y::Int)
    rows, cols = _get_pager_display_size(pagerd)
    width = cols - _shown_ruler_width(pagerd)
    cell = x - _shown_ruler_width(pagerd)
    view_row = y - _column_ruler_rows(pagerd)

    ((1 <= cell <= width) && (y >= 1) && (view_row <= rows)) || return 0

    # The title rows are not scrolled.
    title = 1 <= view_row <= _shown_title_rows(pagerd)

    return _text_column(pagerd, cell, width, title)
end
