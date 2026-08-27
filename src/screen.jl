## Description #############################################################################
#
# Functions related to screen management.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# ANSI escape sequences that do not depend on any parameter. Writing a constant string does
# not allocate, whereas interpolating one at every call does.
const _ALT_SCREEN_OFF = "$(CSI)?1049l"
const _ALT_SCREEN_ON = "$(CSI)?1049h"
const _CLEAR_SCREEN = "$(CSI)2J"
const _CLEAR_TO_EOL = "$(CSI)0K"
const _CURSOR_HOME = "$(CSI)1;1H"
const _CURSOR_KEYS_OFF = "$(CSI)?1l"
const _CURSOR_KEYS_ON = "$(CSI)?1h"
const _HIDE_CURSOR = "$(CSI)?25l"
const _SHOW_CURSOR = "$(CSI)?25h"

# The mouse is reported with the SGR encoding, which is unambiguous for any position.
const _MOUSE_ON = "$(CSI)?1000h$(CSI)?1006h"
const _MOUSE_OFF = "$(CSI)?1006l$(CSI)?1000l"

# Parameterized escape sequences are assembled from precomputed pieces. Building them with
# string interpolation allocates roughly 640 bytes per call, which the redraw path pays once
# per screen row. `print(io, ::Int)` is not an alternative because it materializes a `String`
# as well.
#
# Notice that the functions assembling these sequences are not annotated with
# `@nospecialize`. Otherwise, every `write` inside them is a dynamic dispatch whose `Int`
# return value must be boxed, which allocates 16 bytes per call.
const _MAX_CACHED_DECIMAL = 1023
const _MAX_CACHED_ROW = 512

const _DECIMAL_CACHE = String[string(i) for i in 0:_MAX_CACHED_DECIMAL]

# Almost every cursor movement in the redraw path targets the first column, so the whole
# sequence is cached for those.
const _MOVE_ROW_CACHE = String[string(CSI, i, ";1H") for i in 1:_MAX_CACHED_ROW]

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _write_decimal(io::IO, n::Int) -> Int

Write the decimal representation of `n` to `io` without allocating for common values.

# Arguments

- `io::IO`: Terminal output stream to update.
- `n::Int`: Number to write.
"""
function _write_decimal(io::IO, n::Int)
    if 0 <= n <= _MAX_CACHED_DECIMAL
        return write(io, @inbounds _DECIMAL_CACHE[n + 1])
    end

    return write(io, string(n))
end

"""
    _clear_screen(io::IO) -> Nothing

Clear `io` and move its cursor to the first row and column.

Notice that the clearing uses a single escape sequence, which adds new lines to the
terminal and hence preserves its history.

# Arguments

- `io::IO`: Output stream that represents the terminal screen.
"""
function _clear_screen(@nospecialize(io::IO))
    write(io, _CLEAR_SCREEN)
    write(io, _CURSOR_HOME)
    return nothing
end

"""
    _clear_to_eol(io::IO) -> Int

Clear `io` from the cursor through the end of the current line.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
# Notice that this function must specialize: the redraw path calls it once per painted row
# with a concrete buffer, and the generic method would dispatch dynamically at every call.
_clear_to_eol(io::IO) = write(io, _CLEAR_TO_EOL)

"""
    _hide_cursor(io::IO) -> Int

Hide the cursor in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_hide_cursor(@nospecialize(io::IO)) = write(io, _HIDE_CURSOR)

"""
    _move_cursor(io::IO, i::Int, j::Int) -> Int

Move the cursor in `io` to row `i` and column `j`.

# Arguments

- `io::IO`: Terminal output stream to update.
- `i::Int`: One-based destination row.
- `j::Int`: One-based destination column.
"""
function _move_cursor(io::IO, i::Int, j::Int)
    if (j == 1) && (1 <= i <= _MAX_CACHED_ROW)
        return write(io, @inbounds _MOVE_ROW_CACHE[i])
    end

    n = write(io, CSI)
    n += _write_decimal(io, i)
    n += write(io, UInt8(';'))
    n += _write_decimal(io, j)
    n += write(io, UInt8('H'))
    return n
end

"""
    _show_cursor(io::IO) -> Int

Show the cursor in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_show_cursor(@nospecialize(io::IO)) = write(io, _SHOW_CURSOR)

"""
    _turn_on_mouse(io::IO) -> Int

Enable the mouse reporting in `io` with the SGR encoding.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_on_mouse(@nospecialize(io::IO)) = write(io, _MOUSE_ON)

"""
    _turn_off_mouse(io::IO) -> Int

Disable the mouse reporting in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_off_mouse(@nospecialize(io::IO)) = write(io, _MOUSE_OFF)

"""
    _turn_on_alternate_screen_buffer(io::IO) -> Int

Enable and clear the alternate screen buffer in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_on_alternate_screen_buffer(@nospecialize(io::IO)) = write(io, _ALT_SCREEN_ON)

"""
    _turn_on_cursor_key_mode(io::IO) -> Int

Enable cursor-key mode in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_on_cursor_key_mode(@nospecialize(io::IO)) = write(io, _CURSOR_KEYS_ON)

"""
    _turn_off_alternate_screen_buffer(io::IO) -> Int

Disable the alternate screen buffer in `io` and restore the previous buffer.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_off_alternate_screen_buffer(@nospecialize(io::IO)) = write(io, _ALT_SCREEN_OFF)

"""
    _turn_off_cursor_key_mode(io::IO) -> Int

Disable cursor-key mode in `io`.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
_turn_off_cursor_key_mode(@nospecialize(io::IO)) = write(io, _CURSOR_KEYS_OFF)
