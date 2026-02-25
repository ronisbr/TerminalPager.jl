## Description #############################################################################
#
# Functions that creates a view of the string on the IO.
#
############################################################################################

# Write the view of pager `pagerd` to the view buffer.
"""
    _view!(pagerd::Pager) -> Nothing

Write the view of the pager instante `pagerd` to the view buffer.
"""
function _view!(pagerd::Pager)
    # Get the available display size.
    rows, cols = _get_pager_display_size(pagerd)

    # Get the necessary variables.
    active_search_match_id = pagerd.active_search_match_id
    buf                    = pagerd.buf
    frozen_columns         = pagerd.frozen_columns
    frozen_rows            = pagerd.frozen_rows
    lines                  = pagerd.lines
    search_matches         = pagerd.search_matches
    show_ruler             = pagerd.show_ruler
    start_column           = pagerd.start_column
    start_row              = pagerd.start_row
    title_rows             = pagerd.title_rows

    # Make sure that the argument values are correct.
    start_row < 1 && (start_row = 1)
    start_column < 1 && (start_column = 1)

    # Get preferences.
    active_highlight          = _get_preference("active_search_decoration")
    inactive_highlight        = _get_preference("inactive_search_decoration")
    vm_active_line_background = _get_preference("visual_mode_active_line_background")
    vm_line_background        = _get_preference("visual_mode_line_background")

    if pagerd.visual_mode
        current_line = pagerd.visual_mode_line + start_row - 1
        visual_lines = vcat(current_line, pagerd.visual_mode_selected_lines)
        visual_line_backgrounds = vcat(
            vm_active_line_background,
            fill(vm_line_background, length(pagerd.visual_mode_selected_lines))
        )
    else
        visual_lines = nothing
        visual_line_backgrounds = ""
    end

    # Render the view
    cropped_lines, cropped_columns = textview(
        buf,
        lines,
        (start_row, -1, start_column, -1);
        active_highlight            = active_highlight,
        active_match                = active_search_match_id,
        frozen_columns_at_beginning = frozen_columns,
        frozen_lines_at_beginning   = frozen_rows,
        highlight                   = inactive_highlight,
        maximum_number_of_columns   = cols,
        maximum_number_of_lines     = rows,
        search_matches              = search_matches,
        show_ruler                  = show_ruler,
        title_lines                 = title_rows,
        visual_lines                = visual_lines,
        visual_line_backgrounds     = visual_line_backgrounds
    )

    # Write the information to the structure.
    pagerd.cropped_columns = cropped_columns
    pagerd.cropped_lines   = cropped_lines

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end
