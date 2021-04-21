# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related with the command line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _redraw_cmd_line(io::IO, display_size::NTuple{2, Int}, pos::Float64)

Print the command line to the screen.

"""
function _redraw_cmd_line(io::IO, display_size::NTuple{2, Int}, pos::Float64)
    if get(io, :color, true)
        _d = string(Crayon(reset = true))
        _g = string(crayon"dark_gray")
    else
        _d = ""
        _g = ""
    end

    # Compute the scroll position.
    pos = @sprintf("%3d", 100pos)

    cmd_help = "(↑ ↓ ← →:move, ?:help, q:quit) $(pos)%"
    lcmd_help = length(cmd_help)

    if display_size[2] > (lcmd_help + 4)
        cmd_aligned = " "^(display_size[2] - lcmd_help - 1) * _g * cmd_help * _d
    else
        cmd_aligned = ""
    end

    # Move the cursor to the last line and print the command line.
    _move_cursor(io, display_size[1], 0)
    write(io, ":")
    write(io, cmd_aligned)
    _move_cursor(io, display_size[1], 2)

    return nothing
end

"""
    _read_cmd(io::IO, in::IO, display_size::NTuple{2, Int}; prefix::String = "/")

Read a command. The output stream is `io` and the input stream is `in`. The
display size must be passed in `display_size`. The command prefix can be
specified by the keyword `prefix`.

This function returns a string with the command.

"""
function _read_cmd(io::IO, in::IO, display_size::NTuple{2, Int};
                   prefix::String = "/")
    redraw = true
    cmd = ""
    cmd_width = 0
    cursor_pos = 1
    prefix_size = textwidth(prefix)

    while true
        if redraw
            # Clear command line.
            _move_cursor(io, display_size[1], 1)
            _clear_to_eol(io)
            write(io, prefix * cmd)

            # Restore the cursor position.
            _move_cursor(io, display_size[1], cursor_pos + prefix_size)
            redraw = false
        end

        k = _jlgetch(in)

        if k.value == :enter
            break

        elseif k.value isa String
            cmd = first(cmd, (cursor_pos - 1)) *
                  k.value *
                  last(cmd, cmd_width - (cursor_pos - 1))
            cmd_width += 1
            cursor_pos += 1
            redraw = true

        elseif k.value == :backspace
            if cmd_width > 0
                cmd = first(cmd, cmd_width - 1)
                cmd_width -= 1
                cursor_pos -= 1
                redraw = true
            end

        elseif k.value == :left
            if cursor_pos > 1
                cursor_pos -= 1
                _cursor_back(io)
            end

        elseif k.value == :right
            if cursor_pos < cmd_width + 1
                cursor_pos += 1
                _cursor_forward(io)
            end

        elseif k.value == :home
            cursor_pos = 1
            _move_cursor(io, display_size[1], cursor_pos + prefix_size)

        elseif k.value == :end
            cursor_pos = cmd_width + 1
            _move_cursor(io, display_size[1], cursor_pos + prefix_size)
        end
    end

    return cmd
end
