# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related with the command line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _redraw_cmd_line!(pagerd::Pager)

Print the command line of pager `pagerd` to the display.

"""
function _redraw_cmd_line!(pagerd::Pager)
    # Unpack variables.
    @unpack term, display_size, num_lines, lines_cropped = pagerd

    if get(term.out_stream, :color, true)
        _d = string(Crayon(reset = true))
        _g = string(crayon"dark_gray")
    else
        _d = ""
        _g = ""
    end

    # Compute the scroll position
    pos = @sprintf("%3d", 100*(1 - lines_cropped/num_lines))

    cmd_help = "(↑ ↓ ← →:move, ?:help, q:quit) $(pos)%"
    lcmd_help = length(cmd_help)

    if display_size[2] > (lcmd_help + 4)
        cmd_aligned = " "^(display_size[2] - lcmd_help - 1) * _g * cmd_help * _d
    else
        cmd_aligned = ""
    end

    # Move the cursor to the last line and print the command line.
    _move_cursor(term.out_stream, display_size[1], 0)
    write(term.out_stream, ":")
    write(term.out_stream, cmd_aligned)
    _move_cursor(term.out_stream, display_size[1], 2)

    return nothing
end

"""
    _read_cmd!(pagerd::Pager)

Read a command in the pager `pagerd`.

This function returns a string with the command.

"""
function _read_cmd!(pagerd::Pager)
    # Unpack values.
    @unpack term, display_size = pagerd

    # Initialize variables.
    cmd = ""
    cmd_width = 0
    cursor_pos = 1
    prefix = "/"
    prefix_size = 1
    redraw = true

    while true
        if redraw
            # Clear command line.
            _move_cursor(term.out_stream, display_size[1], 1)
            _clear_to_eol(term.out_stream)
            write(term.out_stream, prefix * cmd)

            # Restore the cursor position
            _move_cursor(term.out_stream,
                         display_size[1],
                         cursor_pos + prefix_size)

            redraw = false
        end

        k = _jlgetch(term.in_stream)

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
                _cursor_back(term.out_stream)
            end

        elseif k.value == :right
            if cursor_pos < cmd_width + 1
                cursor_pos += 1
                _cursor_forward(term.out_stream)
            end

        elseif k.value == :home
            cursor_pos = 1
            _move_cursor(term.out_stream,
                         display_size[1],
                         cursor_pos + prefix_size)

        elseif k.value == :end
            cursor_pos = cmd_width + 1
            _move_cursor(term.out_stream,
                         display_size[1],
                         cursor_pos + prefix_size)
        end
    end

    return cmd
end
