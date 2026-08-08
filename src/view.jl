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

    # A degenerate display cannot show any content, so rendering must be skipped entirely.
    # Passing a nonpositive maximum number of lines to `textview` means unbounded, which
    # would render the whole document into the frame buffer.
    if (rows <= 0) || (cols <= 0)
        pagerd.cropped_lines = 0
        pagerd.cropped_columns = 0
        _request_redraw!(pagerd)
        return nothing
    end

    display_config = pagerd.display_config
    start_column = pagerd.start_column
    start_row = pagerd.start_row

    # Make sure that the argument values are correct. The sanitized values must be written back,
    # otherwise the invalid ones are reused by the key processing, by the search, and by the
    # visual mode computations.
    if start_row < 1
        start_row = 1
        pagerd.start_row = start_row
    end

    if start_column < 1
        start_column = 1
        pagerd.start_column = start_column
    end

    vm_active_line_background = display_config.visual_mode_active_line_background
    vm_line_background = display_config.visual_mode_line_background

    active_match_location = if active_search_match_id == 0
        (0, 0)
    else
        active_match = pagerd.ordered_search_matches[active_search_match_id]
        (active_match.line, active_match.index_in_line)
    end

    # The render call is issued once per branch so that the visual arguments are concrete
    # at each call site. Selecting them into union-typed locals first cost roughly 300
    # bytes per frame in boxing.
    cropped_lines, cropped_columns = if pagerd.visual_mode
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

        _render_view(pagerd, rows, cols, active_match_location, visual_lines,
            visual_line_backgrounds)
    else
        _render_view(pagerd, rows, cols, active_match_location, nothing, "")
    end

    # Write the information to the structure.
    pagerd.cropped_columns = cropped_columns
    pagerd.cropped_lines = cropped_lines

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end

"""
    _render_view(pagerd::Pager, rows::Int, cols::Int,
        active_match_location::NTuple{2, Int}, visual_lines::Union{Nothing, Vector{Int}},
        visual_line_backgrounds::Union{String, Vector{String}}) -> Tuple{Int, Int}

Render the viewport of `pagerd` into its view buffer and return the crop counters.

# Arguments

- `pagerd::Pager`: Pager state to render.
- `rows::Int`: Number of available view rows.
- `cols::Int`: Number of available view columns.
- `active_match_location::NTuple{2, Int}`: Line and in-line index of the active match.
- `visual_lines::Union{Nothing, Vector{Int}}`: Lines rendered with a visual background.
- `visual_line_backgrounds::Union{String, Vector{String}}`: Background of each entry of
    `visual_lines`.
"""
function _render_view(
    pagerd::Pager,
    rows::Int,
    cols::Int,
    active_match_location::NTuple{2, Int},
    visual_lines::Union{Nothing, Vector{Int}},
    visual_line_backgrounds::Union{String, Vector{String}},
)
    display_config = pagerd.display_config

    return textview(
        pagerd.buf,
        pagerd.text_layout,
        (pagerd.start_row, -1, pagerd.start_column, -1);
        active_highlight = display_config.active_search_decoration,
        active_match = 0,
        active_match_location = active_match_location,
        frozen_columns_at_beginning = pagerd.frozen_columns,
        frozen_lines_at_beginning = pagerd.frozen_rows,
        highlight = display_config.inactive_search_decoration,
        maximum_number_of_columns = cols,
        maximum_number_of_lines = rows,
        search_matches = pagerd.search_matches,
        show_ruler = pagerd.show_ruler,
        title_lines = pagerd.title_rows,
        visual_lines = visual_lines,
        visual_line_backgrounds = visual_line_backgrounds,
    )
end
