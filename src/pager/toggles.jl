## Description #############################################################################
#
# Commands that show and hide the line-number ruler, the column ruler, and the scrollbar.
#
############################################################################################

"""
    _toggle_ruler!(pagerd::Pager) -> Nothing

Show or hide the line number ruler of `pagerd` and request a redraw. Hiding it scrolls the
view left if the end of the widest line does not fill the reclaimed columns.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_ruler!(pagerd::Pager)
    pagerd.show_ruler = !pagerd.show_ruler

    # Hiding the ruler gives its columns to the text. If the view is at the end of the
    # widest line, it is scrolled left so that those columns are filled, without entering
    # the frozen columns. Notice that this must be decided with the width of the text, not
    # with the columns cropped in the last frame, which only considers the visible rows.
    pagerd.show_ruler || _clamp_start_column!(pagerd)

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

    # Hiding the scrollbar gives its column to the text. Like the ruler, the view is
    # scrolled left if it is at the end of the widest line.
    pagerd.show_scrollbar || _clamp_start_column!(pagerd)

    _request_redraw!(pagerd)

    return nothing
end
