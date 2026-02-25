## Description #############################################################################
#
# Functions related to screen management.
#
############################################################################################

"""
    _clear_screen(io::IO; newlines::Bool = false) -> Nothing

Clear the screen `io`. If `newlines` is `false`, the display lines will be overwritten.
Otherwise, a new screen page will be printed, preserving the history. At the end, the
cursor position is `(1, 1)`.
"""
function _clear_screen(@nospecialize(io::IO); newlines::Bool = false)
    if newlines
        write(io, "$(CSI)2J")

    else
        dsize::Tuple{Int, Int} = displaysize(io)

        for i in 1:first(dsize)
            _move_cursor(io, i, 1)
            _clear_to_eol(io)
        end
    end

    _move_cursor(io, 1, 1)

    return nothing
end

"""
    _cursor_back(io::IO, i::Int = 1) -> Nothing

Move the cursor `i` characters back in `io`.
"""
function _cursor_back(@nospecialize(io::IO), i::Int = 1)
    write(io, "$(CSI)$(i)D")
    return nothing
end

"""
    _cursor_forward(io::IO, i::Int = 1) -> Nothing

Move the cursor `i` characters forward in `io`.
"""
function _cursor_forward(@nospecialize(io::IO), i::Int = 1)
    write(io, "$(CSI)$(i)C")
    return nothing
end

"""
    _clear_to_eol(io::IO) -> Nothing

Clear from the cursor position to the end of the line in `io`.
"""
function _clear_to_eol(@nospecialize(io::IO))
    write(io, "$(CSI)0K")
    return nothing
end

"""
    _hide_cursor(io::IO) -> Nothing

Hide the cursor in `io`.
"""
function _hide_cursor(@nospecialize(io::IO))
    write(io, "$(CSI)?25l")
    return nothing
end

"""
    _move_cursor(io::IO, i::Int, j::Int) -> Nothing

Move the cursor of the screen `io` to the position `(i, j)`.
"""
function _move_cursor(@nospecialize(io::IO), i::Int, j::Int)
    write(io, "$(CSI)$(i);$(j)H")
    return nothing
end

"""
    _restore_cursor(io::IO) -> Nothing

Restore the previously saved cursor position in screen `io`.
"""
function _restore_cursor(@nospecialize(io::IO))
    write(io, "$(CSI)u")
    return nothing
end

"""
    _save_cursor(io::IO) -> Nothing

Save the current cursor position in screen `io`.
"""
function _save_cursor(@nospecialize(io::IO))
    write(io, "$(CSI)s")
    return nothing
end

"""
    _show_cursor(io::IO) -> Nothing

Show the cursor in `io`.
"""
function _show_cursor(@nospecialize(io::IO))
    write(io, "$(CSI)?25h")
    return nothing
end

"""
    _turn_on_alternate_screen_buffer(io::IO) -> Nothing

Turn on the alternate screen buffer in `io`, clearing it first.
"""
function _turn_on_alternate_screen_buffer(@nospecialize(io::IO))
    write(io, "$(CSI)?1049h")
    return nothing
end

"""
    _turn_off_alternate_screen_buffer(io::IO) -> Nothing

Turn off the alternate screen buffer in `io`, restoring the old buffer.
"""
function _turn_off_alternate_screen_buffer(@nospecialize(io::IO))
    write(io, "$(CSI)?1049l")
    return nothing
end
