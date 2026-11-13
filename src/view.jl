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
    # Passing a nonpositive maximum number of lines to `_textview` means unbounded, which
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

    # The column ruler is the first two rows of the frame, before the rows of the text.
    if pagerd.show_column_ruler
        _write_column_ruler!(buf.io, pagerd, cols, get(buf, :color, true)::Bool)
        write(buf.io, UInt8('\n'))
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
    # buffer, and the frame is assembled from it with the freeze guides drawn and the
    # scrollbar appended to every row.
    show_scrollbar = pagerd.show_scrollbar
    selecting = _selecting_on_screen(pagerd)
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
    # selection is active, because the guides are drawn over the view.
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
        # The frame with the guides feeds the scrollbar, or it is the frame itself.
        drawn = show_scrollbar ? pagerd.freeze_buf : buf.io

        if show_scrollbar
            truncate(drawn, 0)
            seekstart(drawn)
        end

        _draw_freeze_guides!(drawn, frame, rows, cols, pagerd)
        frame = drawn
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

    return _textview(
        io,
        pagerd.text_layout,
        (pagerd.start_row, -1, pagerd.start_column, -1);
        active_highlight = display_config.search_active_match,
        active_match_location = active_match_location,
        frozen_columns_at_beginning = pagerd.frozen_columns,
        frozen_lines_at_beginning = pagerd.frozen_rows,
        highlight = display_config.search_match,
        maximum_number_of_columns = cols,
        maximum_number_of_lines = rows,
        ruler_decoration = display_config.ruler,
        ruler_foot = true,
        ruler_mark_decoration = display_config.bookmark,
        ruler_marks = _bookmark_rows(pagerd),
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

# Glyphs of the column ruler, all with a display width of one.
const _COLUMN_RULER_LINE = '─'
const _COLUMN_RULER_HALF_TICK = '┬'
const _COLUMN_RULER_TICK = '┴'
const _COLUMN_RULER_BREAK = '┆'

"""
    _write_column_ruler!(out::IOBuffer, pagerd::Pager, cols::Int, use_color::Bool) ->
        Nothing

Write the two rows of the column ruler of `pagerd` to `out`, for a view with `cols` columns.

The second row is a line with a tick on every tenth text column and a half tick on every
fifth one, and the first row prints the number of each tenth column right above its tick.
The ruler numbers the text columns the view shows: the frozen columns first, and then the
columns from the first visible one. The columns of the line-number ruler are left blank, and
the ruler stops at the widest line of the text. If the numbering jumps between the frozen and
the scrolled columns, the line carries a break mark on the first scrolled column.

# Arguments

- `out::IOBuffer`: Buffer receiving the rows, separated by a newline.
- `pagerd::Pager`: Pager state with the viewport and the display configuration.
- `cols::Int`: Number of columns of the view.
- `use_color::Bool`: Decorate the ruler with the face `ruler`.
"""
function _write_column_ruler!(out::IOBuffer, pagerd::Pager, cols::Int, use_color::Bool)
    ruler_width = pagerd.show_ruler ? _ruler_width(pagerd) : 0
    width = max(cols - ruler_width, 0)
    text_width = _text_width(pagerd)

    # These are the sanitized values `_textview` uses for the frozen columns and for the
    # first scrolled column.
    frozen_columns = clamp(pagerd.frozen_columns, 0, width)
    start_column = max(pagerd.start_column, pagerd.frozen_columns + 1)

    # Both rows are assembled before they are written, because the numbers end at their
    # ticks. This path allocates a little on every frame, but only while the ruler is shown.
    numbers = fill(' ', width)
    ticks = fill(' ', width)

    # The frozen columns are always the first ones of the text.
    if frozen_columns > 0
        _fill_column_ruler_segment!(
            numbers, ticks, 0, 1, min(frozen_columns, text_width), false
        )
    end

    # The scrolled columns follow. The break mark is drawn only if the numbering jumps.
    last_column = min(start_column + (width - frozen_columns) - 1, text_width)

    if last_column >= start_column
        break_mark = (frozen_columns > 0) && (start_column > frozen_columns + 1)
        _fill_column_ruler_segment!(
            numbers, ticks, frozen_columns, start_column, last_column, break_mark
        )
    end

    _write_column_ruler_row!(out, numbers, ruler_width, pagerd.display_config, use_color)
    write(out, UInt8('\n'))
    _write_column_ruler_row!(out, ticks, ruler_width, pagerd.display_config, use_color)

    return nothing
end

"""
    _fill_column_ruler_segment!(numbers::Vector{Char}, ticks::Vector{Char}, offset::Int,
        first_column::Int, last_column::Int, break_mark::Bool) -> Nothing

Fill the cells `offset + 1` onwards of the rows `numbers` and `ticks` of the column ruler
with the text columns `first_column` to `last_column`.

Every tenth column gets a tick and its number, right-aligned above the tick, and every fifth
column gets a half tick. A number that does not fit in the segment is skipped, leaving its
tick unlabelled. If `break_mark` is set, the first cell of the line is the break mark.

# Arguments

- `numbers::Vector{Char}`: Cells of the row with the numbers.
- `ticks::Vector{Char}`: Cells of the row with the line and the ticks.
- `offset::Int`: Number of cells before the segment.
- `first_column::Int`: Text column of the first cell.
- `last_column::Int`: Text column of the last cell.
- `break_mark::Bool`: Draw the break mark on the first cell of the line.
"""
function _fill_column_ruler_segment!(
    numbers::Vector{Char},
    ticks::Vector{Char},
    offset::Int,
    first_column::Int,
    last_column::Int,
    break_mark::Bool,
)
    num_cells = last_column - first_column + 1
    num_cells <= 0 && return nothing

    @inbounds for i in 1:num_cells
        column = first_column + i - 1
        ticks[offset + i] = if column % 10 == 0
            _COLUMN_RULER_TICK
        elseif column % 5 == 0
            _COLUMN_RULER_HALF_TICK
        else
            _COLUMN_RULER_LINE
        end
    end

    first_tick = first_column + mod(-first_column, 10)

    for column in first_tick:10:last_column
        label = string(column)
        i = column - first_column + 1
        start = i - length(label) + 1
        start < 1 && continue

        for (k, c) in enumerate(label)
            @inbounds numbers[offset + start + k - 1] = c
        end
    end

    break_mark && (ticks[offset + 1] = _COLUMN_RULER_BREAK)

    return nothing
end

"""
    _write_column_ruler_row!(out::IOBuffer, cells::Vector{Char}, ruler_width::Int,
        display_config::DisplayConfig, use_color::Bool) -> Nothing

Write one row of the column ruler to `out`: `ruler_width` blank columns for the line-number
ruler, and then `cells` without their trailing blanks.

# Arguments

- `out::IOBuffer`: Buffer receiving the row.
- `cells::Vector{Char}`: Cells of the row.
- `ruler_width::Int`: Number of columns of the line-number ruler, or `0` if it is hidden.
- `display_config::DisplayConfig`: Session display configuration with the ruler face.
- `use_color::Bool`: Decorate the row with the face `ruler`.
"""
function _write_column_ruler_row!(
    out::IOBuffer,
    cells::Vector{Char},
    ruler_width::Int,
    display_config::DisplayConfig,
    use_color::Bool,
)
    last = findlast(!=(' '), cells)
    last === nothing && (last = 0)

    use_color && write(out, display_config.ruler)
    _write_blanks(out, ruler_width)

    @inbounds for i in 1:last
        write(out, cells[i])
    end

    use_color && write(out, _SGR_RESET)

    return nothing
end

# Glyphs of the freeze guides, all with a display width of one.
const _FREEZE_GUIDE_HORIZONTAL = "━"
const _FREEZE_GUIDE_VERTICAL = "┃"
const _FREEZE_GUIDE_CROSSING = "╋"

"""
    _draw_freeze_guides!(out::IOBuffer, frame::IOBuffer, rows::Int, cols::Int,
        pagerd::Pager) -> Nothing

Copy the view in `frame` to `out`, drawing the guides of the on-screen selection mode of
`pagerd` with the face `freeze_guide`.

The horizontal guide replaces the view row after the selected rows, and the vertical guide
replaces the text column after the selected columns on every other row, with a crossing
where they meet. The title selection has no columns, so it draws only the horizontal guide.
The ruler is kept on every row, so both guides start after it. The text under the guides is
hidden, and the decoration state of the text at the right of the vertical guide is restored.
Rows missing from `frame`, when the text is shorter than the view, are emitted blank so that
the vertical guide spans the whole view. Notice that the face is written even if the terminal
has no color support, because `frame` already carries the escape sequences of the text.

# Arguments

- `out::IOBuffer`: Buffer receiving the frame.
- `frame::IOBuffer`: Rendered view, one row per line.
- `rows::Int`: Number of rows of the view.
- `cols::Int`: Number of columns of the view.
- `pagerd::Pager`: Pager state with the selection and the display configuration.
"""
function _draw_freeze_guides!(
    out::IOBuffer, frame::IOBuffer, rows::Int, cols::Int, pagerd::Pager
)
    face = pagerd.display_config.freeze_guide
    selected_rows = pagerd.freeze_selection_rows
    selected_columns = pagerd.freeze_selection_columns
    vertical = pagerd.mode == :freeze_selection
    ruler_width = pagerd.show_ruler ? _ruler_width(pagerd) : 0

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

        _draw_freeze_guides_row!(
            out,
            line,
            row,
            selected_rows,
            selected_columns,
            ruler_width,
            cols,
            face,
            vertical,
        )
        row < rows && write(out, UInt8('\n'))

        row += 1
        row_first = i + 1
    end

    # The rows after the end of the text only carry the guides.
    while row <= rows
        _draw_freeze_guides_row!(
            out, "", row, selected_rows, selected_columns, ruler_width, cols, face, vertical
        )
        row < rows && write(out, UInt8('\n'))
        row += 1
    end

    return nothing
end

"""
    _draw_freeze_guides_row!(out::IOBuffer, line::String, row::Int, selected_rows::Int,
        selected_columns::Int, ruler_width::Int, cols::Int, face::String,
        vertical::Bool) -> Nothing

Write the view row `line`, which is the row `row` of the view, to `out`, replacing its text
by the horizontal guide if it follows the `selected_rows` first rows, or drawing the
vertical guide on the column after its `selected_columns` first columns otherwise, if
`vertical` is set. The `ruler_width` columns of the ruler are kept in both cases.

# Arguments

- `out::IOBuffer`: Buffer receiving the row.
- `line::String`: Rendered row, without the trailing newline.
- `row::Int`: One-based row of the view.
- `selected_rows::Int`: Number of selected rows.
- `selected_columns::Int`: Number of selected columns.
- `ruler_width::Int`: Number of columns of the ruler, or `0` if it is hidden.
- `cols::Int`: Number of columns of the view.
- `face::String`: Escape sequence of the face of the guides.
- `vertical::Bool`: Draw the vertical guide.
"""
function _draw_freeze_guides_row!(
    out::IOBuffer,
    line::String,
    row::Int,
    selected_rows::Int,
    selected_columns::Int,
    ruler_width::Int,
    cols::Int,
    face::String,
    vertical::Bool,
)
    # One-based view column of the vertical guide. Without it, the column is placed outside
    # the view, which skips the crossing and the vertical guide below.
    guide_column = vertical ? ruler_width + selected_columns + 1 : cols + 1

    # The ruler is kept as it is on every row. Its last cell is followed by a reset, and the
    # face starts with one, so neither leaks into the other. The rows after the end of the
    # text have no ruler, so its columns are left blank to keep the guides aligned.
    text = line

    if ruler_width > 0
        if isempty(line)
            _write_blanks(out, ruler_width)
        else
            ruler, text = split_string(line, ruler_width)
            write(out, ruler)
        end
    end

    # The row after the selected ones is the horizontal guide.
    if row == selected_rows + 1
        write(out, face)

        for column in (ruler_width + 1):cols
            if column == guide_column
                write(out, _FREEZE_GUIDE_CROSSING)
            else
                write(out, _FREEZE_GUIDE_HORIZONTAL)
            end
        end

        write(out, _SGR_RESET)
        return nothing
    end

    # The vertical guide is outside the view in the title selection, and until the selection
    # is clamped after a resize.
    if guide_column > cols
        write(out, text)
        return nothing
    end

    width = printable_textwidth(remove_decorations(text))

    if width <= selected_columns
        write(out, text)
        _write_blanks(out, selected_columns - width)
        write(out, face)
        write(out, _FREEZE_GUIDE_VERTICAL)
        write(out, _SGR_RESET)
    else
        # Both functions replace a wide character at the split point by blanks, so that the
        # widths are kept. The escape sequences of the text under the guide are written
        # after it, restoring the decoration state of the rest of the row.
        head, _ = split_string(text, selected_columns)
        ansi, rest = left_crop(text, selected_columns + 1)
        write(out, head)
        write(out, face)
        write(out, _FREEZE_GUIDE_VERTICAL)
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
