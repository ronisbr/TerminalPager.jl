## Description #############################################################################
#
# Frozen rows and columns and title rows: the prompts that change them and their selection
# on the screen.
#
############################################################################################

"""
    _change_freeze!(pagerd::Pager) -> Nothing

Prompt for the numbers of frozen rows and columns of `pagerd`, apply them, and request a
redraw. An invalid or cancelled number of rows also skips the prompt for the columns.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _change_freeze!(pagerd::Pager)
    status, frozen_rows = _prompt_number!(pagerd, "Frozen rows", pagerd.frozen_rows)

    # An invalid or cancelled number of rows also skips the prompt for the columns.
    if status in (:value, :empty)
        if status === :value
            # The clamped field value must be used here, not the raw parsed one, and the
            # first visible row must stay inside the text.
            pagerd.frozen_rows = max(0, frozen_rows)
            pagerd.start_row = _clamp_row(pagerd, pagerd.start_row)
            pagerd.visual_mode_line = 1
            _reset_crop!(pagerd)
        end

        status, frozen_columns = _prompt_number!(
            pagerd, "Frozen columns", pagerd.frozen_columns
        )

        if status === :value
            pagerd.frozen_columns = max(0, frozen_columns)
            pagerd.start_column = max(pagerd.start_column, pagerd.frozen_columns + 1)
            _reset_crop!(pagerd)
        end

        if status !== :invalid
            _set_message!(
                pagerd,
                "Frozen $(pagerd.frozen_rows) rows × $(pagerd.frozen_columns) columns",
            )
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _select_on_screen!(pagerd::Pager, mode::Symbol) -> Nothing

Select on the screen the frozen rows and columns of `pagerd`, if `mode` is
`:freeze_selection`, or its title rows, if `mode` is `:title_selection`, and request a
redraw.

The view moves to the top-left corner of the text, so that the screen rows and columns are
the text rows and columns. Only the title rows stay frozen while the frozen rows and
columns are selected, and nothing stays frozen while the title rows are. The rows and the
columns that would be selected are marked by guide lines drawn with the face
`freeze_guide`, the title selection having only the one under the rows. The movement keys
and the mouse move the selection, Enter applies it, and the keys bound to `:quit`,
`:quit_search`, and `:quit_eot` cancel it. In both cases, the viewport is restored and
clamped to the frozen region.

Since the titles are always frozen, applying more title rows than frozen rows freezes them
as well. Nothing happens, and an error message is shown, if the text is empty, if the view
has no rows, or if the title rows do not fit in the view while the frozen rows are selected.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `mode::Symbol`: Selection mode, `:freeze_selection` or `:title_selection`.
"""
function _select_on_screen!(pagerd::Pager, mode::Symbol)
    selecting_titles = mode == :title_selection
    rows, cols = _get_pager_display_size(pagerd)

    start_row = pagerd.start_row
    start_column = pagerd.start_column
    frozen_rows = pagerd.frozen_rows
    frozen_columns = pagerd.frozen_columns
    title_rows = pagerd.title_rows

    if pagerd.num_lines == 0
        message = selecting_titles ? "Nothing to select" : "Nothing to freeze"
        _set_message!(pagerd, message; kind = :error)
        return nothing
    end

    if (rows <= 0) || (cols <= 0) || (!selecting_titles && (title_rows >= rows))
        message = if selecting_titles
            "Not enough rows to select the title rows"
        else
            "Not enough rows to show the $title_rows title rows"
        end

        _set_message!(pagerd, message; kind = :error)
        return nothing
    end

    # Everything but the rows kept frozen scrolls to the top-left corner of the text.
    kept_rows = selecting_titles ? 0 : title_rows
    pagerd.frozen_rows = kept_rows
    pagerd.frozen_columns = 0
    pagerd.title_rows = kept_rows
    pagerd.start_row = kept_rows + 1
    pagerd.start_column = 1

    applied = _run_selection!(
        pagerd,
        mode,
        selecting_titles ? title_rows : frozen_rows,
        selecting_titles ? 0 : frozen_columns,
    )

    pagerd.frozen_rows = frozen_rows
    pagerd.frozen_columns = frozen_columns
    pagerd.title_rows = title_rows

    if applied && selecting_titles
        title_rows = pagerd.freeze_selection_rows
        pagerd.title_rows = title_rows

        # The titles are always frozen.
        if title_rows > frozen_rows
            pagerd.frozen_rows = title_rows
            pagerd.visual_mode_line = 1
            _set_message!(
                pagerd, "$title_rows title rows, frozen rows raised to $title_rows"
            )
        else
            _set_message!(pagerd, "$title_rows title rows")
        end
    elseif applied
        pagerd.frozen_rows = pagerd.freeze_selection_rows
        pagerd.frozen_columns = pagerd.freeze_selection_columns
        pagerd.visual_mode_line = 1
        _set_message!(
            pagerd, "Frozen $(pagerd.frozen_rows) rows × $(pagerd.frozen_columns) columns"
        )
    end

    _end_selection!(pagerd, start_row, start_column)

    return nothing
end

"""
    _run_selection!(pagerd::Pager, mode::Symbol, rows::Int, columns::Int) -> Bool

Run the on-screen selection loop of `pagerd` in `mode`, starting with `rows` rows and
`columns` columns selected, and return whether the selection was applied.

The loop redraws the screen, keeps the selection inside the view when the display is
resized, and reads the keystrokes directly: Enter applies the selection, the keys bound to
`:quit`, `:quit_search`, and `:quit_eot` cancel it, and the other keystrokes move it. The
mode of the pager is restored when the loop ends.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `mode::Symbol`: Selection mode, `:freeze_selection` or `:title_selection`.
- `rows::Int`: Initial number of selected rows.
- `columns::Int`: Initial number of selected columns.
"""
function _run_selection!(pagerd::Pager, mode::Symbol, rows::Int, columns::Int)
    saved_mode = pagerd.mode
    pagerd.mode = mode
    pagerd.freeze_selection_rows = rows
    pagerd.freeze_selection_columns = columns
    _clamp_freeze_selection!(pagerd)
    _request_redraw!(pagerd)

    applied = false

    try
        while true
            pagerd.redraw && _paint!(pagerd)

            # A change of the display size repaints the view without waiting for a
            # keystroke. The selection must stay inside the new view.
            if !_wait_for_input!(pagerd)
                _update_display_size!(pagerd)
                _clamp_freeze_selection!(pagerd)
                _request_redraw!(pagerd)
                continue
            end

            k = _read_keystroke!(pagerd.input)

            # Enter is bound to a movement, so it must be checked before the bindings.
            if (k.value == "<enter>") || (k.value == "<keypad_enter>")
                applied = true
                break
            end

            action = _pager_action(k)

            if (action === :quit) || (action === :quit_search) || (action === :quit_eot)
                break
            end

            _move_freeze_selection!(pagerd, action, k)
        end
    finally
        pagerd.mode = saved_mode
    end

    return applied
end

"""
    _end_selection!(pagerd::Pager, start_row::Int, start_column::Int) -> Nothing

Restore the viewport of `pagerd` to `start_row` and `start_column` after an on-screen
selection, keep it outside the frozen region, and request a redraw.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `start_row::Int`: First visible row to restore.
- `start_column::Int`: First visible column to restore.
"""
function _end_selection!(pagerd::Pager, start_row::Int, start_column::Int)
    # Notice that the display size can have changed while the selection was active.
    pagerd.start_row = start_row
    pagerd.start_column = start_column
    _clamp_viewport!(pagerd)
    _reset_crop!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _freeze_selection_bounds(pagerd::Pager) -> Tuple{Int, Int, Int}

Return the minimum and the maximum numbers of rows, and the maximum number of columns, the
freeze selection of `pagerd` can have.

The rows are bounded by the title rows, which always stay frozen, and by the view and the
text. The columns are bounded by the view, without the ruler, and by the widest line, and
the title selection has no columns. The guides are drawn after the selected rows and
columns, so the view bounds leave one row and one column for them.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _freeze_selection_bounds(pagerd::Pager)
    rows, cols = _get_pager_display_size(pagerd)
    ruler_width = _shown_ruler_width(pagerd)

    max_rows = max(min(rows - 1, pagerd.num_lines), 0)
    min_rows = clamp(pagerd.title_rows, 0, max_rows)
    max_columns = if pagerd.mode == :title_selection
        0
    else
        max(min(cols - ruler_width - 1, _text_width(pagerd)), 0)
    end

    return min_rows, max_rows, max_columns
end

"""
    _clamp_freeze_selection!(pagerd::Pager) -> Nothing

Keep the freeze selection of `pagerd` inside its bounds.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _clamp_freeze_selection!(pagerd::Pager)
    min_rows, max_rows, max_columns = _freeze_selection_bounds(pagerd)
    pagerd.freeze_selection_rows = clamp(pagerd.freeze_selection_rows, min_rows, max_rows)
    pagerd.freeze_selection_columns = clamp(pagerd.freeze_selection_columns, 0, max_columns)
    return nothing
end

"""
    _move_freeze_selection!(pagerd::Pager, action::Union{Nothing, Symbol}, k::Keystroke) ->
        Nothing

Move the freeze selection of `pagerd` according to the movement `action` or to the position
of the mouse event `k`, and request a redraw if it changed.

The single movements move the selection by one, the fast ones by five rows or ten columns,
and `:home`, `:end`, `:bol`, and `:eol` move it to the bounds. A mouse press or drag inside
the view puts the guides on the pointer, selecting the rows above it and the columns at its
left, without the ruler. Every other keystroke is ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `action::Union{Nothing, Symbol}`: Resolved pager action of `k`.
- `k::Keystroke`: Keystroke to process.
"""
function _move_freeze_selection!(pagerd::Pager, action, k::Keystroke)
    min_rows, max_rows, max_columns = _freeze_selection_bounds(pagerd)
    rows = pagerd.freeze_selection_rows
    columns = pagerd.freeze_selection_columns

    if (k.value == "<mouse_press>") || (k.value == "<mouse_drag>")
        # In this mode, the screen row of a text row is its line number, because the view
        # starts at the first line after the titles and the column ruler. The guides are put
        # on the pointer, so the rows above it and the columns at its left are selected. A
        # click on either ruler selects nothing in its direction, and one on the status line
        # is ignored.
        view_row = k.y - _column_ruler_rows(pagerd)

        if 1 <= view_row <= _get_pager_display_size(pagerd)[1]
            rows = view_row - 1
            columns = k.x - _shown_ruler_width(pagerd) - 1
        end
    elseif action === :up
        rows -= 1
    elseif action === :down
        rows += 1
    elseif action === :fastup
        rows -= 5
    elseif action === :fastdown
        rows += 5
    elseif action === :home
        rows = min_rows
    elseif action === :end
        rows = max_rows
    elseif action === :left
        columns -= 1
    elseif action === :right
        columns += 1
    elseif action === :fastleft
        columns -= 10
    elseif action === :fastright
        columns += 10
    elseif action === :bol
        columns = 0
    elseif action === :eol
        columns = max_columns
    end

    rows = clamp(rows, min_rows, max_rows)
    columns = clamp(columns, 0, max_columns)

    if (rows != pagerd.freeze_selection_rows) ||
        (columns != pagerd.freeze_selection_columns)
        pagerd.freeze_selection_rows = rows
        pagerd.freeze_selection_columns = columns
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _change_title_rows!(pagerd::Pager) -> Nothing

Prompt for the number of title rows of `pagerd`, apply it, and request a redraw. An invalid
or cancelled number keeps the current one.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _change_title_rows!(pagerd::Pager)
    status, title_rows = _prompt_number!(pagerd, "Title rows", pagerd.title_rows)

    if status === :value
        pagerd.title_rows = max(0, title_rows)
        _set_message!(pagerd, "$(pagerd.title_rows) title rows")
    end

    _request_redraw!(pagerd)

    return nothing
end
