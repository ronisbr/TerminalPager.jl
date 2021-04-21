# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to screen management.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _clear_screen(io::IO; newlines::Bool = false)

Clear the screen `io`. If `newlines` is false, then the display lines will be
overwritten. Otherwise, a new screen page will be printed, preserving the
history. At the end, the cursor position is `(0, 0)`.

"""
function _clear_screen(io::IO; newlines::Bool = false)
    # TODO: The routing to clear the screen can be inside the routine to redraw.
    # This will save some unnecessary cleaning.
    if newlines
        write(io, "$(CSI)2J")
    else
        dsize = displaysize(io)

        for i = 1:dsize[1]
            _move_cursor(io, i-1, 0)
            _clear_to_eol(io)
        end
    end

    _move_cursor(io, 0, 0)

    return nothing
end

"""
    _cursor_back(io::IO, i::Int = 1)

Move the cursor `i` characters back.

"""
_cursor_back(io::IO, i::Int = 1) = write(io, "$(CSI)$(i)D")

"""
    _cursor_forward(io::IO, i::Int = 1)

Move the cursor `i` characters forward.

"""
_cursor_forward(io::IO, i::Int = 1) = write(io, "$(CSI)$(i)C")

"""
    _clear_to_eol(io::IO)

Clear from the cursor to the end of the line.

"""
_clear_to_eol(io::IO) = write(io, "$(CSI)K")

"""
    _move_cursor(io::IO, i::Int, j::Int)

Move the cursor of the screen `io` to the position `(i, j)`.

"""
_move_cursor(io::IO, i::Int, j::Int) = write(io, "$(CSI)$(i);$(j)H")

"""
    _restore_cursor(io::IO)

Restore the cursor position in screen `io`.

"""
_restore_cursor(io::IO) = write(io, "$(CSI)u")

"""
    _save_cursor(io::IO)

Save the cursor position in screen `io`.

"""
_save_cursor(io::IO) = write(io, "$(CSI)s")
