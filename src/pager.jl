# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to the pager.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _pager(str::AbstractString)

Initialize the pager of the string `str`.

"""
function _pager(str::AbstractString)
    # Get the tokens (lines) of the input.
    tokens = split(str, '\n')
    num_tokens = length(tokens)

    # Initialize the terminal.
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

    # Clear the screen and position the cursor at the top.
    _clear_screen(term.out_stream)
    _move_cursor(term.out_stream, 0, 0)

    # Initialize the variables.
    start_row = 1
    start_col = 1
    aux = 1

    # Switch the terminal to raw mode, meaning that all keystroke is immediatly
    # passed to us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    # To improve speed, everything is written to this buffer and then flushed to
    # the screen.
    buf = IOBuffer()
    io = IOContext(buf, :color => get(stdout, :color, true))

    # Initialize the variables.
    redraw = true
    start_row = 1
    start_col = 1
    lines_cropped = 0
    columns_cropped = 0

    # Store the current terminal size.
    dsize = displaysize(term.out_stream)

    while true
        # If the terminal size has changed, then we need to redraw the view.
        newdsize = displaysize(term.out_stream)

        if newdsize != dsize
            redraw = true
            dsize = newdsize
        end

        # Check if we need to redraw the screen.
        if redraw
            lines_cropped, columns_cropped = _view(io,
                                                   tokens,
                                                   (dsize[1]-1, dsize[2]),
                                                   start_row,
                                                   start_col)
            _print_cmd_line(io, dsize, 1 - lines_cropped / num_tokens)
            _redraw(term.out_stream, buf)
            redraw = false
        end

        k = _jlgetch(term.in_stream)

        if k.value == "q"
            break
        elseif k.value == "?"
            _print_help(io)
            _redraw(term.out_stream, buf)
            redraw = true
            _jlgetch(term.in_stream)
        else
            start_col, start_row, redraw =
                _pager_keyprocess(k,
                                  start_col,
                                  start_row,
                                  lines_cropped,
                                  columns_cropped,
                                  dsize[1]-1)
        end
    end
    REPL.Terminals.raw!(term, false)

    return nothing
end

"""
    _redraw(out::IO, in::IOBuffer)

Redraw the screen `out` with the contents in the buffer `in`.

"""
function _redraw(out::IO, in::IOBuffer)
    _clear_screen(out)
    _move_cursor(out, 0, 0)
    write(out, take!(in))
    return nothing
end

"""
    _pager_keyprocess(k::Keystroke, start_col::Int, start_row::Int, lines_cropped::Int, columns_cropped::Int, display_rows::Int)

Process the keystroke `k` using the information in the other parameters. It
returns the new `start_col`, the new `start_row`, and a `Bool` indicating
whether the display must be redraw.

"""
function _pager_keyprocess(k::Keystroke,
                           start_col::Int,
                           start_row::Int,
                           lines_cropped::Int,
                           columns_cropped::Int,
                           display_rows::Int)
    redraw = false

    if k.ktype == :down
        if lines_cropped > 0
            if k.shift
                start_row += min(5, lines_cropped)
            else
                start_row += 1
            end

            redraw = true
        end
    elseif k.ktype == :up
        if start_row > 1
            if k.shift
                start_row -= 5
            else
                start_row -= 1
            end

            start_row < 1 && (start_row = 1)

            redraw = true
        end
    elseif k.ktype == :right
        if columns_cropped > 0
            if k.shift
                start_col += min(10, columns_cropped)
            else
                start_col += 1
            end

            redraw = true
        end
    elseif k.ktype == :left
        if start_col > 1
            if k.shift
                start_col -= 10
            else
                start_col -= 1
            end

            start_col < 1 && (start_col = 1)

            redraw = true
        end
    elseif k.ktype == :end
        if columns_cropped > 0
            start_col += columns_cropped
            redraw = true
        end
    elseif k.ktype == :home
        if start_col > 1
            start_col = 1
            redraw = true
        end
    elseif k.ktype == :pagedown
        if lines_cropped > 0
            start_row += min(display_rows, lines_cropped)
            redraw = true
        end
    elseif k.ktype == :pageup
        if start_row > 1
            start_row -= display_rows
            start_row < 1 && (start_row = 1)
            redraw = true
        end
    end


    return start_col, start_row, redraw
end

"""
    _view(io::IO, tokens::Vector{String}, screen_size::NTuple{2,Int}, start_row::Int, start_col::Int)

Show a view of `tokens` in `io` considering the screen size `screen_size` and
the start row and column `start_row` and `start_col`.

"""
function _view(io::IO,
               tokens::Vector{T} where T<:AbstractString,
               screen_size::NTuple{2,Int},
               start_row::Int,
               start_col::Int)

    # Get the available display size.
    rows, cols = screen_size

    # Make sure that the argument values are correct.
    start_row < 1 && (start_row = 1)
    start_col ≤ 1 && (start_col = 1)

    # Printed lines.
    num_printed_lines = 0

    # Regex that matches ANSI escape characters.
    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    # Indicate whether a line has been cropped.
    lines_cropped = 0

    # Indicate if all columns were displayed.
    columns_cropped = 0

    for i = start_row:length(tokens)
        line = tokens[i]

        # Split the lines into escape sequence and text.
        ansi        = collect(eachmatch(regex_ansi, line))
        line_tokens = split(line, regex_ansi)

        # Number of printed columns.
        num_printed_cols = 0

        # Number of virtual columns analyzed.
        num_virtual_cols = 0

        # Indicate that we reached the requested column.
        initial_cropping = true

        # Print the text between ANSI escape sequences.
        for j = 1:length(line_tokens)
            token_width = textwidth(line_tokens[j])

            # We need to find the requested start column.
            if initial_cropping
                if (num_virtual_cols + token_width) < start_col
                    num_virtual_cols += token_width
                    j ≤ length(ansi) && write(io, ansi[j].match)
                    continue
                else
                    line_str = _crop_str(line_tokens[j], start_col - num_virtual_cols)
                    line_width = textwidth(line_str)
                    initial_cropping = false
                end
            else
                line_str = line_tokens[j]
                line_width = token_width
            end

            Δ = cols - num_printed_cols

            # Check if we need to crop the line.
            if Δ < line_width
                Δ > 0 && write(io, _crop_str(line_str, 1, Δ))

                # In this case, we must apply all remaining regexes.
                for k = i:length(ansi)
                    write(io, ansi[k].match)
                end

                columns_cropped = max(lines_cropped, line_width - Δ)
                break
            else
                write(io, line_str)
                j == length(line_tokens) && break
                num_printed_cols += line_width
                write(io, ansi[j].match)
            end
        end

        write(io, '\n')
        num_printed_lines += 1

        if num_printed_lines ≥ rows
            lines_cropped = length(tokens) - rows - start_row
            break
        end
    end

    return lines_cropped, columns_cropped
end
