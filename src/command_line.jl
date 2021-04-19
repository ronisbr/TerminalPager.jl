# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related with the command line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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

        if k.ktype == :enter
            break

        elseif k.ktype == :char
            cmd = first(cmd, (cursor_pos - 1)) *
                  k.value *
                  last(cmd, cmd_width - (cursor_pos - 1))
            cmd_width += 1
            cursor_pos += 1
            redraw = true

        elseif k.ktype == :backspace
            if cmd_width > 0
                cmd = first(cmd, cmd_width - 1)
                cmd_width -= 1
                cursor_pos -= 1
                redraw = true
            end

        elseif k.ktype == :left
            if cursor_pos > 1
                cursor_pos -= 1
                _cursor_back(io)
            end

        elseif k.ktype == :right
            if cursor_pos < cmd_width + 1
                cursor_pos += 1
                _cursor_forward(io)
            end

        elseif k.ktype == :home
            cursor_pos = 1
            _move_cursor(io, display_size[1], cursor_pos + prefix_size)

        elseif k.ktype == :end
            cursor_pos = cmd_width + 1
            _move_cursor(io, display_size[1], cursor_pos + prefix_size)
        end
    end

    return cmd
end
