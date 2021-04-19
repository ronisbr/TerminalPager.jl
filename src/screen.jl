# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to screen management.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _clear_screen(io::IO)

Clear the screen `io`.

"""
_clear_screen(io::IO) = write(io, "$(CSI)2J")

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
