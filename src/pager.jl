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
    _clear_screen(term.out_stream, newlines = true)

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
    dsize::Tuple{Int, Int} = displaysize(term.out_stream)

    while true
        # If the terminal size has changed, then we need to redraw the view.
        newdsize::Tuple{Int, Int} = displaysize(term.out_stream)

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

        start_row, start_col, redraw, event =
            _pager_keyprocess(k,
                              start_row,
                              start_col,
                              lines_cropped,
                              columns_cropped,
                              dsize[1]-1)

        if event == :quit
            break
        elseif event == :help
            _print_help(io)
            _redraw(term.out_stream, buf)
            redraw = true
            _jlgetch(term.in_stream)
        elseif k.value == "/"
            _read_cmd(term.out_stream, term.in_stream, dsize)
            redraw = true
        else
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
    write(out, take!(in))
    return nothing
end

"""
    _pager_keyprocess(k::Keystroke, start_row::Int, start_col::Int, lines_cropped::Int, columns_cropped::Int, display_rows::Int)

Process the keystroke `k` using the information in the other parameters. It
returns the new `start_row`, the new `start_col`, a `Bool` indicating whether
the display must be redraw, and an event.

"""
function _pager_keyprocess(k::Keystroke,
                           start_row::Int,
                           start_col::Int,
                           lines_cropped::Int,
                           columns_cropped::Int,
                           display_rows::Int)
    redraw = false
    event = nothing
    key = (k.value, k.alt, k.ctrl, k.shift)
    action = get(_default_keybindings, key, nothing)

    if action == :quit
        event = :quit

    elseif action == :help
        event = :help

    elseif action == :down
        if lines_cropped > 0
            start_row += 1
            redraw = true
        end

    elseif action == :fastdown
        if lines_cropped > 0
            start_row += min(5, lines_cropped)
            redraw = true
        end

    elseif action == :up
        if start_row > 1
            start_row -= 1
            redraw = true
        end

    elseif action == :fastup
        if start_row > 1
            start_row -= 5
        end
        start_row < 1 && (start_row = 1)
        redraw = true

    elseif action == :right
        if columns_cropped > 0
            start_col += 1
            redraw = true
        end

    elseif action == :fastright
        if columns_cropped > 0
            start_col += min(10, columns_cropped)
            redraw = true
        end

    elseif action == :eol
        if columns_cropped > 0
            start_col += columns_cropped
            redraw = true
        end

    elseif action == :left
        if start_col > 1
            start_col -= 1
            redraw = true
        end

    elseif action == :fastleft
        if start_col > 1
            start_col -= 10
            start_col < 1 && (start_col = 1)
            redraw = true
        end

    elseif action == :bol
        if start_col > 1
            start_col = 1
            redraw = true
        end

    elseif action == :end
        if lines_cropped > 0
            start_row += lines_cropped
            redraw = true
        end

    elseif action == :home
        if start_row > 1
            start_row = 1
            redraw = true
        end

    elseif action == :pagedown
        if lines_cropped > 0
            start_row += min(display_rows, lines_cropped)
            redraw = true
        end

    elseif action == :pageup
        if start_row > 1
            start_row -= display_rows
            start_row < 1 && (start_row = 1)
            redraw = true
        end
    end

    return start_row, start_col, redraw, event
end

