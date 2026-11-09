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

    vm_active_line_background = display_config.visual_active_line
    vm_line_background = display_config.visual_line

    active_match_location = if active_search_match_id == 0
        (0, 0)
    else
        active_match = pagerd.ordered_search_matches[active_search_match_id]
        (active_match.line, active_match.index_in_line)
    end

    # With the scrollbar or the freeze selection, the view is rendered into a scratch
    # buffer, and the frame is assembled from it with the selection painted and the
    # scrollbar appended to every row.
    show_scrollbar = pagerd.show_scrollbar
    selecting = pagerd.mode == :freeze_selection
    target = if show_scrollbar || selecting
        view_buf = pagerd.view_buf
        truncate(view_buf, 0)
        seekstart(view_buf)
        IOContext(view_buf, buf)
    else
        buf
    end

    # The render call is issued once per branch so that the visual arguments are concrete
    # at each call site. Selecting them into union-typed locals first cost roughly 300
    # bytes per frame in boxing. The visual backgrounds are not drawn while the freeze
    # selection is active, because the selection is painted over the view.
    cropped_lines, cropped_columns = if pagerd.visual_mode && !selecting
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

        _render_view(pagerd, target, rows, cols, active_match_location, visual_lines,
            visual_line_backgrounds)
    else
        _render_view(pagerd, target, rows, cols, active_match_location, nothing, "")
    end

    frame = pagerd.view_buf

    if selecting
        # The painted frame feeds the scrollbar, or it is the frame itself.
        painted = show_scrollbar ? pagerd.freeze_buf : buf.io

        if show_scrollbar
            truncate(painted, 0)
            seekstart(painted)
        end

        _paint_freeze_selection!(painted, frame, rows, cols, pagerd)
        frame = painted
    end

    if show_scrollbar
        thumb_first, thumb_last = _scrollbar_thumb(pagerd, rows)
        _append_scrollbar!(
            buf.io,
            frame,
            rows,
            pagerd.display_size[2],
            thumb_first,
            thumb_last,
            get(buf, :color, true)::Bool,
            display_config,
        )
    end

    # Write the information to the structure.
    pagerd.cropped_columns = cropped_columns
    pagerd.cropped_lines = cropped_lines

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end

"""
    _render_view(pagerd::Pager, io::IO, rows::Int, cols::Int,
        active_match_location::NTuple{2, Int}, visual_lines::Union{Nothing, Vector{Int}},
        visual_line_backgrounds::Union{String, Vector{String}}) -> Tuple{Int, Int}

Render the viewport of `pagerd` into `io` and return the crop counters.

# Arguments

- `pagerd::Pager`: Pager state to render.
- `io::IO`: Buffer receiving the rendered view.
- `rows::Int`: Number of available view rows.
- `cols::Int`: Number of available view columns.
- `active_match_location::NTuple{2, Int}`: Line and in-line index of the active match.
- `visual_lines::Union{Nothing, Vector{Int}}`: Lines rendered with a visual background.
- `visual_line_backgrounds::Union{String, Vector{String}}`: Background of each entry of
    `visual_lines`.
"""
function _render_view(
    pagerd::Pager,
    io::IO,
    rows::Int,
    cols::Int,
    active_match_location::NTuple{2, Int},
    visual_lines::Union{Nothing, Vector{Int}},
    visual_line_backgrounds::Union{String, Vector{String}},
)
    display_config = pagerd.display_config

    return textview(
        io,
        pagerd.text_layout,
        (pagerd.start_row, -1, pagerd.start_column, -1);
        active_highlight = display_config.search_active_match,
        active_match = 0,
        active_match_location = active_match_location,
        frozen_columns_at_beginning = pagerd.frozen_columns,
        frozen_lines_at_beginning = pagerd.frozen_rows,
        highlight = display_config.search_match,
        maximum_number_of_columns = cols,
        maximum_number_of_lines = rows,
        ruler_decoration = display_config.ruler,
        search_matches = pagerd.search_matches,
        show_ruler = pagerd.show_ruler,
        title_lines = pagerd.title_rows,
        visual_lines = visual_lines,
        visual_line_backgrounds = visual_line_backgrounds,
    )
end

"""
    _scrollbar_thumb(pagerd::Pager, rows::Int) -> Tuple{Int, Int}

Return the first and last rows of the scrollbar thumb of `pagerd` for a bar with `rows`
rows.

The thumb covers the fraction of the scrollable lines that is visible, at a position that
follows the first visible line. It always has at least one row.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
- `rows::Int`: Number of rows of the scrollbar.
"""
function _scrollbar_thumb(pagerd::Pager, rows::Int)
    frozen_rows = pagerd.frozen_rows
    min_row = _first_scrollable_row(pagerd)
    scrollable = max(pagerd.num_lines - frozen_rows, 1)
    visible = clamp(rows - frozen_rows, 1, scrollable)

    thumb = clamp(round(Int, rows * visible / scrollable), 1, rows)
    hidden = scrollable - visible
    progress = hidden > 0 ? clamp((pagerd.start_row - min_row) / hidden, 0, 1) : 0.0
    thumb_first = 1 + round(Int, progress * (rows - thumb))

    return thumb_first, thumb_first + thumb - 1
end

"""
    _paint_freeze_selection!(out::IOBuffer, frame::IOBuffer, rows::Int, cols::Int,
        pagerd::Pager) -> Nothing

Copy the view in `frame` to `out`, painting the rows and the columns selected in the freeze
selection mode of `pagerd` with the face `freeze_block`.

The selected rows are painted across the `cols` columns of the view, and the selected
columns are painted on every one of the `rows` rows below them, after the ruler. The
decorations of the text inside the painted region are removed, so that the region is
uniform, and the decoration state of the text at the right of the painted columns is
restored. Rows missing from `frame`, when the text is shorter than the view, are emitted
blank so that the painted columns span the whole view. Notice that the face is written even
if the terminal has no color support, because `frame` already carries the escape sequences
of the text.

# Arguments

- `out::IOBuffer`: Buffer receiving the frame.
- `frame::IOBuffer`: Rendered view, one row per line.
- `rows::Int`: Number of rows of the view.
- `cols::Int`: Number of columns of the view.
- `pagerd::Pager`: Pager state with the selection and the display configuration.
"""
function _paint_freeze_selection!(
    out::IOBuffer, frame::IOBuffer, rows::Int, cols::Int, pagerd::Pager
)
    face = pagerd.display_config.freeze_block
    selected_rows = pagerd.freeze_selection_rows
    selected_columns = pagerd.freeze_selection_columns
    ruler_width = pagerd.show_ruler ? _ruler_width(pagerd.num_lines) : 0

    data, num_bytes = _frame_bytes(frame)
    row = 1
    row_first = 1

    @inbounds for i in 1:(num_bytes + 1)
        # The last row is not terminated by a newline.
        (i <= num_bytes) && (data[i] != UInt8('\n')) && continue
        (i > num_bytes) && (row_first > num_bytes) && (row > 1) && break
        row > rows && break

        row_size = i - row_first
        line = if row_size > 0
            GC.@preserve data unsafe_string(pointer(data, row_first), row_size)
        else
            ""
        end

        _paint_freeze_row!(
            out, line, row, selected_rows, selected_columns, ruler_width, cols, face
        )
        row < rows && write(out, UInt8('\n'))

        row += 1
        row_first = i + 1
    end

    # The rows after the end of the text only carry the selection.
    while row <= rows
        _paint_freeze_row!(
            out, "", row, selected_rows, selected_columns, ruler_width, cols, face
        )
        row < rows && write(out, UInt8('\n'))
        row += 1
    end

    return nothing
end

"""
    _paint_freeze_row!(out::IOBuffer, line::String, row::Int, selected_rows::Int,
        selected_columns::Int, ruler_width::Int, cols::Int, face::String) -> Nothing

Write the view row `line`, which is the row `row` of the view, to `out`, painting it with
`face` if it is one of the `selected_rows` first rows, or painting its `selected_columns`
first columns after the `ruler_width` columns of the ruler otherwise.

# Arguments

- `out::IOBuffer`: Buffer receiving the row.
- `line::String`: Rendered row, without the trailing newline.
- `row::Int`: One-based row of the view.
- `selected_rows::Int`: Number of selected rows.
- `selected_columns::Int`: Number of selected columns.
- `ruler_width::Int`: Number of columns of the ruler, or `0` if it is hidden.
- `cols::Int`: Number of columns of the view.
- `face::String`: Escape sequence of the face of the selection.
"""
function _paint_freeze_row!(
    out::IOBuffer,
    line::String,
    row::Int,
    selected_rows::Int,
    selected_columns::Int,
    ruler_width::Int,
    cols::Int,
    face::String,
)
    # A selected row is painted edge to edge, ruler included.
    if row <= selected_rows
        plain = remove_decorations(line)
        write(out, face)
        write(out, plain)
        _write_blanks(out, cols - printable_textwidth(plain))
        write(out, _SGR_RESET)
        return nothing
    end

    if selected_columns <= 0
        write(out, line)
        return nothing
    end

    # The ruler is kept as it is. Its last cell is followed by a reset, and the face starts
    # with one, so neither leaks into the other.
    text = line

    if ruler_width > 0
        ruler, text = split_string(line, ruler_width)
        write(out, ruler)
    end

    plain = remove_decorations(text)
    width = printable_textwidth(plain)

    if width <= selected_columns
        write(out, face)
        write(out, plain)
        _write_blanks(out, selected_columns - width)
        write(out, _SGR_RESET)
    else
        # Both functions replace a wide character at the split point by blanks, so that the
        # widths are kept. The escape sequences of the painted part are written after it,
        # restoring the decoration state of the rest of the row.
        head, _ = split_string(text, selected_columns)
        ansi, rest = left_crop(text, selected_columns)
        write(out, face)
        write(out, remove_decorations(head))
        write(out, _SGR_RESET)
        write(out, ansi)
        write(out, rest)
    end

    return nothing
end

# Glyphs of the scrollbar, both with a display width of one.
const _SCROLLBAR_THUMB = "┃"
const _SCROLLBAR_TRACK = "│"

"""
    _append_scrollbar!(out::IOBuffer, frame::IOBuffer, rows::Int, column::Int,
        thumb_first::Int, thumb_last::Int, use_color::Bool,
        display_config::DisplayConfig) -> Nothing

Copy the view in `frame` to `out`, appending the scrollbar at `column` to every one of the
`rows` rows.

Rows missing from `frame`, when the text is shorter than the view, are emitted empty so that
the scrollbar always spans the whole view.

# Arguments

- `out::IOBuffer`: Buffer receiving the frame.
- `frame::IOBuffer`: Rendered view, one row per line.
- `rows::Int`: Number of rows of the view.
- `column::Int`: One-based column of the scrollbar.
- `thumb_first::Int`: First row of the thumb.
- `thumb_last::Int`: Last row of the thumb.
- `use_color::Bool`: Decorate the scrollbar with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the scrollbar faces.
"""
function _append_scrollbar!(
    out::IOBuffer,
    frame::IOBuffer,
    rows::Int,
    column::Int,
    thumb_first::Int,
    thumb_last::Int,
    use_color::Bool,
    display_config::DisplayConfig,
)
    data, num_bytes = _frame_bytes(frame)
    row = 1
    row_first = 1

    @inbounds for i in 1:(num_bytes + 1)
        # The last row is not terminated by a newline.
        (i <= num_bytes) && (data[i] != UInt8('\n')) && continue
        (i > num_bytes) && (row_first > num_bytes) && (row > 1) && break
        row > rows && break

        row_size = i - row_first
        row_size > 0 &&
            GC.@preserve data unsafe_write(out, pointer(data, row_first), UInt(row_size))
        _write_scrollbar_cell!(
            out, column, thumb_first <= row <= thumb_last, use_color, display_config
        )
        row < rows && write(out, UInt8('\n'))

        row += 1
        row_first = i + 1
    end

    # The rows after the end of the text only carry the scrollbar.
    while row <= rows
        _write_scrollbar_cell!(
            out, column, thumb_first <= row <= thumb_last, use_color, display_config
        )
        row < rows && write(out, UInt8('\n'))
        row += 1
    end

    return nothing
end

"""
    _write_scrollbar_cell!(
        out::IOBuffer,
        column::Int,
        is_thumb::Bool,
        use_color::Bool,
        display_config::DisplayConfig,
    ) -> Nothing

Write one cell of the scrollbar at `column` of the current row of `out`.

# Arguments

- `out::IOBuffer`: Buffer receiving the frame.
- `column::Int`: One-based column of the scrollbar.
- `is_thumb::Bool`: Whether the cell belongs to the thumb.
- `use_color::Bool`: Decorate the cell with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the scrollbar faces.
"""
function _write_scrollbar_cell!(
    out::IOBuffer,
    column::Int,
    is_thumb::Bool,
    use_color::Bool,
    display_config::DisplayConfig,
)
    write(out, CSI)
    _write_decimal(out, column)
    write(out, UInt8('G'))

    # Every face starts by resetting the attributes, which also protects the cell from the
    # attributes left by the text of the row.
    if is_thumb
        use_color && write(out, display_config.scrollbar_thumb)
        write(out, _SCROLLBAR_THUMB)
    else
        use_color && write(out, display_config.scrollbar_track)
        write(out, _SCROLLBAR_TRACK)
    end

    use_color && write(out, _SGR_RESET)

    return nothing
end
