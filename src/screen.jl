# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions related to screen management.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Clear the screen `io`. If `newlines` is false, then the display lines will be overwritten.
# Otherwise, a new screen page will be printed, preserving the history. At the end, the
# cursor position is `(0, 0)`.
function _clear_screen(io::IO; newlines::Bool = false)
    if newlines
        write(io, "$(CSI)2J")

    else
        dsize::Tuple{Int, Int} = displaysize(io)

        for i in 1:dsize[1]
            _move_cursor(io, i, 1)
            _clear_to_eol(io)
        end
    end

    _move_cursor(io, 1, 1)

    return nothing
end

# Move the cursor `i` characters back.
_cursor_back(io::IO, i::Int = 1) = write(io, "$(CSI)$(i)D")

# Move the cursor `i` characters forward.
_cursor_forward(io::IO, i::Int = 1) = write(io, "$(CSI)$(i)C")

# Clear from the cursor to the end of the line.
_clear_to_eol(io::IO) = write(io, "$(CSI)0K")

# Hide cursor.
_hide_cursor(io::IO) = write(io, "$(CSI)?25l")

# Move the cursor of the screen `io` to the position `(i, j)`.
_move_cursor(io::IO, i::Int, j::Int) = write(io, "$(CSI)$(i);$(j)H")

# Restore the cursor position in screen `io`.
_restore_cursor(io::IO) = write(io, "$(CSI)u")

# Save the cursor position in screen `io`.
_save_cursor(io::IO) = write(io, "$(CSI)s")

# Show cursor.
_show_cursor(io::IO) = write(io, "$(CSI)?25h")
