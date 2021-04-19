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
        elseif k.value == "/"
            _read_cmd(term.out_stream, term.in_stream, dsize)
            redraw = true
        else
            start_row, start_col, redraw =
                _pager_keyprocess(k,
                                  start_row,
                                  start_col,
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
    _pager_keyprocess(k::Keystroke, start_row::Int, start_col::Int, lines_cropped::Int, columns_cropped::Int, display_rows::Int)

Process the keystroke `k` using the information in the other parameters. It
returns the new `start_row`, the new `start_col`, and a `Bool` indicating
whether the display must be redraw.

"""
function _pager_keyprocess(k::Keystroke,
                           start_row::Int,
                           start_col::Int,
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
            if k.alt
                start_col += columns_cropped
            elseif k.shift
                start_col += min(10, columns_cropped)
            else
                start_col += 1
            end

            redraw = true
        end
    elseif k.ktype == :left
        if start_col > 1
            if k.alt
                start_col = 1
            elseif k.shift
                start_col -= 10
            else
                start_col -= 1
            end

            start_col < 1 && (start_col = 1)

            redraw = true
        end
    elseif k.ktype == :end
        if lines_cropped > 0
            start_row += lines_cropped
            redraw = true
        end
    elseif k.ktype == :home
        if start_row > 1
            start_row = 1
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

    return start_row, start_col, redraw
end

