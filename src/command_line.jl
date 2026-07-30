## Description #############################################################################
#
# Functions related to the command line.
#
############################################################################################

"""
    _print_cmd_message!(pagerd::Pager, msg::String;
        crayon::Crayon = Crayon()) -> Nothing

Print `msg` on the pager command line.

# Arguments

- `pagerd::Pager`: Pager state whose terminal receives the message.
- `msg::String`: Message to print.

# Keywords

- `crayon::Crayon`: Formatting applied when the terminal supports color.
    (**Default**: `Crayon()`)
"""
function _print_cmd_message!(pagerd::Pager, msg::String; crayon::Crayon = Crayon())
    term = pagerd.term
    display_size = pagerd.display_size

    if get(term.out_stream, :color, true)
        _d = _CRAYON_RESET
        _h = string(crayon)
    else
        _d = ""
        _h = ""
    end

    # Move the cursor to the last line and print the message.
    _move_cursor(term.out_stream, display_size[1], 1)
    write(term.out_stream, _h)
    write(term.out_stream, msg)
    write(term.out_stream, _d)
    _clear_to_eol(term.out_stream)

    return nothing
end

"""
    _redraw_cmd_line!(pagerd::Pager) -> Nothing

Redraw the pager command line and status information.

# Arguments

- `pagerd::Pager`: Pager state to redraw.
"""
function _redraw_cmd_line!(pagerd::Pager)
    # Unpack variables.
    term = pagerd.term
    display_size = pagerd.display_size
    num_lines = pagerd.num_lines
    cropped_lines = pagerd.cropped_lines
    mode = pagerd.mode
    features = pagerd.features

    if get(term.out_stream, :color, true)::Bool
        _d = _CRAYON_RESET
        _g = _CRAYON_G
    else
        _d = ""
        _g = ""
    end

    # Compute the information considering the current mode.
    if mode == :view
        cmd_help = "(↑ ↓ ← →:move, "

        if :help ∈ features
            cmd_help *= "?:help, "
        end

        cmd_help *= "q:quit)"

    elseif mode == :searching
        active_search_match_id = pagerd.active_search_match_id
        num_matches = pagerd.num_matches

        # Check if there are matches.
        if num_matches > 0
            cmd_help =
                "(match " *
                string(active_search_match_id) *
                " of " *
                string(num_matches) *
                ")"
        else
            cmd_help = "(no match found)"
        end

    else
        cmd_help = "ERROR"
    end

    # Compute the scroll position. Notice that an empty text has nothing left to scroll, so
    # we must not divide by `num_lines` here.
    percentage = num_lines > 0 ? round(Int, 100 * (1 - cropped_lines / num_lines)) : 100
    cmd_help *= " " * lpad(string(percentage), 3) * "%"

    lcmd_help = length(cmd_help)

    if display_size[2] > (lcmd_help + 4)
        cmd_aligned = " "^(display_size[2] - lcmd_help - 1) * _g * cmd_help * _d
    else
        cmd_aligned = ""
    end

    # Move the cursor to the last line and print the command line.
    _move_cursor(term.out_stream, display_size[1], 1)
    write(term.out_stream, ":" * cmd_aligned)
    _move_cursor(term.out_stream, display_size[1], 2)

    return nothing
end

"""
    _read_cmd!(pagerd::Pager; prefix::String = "/") -> String

Read and edit one command from the pager input.

# Arguments

- `pagerd::Pager`: Pager state whose terminal and input are used.

# Keywords

- `prefix::String`: Prompt displayed before the command.
    (**Default**: `"/"`)
"""
function _read_cmd!(pagerd::Pager; prefix::String = "/")
    # Unpack values.
    term = pagerd.term
    display_size = pagerd.display_size

    # Initialize variables.
    cmd = ""
    cmd_width = 0
    cursor_pos = 1
    prefix_size = textwidth(prefix)
    redraw = true

    while true
        if redraw
            # Clear command line.
            _move_cursor(term.out_stream, display_size[1], 1)
            _clear_to_eol(term.out_stream)
            write(term.out_stream, prefix * cmd)

            # Restore the cursor position.
            _move_cursor(term.out_stream, display_size[1], cursor_pos + prefix_size)

            redraw = false
        end

        k = _read_keystroke!(pagerd.input)

        if k.value == "<enter>"
            break

        elseif k.value == "<backspace>"
            if cmd_width > 0
                cmd = first(cmd, cmd_width - 1)
                cmd_width -= 1
                cursor_pos -= 1
                redraw = true
            else
                break
            end

        elseif k.value == "<left>"
            if cursor_pos > 1
                cursor_pos -= 1
                _cursor_back(term.out_stream)
            end

        elseif k.value == "<right>"
            if cursor_pos < cmd_width + 1
                cursor_pos += 1
                _cursor_forward(term.out_stream)
            end

        elseif k.value == "<home>"
            cursor_pos = 1
            _move_cursor(term.out_stream, display_size[1], cursor_pos + prefix_size)

        elseif k.value == "<end>"
            cursor_pos = cmd_width + 1
            _move_cursor(term.out_stream, display_size[1], cursor_pos + prefix_size)

        else
            cmd =
                first(cmd, (cursor_pos - 1)) *
                string(k.value) *
                last(cmd, cmd_width - (cursor_pos - 1))

            cmd_width += 1
            cursor_pos += 1
            redraw = true
        end
    end

    return cmd
end
