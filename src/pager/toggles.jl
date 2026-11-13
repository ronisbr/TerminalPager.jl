## Description #############################################################################
#
# Commands that show and hide the line-number ruler, the column ruler, and the scrollbar.
#
############################################################################################

"""
    _toggle_ruler!(pagerd::Pager) -> Nothing

Show or hide the line number ruler of `pagerd` and request a redraw. Hiding it scrolls the
view left if the text cropped at the right edge does not fill the reclaimed columns.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_ruler!(pagerd::Pager)
    pagerd.show_ruler = !pagerd.show_ruler

    # If the ruler is hidden, we must verify if the screen is near the right edge to fix the
    # `start_column`.
    if !pagerd.show_ruler
        ruler_spacing = _ruler_width(pagerd)

        if pagerd.cropped_columns ≤ ruler_spacing
            # Hiding the ruler reclaims `ruler_spacing` columns, of which `cropped_columns`
            # are filled by the text that was cropped at the right edge. Scrolling left by
            # the difference fills the rest. Scrolling by the full ruler width cropped that
            # text again. Notice that the reclaimed columns must not push the view into the
            # frozen region.
            pagerd.start_column = max(
                pagerd.start_column - (ruler_spacing - pagerd.cropped_columns),
                _first_scrollable_column(pagerd),
            )
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_column_ruler!(pagerd::Pager) -> Nothing

Show or hide the column ruler of `pagerd` and request a redraw. The ruler takes the first
two rows of the view, so the viewport is clamped to the new number of rows.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_column_ruler!(pagerd::Pager)
    pagerd.show_column_ruler = !pagerd.show_column_ruler
    _clamp_viewport!(pagerd)

    # Every row moved by two, so the snapshot no longer describes the screen.
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_scrollbar!(pagerd::Pager) -> Nothing

Show or hide the scrollbar of `pagerd` and request a redraw. Hiding it scrolls the view left
by one column if the text is scrolled to its right end.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_scrollbar!(pagerd::Pager)
    pagerd.show_scrollbar = !pagerd.show_scrollbar

    # Hiding the scrollbar reclaims one column that the cropped text can use. Like the
    # ruler, the reclaimed column must not push the view into the frozen region.
    if !pagerd.show_scrollbar && (pagerd.cropped_columns == 0)
        pagerd.start_column = max(pagerd.start_column - 1, _first_scrollable_column(pagerd))
    end

    _request_redraw!(pagerd)

    return nothing
end
