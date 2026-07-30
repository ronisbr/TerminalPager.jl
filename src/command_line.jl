## Description #############################################################################
#
# Functions related to the command line.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The command line hints are constant except for the numbers in them. Assembling them at every
# frame allocated roughly 950 bytes per keystroke.
const _CMD_HINT = "(↑ ↓ ← →:move, q:quit)"
const _CMD_HINT_HELP = "(↑ ↓ ← →:move, ?:help, q:quit)"
const _CMD_MATCH_PREFIX = "(match "
const _CMD_MATCH_INFIX = " of "
const _CMD_NO_MATCH = "(no match found)"
const _CMD_ERROR = "ERROR"

const _CMD_HINT_WIDTH = textwidth(_CMD_HINT)
const _CMD_HINT_HELP_WIDTH = textwidth(_CMD_HINT_HELP)

# Width of "(match  of )", that is, everything but the two numbers.
const _CMD_MATCH_WIDTH = textwidth(_CMD_MATCH_PREFIX) + textwidth(_CMD_MATCH_INFIX) + 1

# Padding is written from a slice of this string, so that right-aligning the hint does not
# allocate a full-width string at every frame.
const _BLANKS = " "^512

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _write_blanks(io::IO, n::Int) -> Int

Write `n` spaces to `io` without allocating.

# Arguments

- `io::IO`: Output stream to update.
- `n::Int`: Number of spaces to write.
"""
function _write_blanks(io::IO, n::Int)
    n <= 0 && return 0

    written = 0

    while written < n
        chunk = min(n - written, length(_BLANKS))
        written += GC.@preserve _BLANKS unsafe_write(io, pointer(_BLANKS), UInt(chunk))
    end

    return written
end

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

    use_color = get(term.out_stream, :color, true)::Bool

    # Compute the scroll position. Notice that an empty text has nothing left to scroll, so
    # we must not divide by `num_lines` here.
    percentage = if num_lines > 0
        clamp(round(Int, 100 * (1 - cropped_lines / num_lines)), 0, 100)
    else
        100
    end

    # Compute the information considering the current mode. Everything except the numbers is
    # constant, so we only need the width of the hint here.
    hint_width = 0
    match_id = 0
    num_matches = 0

    if mode == :view
        hint_width = if :help ∈ pagerd.features
            _CMD_HINT_HELP_WIDTH
        else
            _CMD_HINT_WIDTH
        end

    elseif mode == :searching
        match_id = pagerd.active_search_match_id
        num_matches = pagerd.num_matches

        hint_width = if num_matches > 0
            _CMD_MATCH_WIDTH + ndigits(match_id) + ndigits(num_matches)
        else
            length(_CMD_NO_MATCH)
        end

    else
        hint_width = length(_CMD_ERROR)
    end

    # The scroll position is always rendered as " NNN%", with the number right-aligned in
    # three columns. Since it is a percentage, it never needs more than three digits.
    hint_width += 5

    out = _screen_buffer!(pagerd)

    # Move the cursor to the last line and write the command line.
    _move_cursor(out, display_size[1], 1)
    write(out, UInt8(':'))

    if display_size[2] > (hint_width + 4)
        _write_blanks(out, display_size[2] - hint_width - 1)
        use_color && write(out, _CRAYON_G)

        if mode == :view
            write(out, :help ∈ pagerd.features ? _CMD_HINT_HELP : _CMD_HINT)

        elseif mode == :searching
            if num_matches > 0
                write(out, _CMD_MATCH_PREFIX)
                _write_decimal(out, match_id)
                write(out, _CMD_MATCH_INFIX)
                _write_decimal(out, num_matches)
                write(out, UInt8(')'))
            else
                write(out, _CMD_NO_MATCH)
            end

        else
            write(out, _CMD_ERROR)
        end

        write(out, UInt8(' '))
        _write_blanks(out, max(0, 3 - ndigits(percentage)))
        _write_decimal(out, percentage)
        write(out, UInt8('%'))

        use_color && write(out, _CRAYON_RESET)
    end

    _move_cursor(out, display_size[1], 2)

    _flush_screen!(pagerd)

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
