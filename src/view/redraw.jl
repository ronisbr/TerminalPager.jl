## Description #############################################################################
#
# Incremental redraw: the rows of the rendered frame that changed since the last one are
# written to the terminal, using a snapshot of what is on the screen.
#
############################################################################################

"""
    _invalidate_frame!(pagerd::Pager) -> Nothing

Discard the frame snapshot, forcing the next redraw to repaint every row.

This must be called whenever something other than [`_redraw!`](@ref) writes to the rows above
the command line.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _invalidate_frame!(pagerd::Pager)
    pagerd.frame_cache.valid = false
    return nothing
end

"""
    _frame_bytes(io::IOBuffer) -> Tuple{Any, Int}

Return the storage backing the bytes written to `io` and how many of them are valid.

The storage is a `Vector{UInt8}` up to Julia 1.11 and a `Memory{UInt8}` afterwards. In both
cases, `pointer(storage, i)` is valid, which is all the redraw path needs. Notice that we
must not use `take!` here, because it hands over the storage and forces `io` to allocate a
new one for the next frame.

# Arguments

- `io::IOBuffer`: Buffer holding a rendered frame.
"""
_frame_bytes(io::IOBuffer) = (io.data, io.size)

"""
    _screen_buffer!(pagerd::Pager) -> IOBuffer

Return the reusable buffer that assembles everything sent to the terminal, after resetting it.

# Arguments

- `pagerd::Pager`: Pager state whose buffer is returned.
"""
function _screen_buffer!(pagerd::Pager)
    return _reset_buffer!(pagerd.frame_cache.out)
end

"""
    _reset_buffer!(buf::IOBuffer) -> IOBuffer

Empty `buf`, keeping its storage so that it is reused, and return it.

# Arguments

- `buf::IOBuffer`: Buffer to empty.
"""
function _reset_buffer!(buf::IOBuffer)
    truncate(buf, 0)
    seekstart(buf)
    return buf
end

"""
    _flush_screen!(pagerd::Pager) -> Nothing

Send everything assembled in the reusable screen buffer to the terminal in a single write.

Writing each piece separately would issue one system call per piece, which can cause
tearing.

# Arguments

- `pagerd::Pager`: Pager state to flush.
"""
function _flush_screen!(pagerd::Pager)
    data, num_bytes = _frame_bytes(pagerd.frame_cache.out)
    num_bytes > 0 && _write_all(pagerd.term.out_stream, data, num_bytes)
    return nothing
end

"""
    _write_all(io::IO, data, num_bytes::Int) -> Nothing

Write the first `num_bytes` bytes of `data` to `io`.

Notice that this function returns `nothing`. `TTYTerminal` declares its streams as `IO`, so a
`write` to them is a dynamic dispatch whose `Int` return value would have to be boxed.

# Arguments

- `io::IO`: Output stream to update.
- `data`: Byte storage to write from.
- `num_bytes::Int`: Number of bytes to write.
"""
function _write_all(io::IO, data, num_bytes::Int)
    GC.@preserve data unsafe_write(io, pointer(data, 1), UInt(num_bytes))
    return nothing
end

"""
    _bytes_equal(a, ai::Int, b, bi::Int, n::Int) -> Bool

Return whether the `n` bytes of `a` starting at `ai` equal those of `b` starting at `bi`.

# Arguments

- `a`: First byte storage.
- `ai::Int`: One-based first index in `a`.
- `b`: Second byte storage.
- `bi::Int`: One-based first index in `b`.
- `n::Int`: Number of bytes to compare.
"""
function _bytes_equal(a, ai::Int, b, bi::Int, n::Int)
    n <= 0 && return true

    return GC.@preserve a b (
        ccall(
            :memcmp,
            Cint,
            (Ptr{UInt8}, Ptr{UInt8}, Csize_t),
            pointer(a, ai),
            pointer(b, bi),
            n,
        ) == 0
    )
end

"""
    _scan_frame_rows!(frame_cache::FrameCache, data, num_bytes::Int, max_rows::Int) -> Int

Fill the scratch row table of `frame_cache` from the newline positions in `data`.

Return the number of rows found, which is at most `max_rows`.

# Arguments

- `frame_cache::FrameCache`: Cache whose scratch row table is filled.
- `data`: Byte storage holding the rendered frame.
- `num_bytes::Int`: Number of valid bytes in `data`.
- `max_rows::Int`: Maximum number of rows the screen can show.
"""
function _scan_frame_rows!(frame_cache::FrameCache, data, num_bytes::Int, max_rows::Int)
    new_first = frame_cache.new_first
    new_last = frame_cache.new_last

    empty!(new_first)
    empty!(new_last)

    # Without this guard, the early return inside the loop below would report one row for
    # a screen that cannot show any.
    max_rows <= 0 && return 0

    num_rows = 0
    row_first = 1

    @inbounds for i in 1:num_bytes
        data[i] == UInt8('\n') || continue

        num_rows += 1
        push!(new_first, row_first)
        push!(new_last, i - 1)
        row_first = i + 1

        num_rows >= max_rows && return num_rows
    end

    # The last row is not terminated by a newline.
    if row_first <= num_bytes + 1
        num_rows += 1
        push!(new_first, row_first)
        push!(new_last, num_bytes)
    end

    return min(num_rows, max_rows)
end

"""
    _redraw!(pagerd::Pager) -> Nothing

Write the rows of the prepared view buffer that changed to the terminal.

# Arguments

- `pagerd::Pager`: Pager state to redraw.
"""
function _redraw!(pagerd::Pager)
    frame_cache = pagerd.frame_cache
    max_rows = _frame_rows(pagerd)

    data, num_bytes = _frame_bytes(pagerd.buf.io)
    num_rows = _scan_frame_rows!(frame_cache, data, num_bytes, max_rows)

    new_first = frame_cache.new_first
    new_last = frame_cache.new_last
    snapshot = frame_cache.bytes
    row_first = frame_cache.row_first
    row_last = frame_cache.row_last
    valid = frame_cache.valid

    # If the whole frame is unchanged, we do not need to touch the terminal at all.
    if valid &&
        (num_rows == frame_cache.num_rows) &&
        (num_bytes == length(snapshot)) &&
        _bytes_equal(snapshot, 1, data, 1, num_bytes)
        _record_viewport!(frame_cache, pagerd)
        pagerd.redraw = false
        return nothing
    end

    out = _screen_buffer!(pagerd)

    # When the view only scrolled, the terminal shifts the rows it already shows, and the
    # snapshot is shifted the same way. The comparison below then repaints only the rows
    # that entered the view, which is much cheaper than repainting every row.
    valid && pagerd.scroll_regions && _shift_frame!(out, frame_cache, pagerd, max_rows)

    # We must not use the ANSI escape sequence `\e[2J` to clear the screen because it adds new
    # lines to it. Hence, every row we paint is cleared to the end of the line.
    previous_row = -1

    @inbounds for i in 1:num_rows
        row_size = new_last[i] - new_first[i] + 1

        if valid &&
            (i <= frame_cache.num_rows) &&
            (row_last[i] - row_first[i] + 1 == row_size) &&
            _bytes_equal(snapshot, row_first[i], data, new_first[i], row_size)
            continue
        end

        if i == previous_row + 1
            # A carriage return also cancels the pending-wrap state left by a row that filled
            # the display width.
            write(out, "\r\n")
        else
            _move_cursor(out, i, 1)

            # Every row ends with the SGR state at its default, but we reset it anyway.
            # Otherwise, a row painted out of order could erase to the end of the line with a
            # colored background.
            write(out, _SGR_RESET)
        end

        _clear_to_eol(out)
        row_size > 0 &&
            GC.@preserve data unsafe_write(out, pointer(data, new_first[i]), UInt(row_size))

        previous_row = i
    end

    # Clear the rows that were painted before but are not part of this frame. If the snapshot
    # is not valid, we do not know what is on screen, so we must clear everything.
    last_stale = valid ? min(frame_cache.num_rows, max_rows) : max_rows

    @inbounds for i in (num_rows + 1):last_stale
        # A row recorded as empty is already blank.
        valid && (row_last[i] < row_first[i]) && continue
        _move_cursor(out, i, 1)
        write(out, _SGR_RESET)
        _clear_to_eol(out)
    end

    # The snapshot will not describe the screen until the frame is flushed and stored. Hence,
    # a failure in between forces a full repaint instead of leaving a stale snapshot.
    frame_cache.valid = false

    # The cursor is hidden for the whole session, so the frame is flushed as is.
    _flush_screen!(pagerd)

    _store_frame!(frame_cache, data, num_bytes, num_rows)
    _record_viewport!(frame_cache, pagerd)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end

"""
    _paint_view!(pagerd::Pager) -> Nothing

Render the viewport of `pagerd` and write the rows that changed to the terminal, leaving the
status line as it is.

# Arguments

- `pagerd::Pager`: Pager state to paint.
"""
function _paint_view!(pagerd::Pager)
    _view!(pagerd)
    _redraw!(pagerd)
    return nothing
end

"""
    _paint!(pagerd::Pager) -> Nothing

Render the viewport of `pagerd`, write the rows that changed to the terminal, and redraw the
status line.

# Arguments

- `pagerd::Pager`: Pager state to paint.
"""
function _paint!(pagerd::Pager)
    _paint_view!(pagerd)
    _redraw_status_bar!(pagerd)
    return nothing
end

"""
    _record_viewport!(frame_cache::FrameCache, pagerd::Pager) -> Nothing

Record in `frame_cache` the viewport of `pagerd` that the snapshot describes.

# Arguments

- `frame_cache::FrameCache`: Cache to update.
- `pagerd::Pager`: Pager state whose viewport is recorded.
"""
function _record_viewport!(frame_cache::FrameCache, pagerd::Pager)
    frame_cache.start_row = pagerd.start_row
    frame_cache.start_column = pagerd.start_column
    frame_cache.frozen_rows = pagerd.frozen_rows
    return nothing
end

"""
    _shift_frame!(out::IOBuffer, frame_cache::FrameCache, pagerd::Pager, max_rows::Int) ->
        Bool

Shift the scrollable rows of the terminal and of the snapshot in `frame_cache` by the
vertical movement of the viewport of `pagerd` since the snapshot was painted, and return
whether the shift was performed.

The shift is performed only for a pure vertical movement smaller than the scrollable region,
that is, when the first visible column and the frozen rows are unchanged. The sequences
asking the terminal to shift the rows are written to `out`. The rows the terminal blanks
while shifting are recorded as empty in the snapshot, so that the comparison with the new
frame repaints exactly the rows that entered the view.

# Arguments

- `out::IOBuffer`: Buffer assembling everything sent to the terminal.
- `frame_cache::FrameCache`: Cache whose snapshot is shifted.
- `pagerd::Pager`: Pager state with the current viewport.
- `max_rows::Int`: Number of rows the screen can show.
"""
function _shift_frame!(out::IOBuffer, frame_cache::FrameCache, pagerd::Pager, max_rows::Int)
    delta = pagerd.start_row - frame_cache.start_row

    # The scrollable region starts after the column ruler and the frozen rows.
    top = _column_ruler_rows(pagerd) + pagerd.frozen_rows + 1
    bottom = max_rows
    height = bottom - top + 1

    (frame_cache.start_column == pagerd.start_column) || return false
    (frame_cache.frozen_rows == pagerd.frozen_rows) || return false
    ((height >= 2) && (0 < abs(delta) < height)) || return false

    # Ask the terminal to shift the rows of the scrollable region.
    write(out, CSI)
    _write_decimal(out, top)
    write(out, UInt8(';'))
    _write_decimal(out, bottom)
    write(out, UInt8('r'))
    write(out, CSI)
    _write_decimal(out, abs(delta))
    write(out, delta > 0 ? UInt8('S') : UInt8('T'))
    write(out, _RESET_SCROLL_REGION)

    # Shift the snapshot rows the same way. The rows after the ones the snapshot describes
    # were cleared by the previous redraws, and the rows vacated by the shift are blanked by
    # the terminal, so both are recorded as empty rows.
    row_first = frame_cache.row_first
    row_last = frame_cache.row_last
    num_known = length(row_first)
    resize!(row_first, max_rows)
    resize!(row_last, max_rows)

    @inbounds for i in (num_known + 1):max_rows
        row_first[i] = 1
        row_last[i] = 0
    end

    @inbounds if delta > 0
        for i in top:(bottom - delta)
            row_first[i] = row_first[i + delta]
            row_last[i] = row_last[i + delta]
        end

        for i in (bottom - delta + 1):bottom
            row_first[i] = 1
            row_last[i] = 0
        end
    else
        for i in bottom:-1:(top - delta)
            row_first[i] = row_first[i + delta]
            row_last[i] = row_last[i + delta]
        end

        for i in top:(top - delta - 1)
            row_first[i] = 1
            row_last[i] = 0
        end
    end

    frame_cache.num_rows = max_rows

    return true
end

"""
    _store_frame!(frame_cache::FrameCache, data, num_bytes::Int, num_rows::Int) -> Nothing

Record the frame in `data` as what is currently on screen.

# Arguments

- `frame_cache::FrameCache`: Cache to update.
- `data`: Byte storage holding the rendered frame.
- `num_bytes::Int`: Number of valid bytes in `data`.
- `num_rows::Int`: Number of rows that were painted.
"""
function _store_frame!(frame_cache::FrameCache, data, num_bytes::Int, num_rows::Int)
    snapshot = frame_cache.bytes
    resize!(snapshot, num_bytes)
    num_bytes > 0 && copyto!(snapshot, 1, data, 1, num_bytes)

    resize!(frame_cache.row_first, num_rows)
    resize!(frame_cache.row_last, num_rows)
    copyto!(frame_cache.row_first, 1, frame_cache.new_first, 1, num_rows)
    copyto!(frame_cache.row_last, 1, frame_cache.new_last, 1, num_rows)

    frame_cache.num_rows = num_rows
    frame_cache.valid = true

    return nothing
end
