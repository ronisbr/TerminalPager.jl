## Description #############################################################################
#
# Functions related to screen management.
#
############################################################################################

"""
    _clear_screen(io::IO; newlines::Bool = false) -> Nothing

Clear `io` and move its cursor to the first row and column.

# Arguments

- `io::IO`: Output stream that represents the terminal screen.

# Keywords

- `newlines::Bool`: Preserve screen history by clearing the terminal instead of overwriting
    each display line.
    (**Default**: `false`)
"""
function _clear_screen(@nospecialize(io::IO); newlines::Bool = false)
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

"""
    _cursor_back(io::IO, i::Int = 1) -> Int

Move the cursor in `io` backward by `i` columns.

# Arguments

- `io::IO`: Terminal output stream to update.
- `i::Int`: Number of columns to move.
    (**Default**: `1`)
"""
_cursor_back(@nospecialize(io::IO), i::Int = 1) = write(io, "$(CSI)$(i)D")

"""
    _cursor_forward(io::IO, i::Int = 1) -> Int

Move the cursor in `io` forward by `i` columns.

# Arguments

- `io::IO`: Terminal output stream to update.
- `i::Int`: Number of columns to move.
    (**Default**: `1`)
"""
_cursor_forward(@nospecialize(io::IO), i::Int = 1) = write(io, "$(CSI)$(i)C")

"""
    _clear_to_eol(io::IO) -> Int

Clear `io` from the cursor through the end of the current line.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_clear_to_eol(@nospecialize(io::IO)) = write(io, "$(CSI)0K")

"""
    _hide_cursor(io::IO) -> Int

Hide the cursor in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_hide_cursor(@nospecialize(io::IO)) = write(io, "$(CSI)?25l")

"""
    _move_cursor(io::IO, i::Int, j::Int) -> Int

Move the cursor in `io` to row `i` and column `j`.

# Arguments

- `io::IO`: Terminal output stream to update.
- `i::Int`: One-based destination row.
- `j::Int`: One-based destination column.
"""
_move_cursor(@nospecialize(io::IO), i::Int, j::Int) = write(io, "$(CSI)$(i);$(j)H")

"""
    _restore_cursor(io::IO) -> Int

Restore the saved cursor position in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_restore_cursor(@nospecialize(io::IO)) = write(io, "$(CSI)u")

"""
    _save_cursor(io::IO) -> Int

Save the current cursor position in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_save_cursor(@nospecialize(io::IO)) = write(io, "$(CSI)s")

"""
    _show_cursor(io::IO) -> Int

Show the cursor in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_show_cursor(@nospecialize(io::IO)) = write(io, "$(CSI)?25h")

"""
    _turn_on_alternate_screen_buffer(io::IO) -> Int

Enable and clear the alternate screen buffer in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_on_alternate_screen_buffer(@nospecialize(io::IO)) = write(io, "$(CSI)?1049h")

"""
    _turn_on_cursor_key_mode(io::IO) -> Int

Enable cursor-key mode in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_on_cursor_key_mode(@nospecialize(io::IO)) = write(io, "$(CSI)?1h")

"""
    _turn_off_alternate_screen_buffer(io::IO) -> Int

Disable the alternate screen buffer in `io` and restore the previous buffer.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_off_alternate_screen_buffer(@nospecialize(io::IO)) = write(io, "$(CSI)?1049l")

"""
    _turn_off_cursor_key_mode(io::IO) -> Int

Disable cursor-key mode in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_off_cursor_key_mode(@nospecialize(io::IO)) = write(io, "$(CSI)?1l")
