# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related with the command line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Print the message `msg` in the command line of pager `pagerd`. The string
# formatting can be selected using the keyword `crayon`.
function _print_cmd_message!(
    pagerd::Pager,
    msg::String;
    crayon::Crayon = Crayon()
)

    term         = pagerd.term
    display_size = pagerd.display_size

    if get(term.out_stream, :color, true)
        _d = _CRAYON_RESET
        _h = string(crayon)
    else
        _d = ""
        _h = ""
    end

    # Move the cursor to the last line and print the message.
    _move_cursor(term.out_stream, display_size[1], 0)
    write(term.out_stream, _h)
    write(term.out_stream, msg)
    write(term.out_stream, _d)
    _clear_to_eol(term.out_stream)

    return nothing
end

# Print the command line of pager `pagerd` to the display.
function _redraw_cmd_line!(pagerd::Pager)
    # Unpack variables.
    term          = pagerd.term
    display_size  = pagerd.display_size
    num_lines     = pagerd.num_lines
    cropped_lines = pagerd.cropped_lines
    mode          = pagerd.mode
    features      = pagerd.features

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
        search_matches         = pagerd.search_matches

        num_matches = length(search_matches)

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

    # Compute the scroll position
    pos = lpad(round(Int, 100 * (1 - cropped_lines / num_lines)) |> string, 3)
    cmd_help *= " " * pos * "%"

    lcmd_help = length(cmd_help)

    if display_size[2] > (lcmd_help + 4)
        cmd_aligned = " "^(display_size[2] - lcmd_help - 1) * _g * cmd_help * _d
    else
        cmd_aligned = ""
    end

    # Move the cursor to the last line and print the command line.
    _move_cursor(term.out_stream, display_size[1], 0)
    write(term.out_stream, ":" * cmd_aligned)
    _move_cursor(term.out_stream, display_size[1], 2)

    return nothing
end

# Read a command in the pager `pagerd`.
# This function returns a string with the command.
function _read_cmd!(pagerd::Pager; prefix::String = "/")
    # Unpack values.
    term         = pagerd.term
    display_size = pagerd.display_size

    # Initialize variables.
    cmd         = ""
    cmd_width   = 0
    cursor_pos  = 1
    prefix_size = textwidth(prefix)
    redraw      = true

    while true
        if redraw
            # Clear command line.
            _move_cursor(term.out_stream, display_size[1], 1)
            _clear_to_eol(term.out_stream)
            write(term.out_stream, prefix * cmd)

            # Restore the cursor position
            _move_cursor(
                term.out_stream,
                display_size[1],
                cursor_pos + prefix_size
            )

            redraw = false
        end

        k = _jlgetch(term.in_stream)

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
            _move_cursor(
                term.out_stream,
                display_size[1],
                cursor_pos + prefix_size
            )

        elseif k.value == "<end>"
            cursor_pos = cmd_width + 1
            _move_cursor(
                term.out_stream,
                display_size[1],
                cursor_pos + prefix_size
            )

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
