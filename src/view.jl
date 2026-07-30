## Description #############################################################################
#
# Functions that create a view of the string on the IO.
#
############################################################################################

"""
    _view!(pagerd::Pager) -> Nothing

Render the current pager viewport into its view buffer.

# Arguments

- `pagerd::Pager`: Pager state to render and update.
"""
function _view!(pagerd::Pager)
    # Get the available display size.
    rows, cols = _get_pager_display_size(pagerd)

    # Get the necessary variables.
    active_search_match_id = pagerd.active_search_match_id
    buf = pagerd.buf

    # `_redraw!` reads the frame from `buf` without consuming it, so that the storage is
    # reused across frames. Hence, we must reset the buffer here.
    truncate(buf.io, 0)
    seekstart(buf.io)
    display_config = pagerd.display_config
    frozen_columns = pagerd.frozen_columns
    frozen_rows = pagerd.frozen_rows
    text_layout = pagerd.text_layout
    search_matches = pagerd.search_matches
    show_ruler = pagerd.show_ruler
    start_column = pagerd.start_column
    start_row = pagerd.start_row
    title_rows = pagerd.title_rows

    # Make sure that the argument values are correct.
    start_row < 1 && (start_row = 1)
    start_column < 1 && (start_column = 1)

    active_highlight = display_config.active_search_decoration
    inactive_highlight = display_config.inactive_search_decoration
    vm_active_line_background = display_config.visual_mode_active_line_background
    vm_line_background = display_config.visual_mode_line_background

    active_match_location = if active_search_match_id == 0
        (0, 0)
    else
        active_match = pagerd.ordered_search_matches[active_search_match_id]
        (active_match.line, active_match.index_in_line)
    end

    if pagerd.visual_mode
        # These buffers are reused across frames. Otherwise, every frame allocates one vector
        # per selected line.
        visual_lines = pagerd.visual_lines
        visual_line_backgrounds = pagerd.visual_line_backgrounds
        empty!(visual_lines)
        empty!(visual_line_backgrounds)

        push!(visual_lines, pagerd.visual_mode_line + start_row - 1)
        push!(visual_line_backgrounds, vm_active_line_background)

        for line in pagerd.visual_mode_selected_lines
            push!(visual_lines, line)
            push!(visual_line_backgrounds, vm_line_background)
        end
    else
        visual_lines = nothing
        visual_line_backgrounds = ""
    end

    # Render the view.
    cropped_lines, cropped_columns = textview(
        buf,
        text_layout,
        (start_row, -1, start_column, -1);
        active_highlight = active_highlight,
        active_match = 0,
        active_match_location = active_match_location,
        frozen_columns_at_beginning = frozen_columns,
        frozen_lines_at_beginning = frozen_rows,
        highlight = inactive_highlight,
        maximum_number_of_columns = cols,
        maximum_number_of_lines = rows,
        search_matches = search_matches,
        show_ruler = show_ruler,
        title_lines = title_rows,
        visual_lines = visual_lines,
        visual_line_backgrounds = visual_line_backgrounds,
    )

    # Write the information to the structure.
    pagerd.cropped_columns = cropped_columns
    pagerd.cropped_lines = cropped_lines

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end
