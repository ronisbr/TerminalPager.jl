# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to the pager.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


################################################################################
#                    Functions related to `Pager` structure
################################################################################

"""
    _request_redraw!(p::Pager)

Request a redraw of pager `p`.

"""
_request_redraw!(p::Pager) = (p.redraw = true)

"""
    _update_display_size!(p::Pager)

Update the display size information in the pager `p`.

"""
function _update_display_size!(p::Pager)
    # If the terminal size has changed, then we need to redraw the view.
    newdsize::Tuple{Int, Int} = displaysize(p.term.out_stream)

    if newdsize != p.display_size
        p.display_size = newdsize
        _request_redraw!(p)
    end

    return nothing
end

################################################################################
#                        Functions related to the pager
################################################################################

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

    # The pager is divided in two parts, the view buffer and command line. The
    # view buffer contains the string that is shown. To improve speed,
    # everything in the view buffer is written to this buffer and then flushed
    # to the screen.
    iobuf = IOBuffer()
    buf = IOContext(iobuf, :color => get(stdout, :color, true))

    # Initialize the pager structure.
    pagerd = Pager(term = term,
                   buf = buf,
                   display_size = displaysize(term.out_stream),
                   start_row = 1,
                   start_col = 1,
                   lines = tokens,
                   num_lines = num_tokens)

    # Switch the terminal to raw mode, meaning that all keystroke is immediatly
    # passed to us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    # Application main loop
    # ==========================================================================

    while true
        # Check if the display size was changed.
        _update_display_size!(pagerd)

        # Check if we need to redraw the screen.
        if pagerd.redraw
            _view!(pagerd)
            _redraw!(pagerd)
            _redraw_cmd_line!(pagerd)
        end

        # Wait for the user input.
        k = _jlgetch(term.in_stream)
        _pager_key_process!(pagerd, k)
        _pager_event_process!(pagerd) || break
    end

    REPL.Terminals.raw!(term, false)

    return nothing
end

"""
    _pager_key_process!(pagerd::Pager, k::Keystroke)

Process the keystroke `k` in pager `pagerd`.

"""
function _pager_key_process!(pagerd::Pager, k::Keystroke)
    # Unpack variables.
    @unpack display_size, start_col, start_row, lines_cropped, columns_cropped =
            pagerd

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
            _request_redraw!(pagerd)
        end

    elseif action == :fastdown
        if lines_cropped > 0
            start_row += min(5, lines_cropped)
            _request_redraw!(pagerd)
        end

    elseif action == :up
        if start_row > 1
            start_row -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastup
        if start_row > 1
            start_row -= 5
        end
        start_row < 1 && (start_row = 1)
        _request_redraw!(pagerd)

    elseif action == :right
        if columns_cropped > 0
            start_col += 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastright
        if columns_cropped > 0
            start_col += min(10, columns_cropped)
            _request_redraw!(pagerd)
        end

    elseif action == :eol
        if columns_cropped > 0
            start_col += columns_cropped
            _request_redraw!(pagerd)
        end

    elseif action == :left
        if start_col > 1
            start_col -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastleft
        if start_col > 1
            start_col -= 10
            start_col < 1 && (start_col = 1)
            _request_redraw!(pagerd)
        end

    elseif action == :bol
        if start_col > 1
            start_col = 1
            _request_redraw!(pagerd)
        end

    elseif action == :end
        if lines_cropped > 0
            start_row += lines_cropped
            _request_redraw!(pagerd)
        end

    elseif action == :home
        if start_row > 1
            start_row = 1
            _request_redraw!(pagerd)
        end

    elseif action == :pagedown
        if lines_cropped > 0
            start_row += min(display_size[1] - 1, lines_cropped)
            _request_redraw!(pagerd)
        end

    elseif action == :pageup
        if start_row > 1
            start_row -= (display_size[1] - 1)
            start_row < 1 && (start_row = 1)
            _request_redraw!(pagerd)
        end

    elseif action == :search
        event = :search

    elseif action == :next_match
        event = :next_match

    elseif action == :previous_match
        event = :previous_match

    end

    # Repack values.
    @pack! pagerd = start_col, start_row, lines_cropped, columns_cropped, event

    return nothing
end

"""
    _pager_event_process!(pagerd::Pager)

Process the event in `pagerd`. If this function return `false`, then the
application must exit.

"""
function _pager_event_process!(pagerd::Pager)
    @unpack event, lines = pagerd

    if event == :quit
        return false

    elseif event == :help
        _draw_help!(pagerd)

    elseif event == :search
        cmd_input = _read_cmd!(pagerd)

        # Do not search if the regex is empty.
        if !isempty(cmd_input)
            match_regex = Regex(cmd_input)
            _find_matches!(pagerd, match_regex)
            _change_active_match!(pagerd, true)
            _move_view_to_match!(pagerd)
        end

        _request_redraw!(pagerd)

    elseif event == :next_match
        _change_active_match!(pagerd, true)
        _move_view_to_match!(pagerd)
        _request_redraw!(pagerd)

    elseif event == :previous_match
        _change_active_match!(pagerd, false)
        _move_view_to_match!(pagerd)
        _request_redraw!(pagerd)

    end

    return true
end

"""
    _redraw!(pagerd::Pager)

Redraw the screen of pager `pagerd`.

"""
function _redraw!(pagerd::Pager)
    @unpack buf, term, display_size = pagerd

    str = String(take!(buf.io))
    lines = split(str, '\n')
    num_lines = length(lines)

    _move_cursor(term.out_stream, 0, 0)

    # Hide the cursor when drawing the buffer.
    _hide_cursor(term.out_stream)

    for i = 1:num_lines
        write(term.out_stream, lines[i])
        _clear_to_eol(term.out_stream)
        i ≠ num_lines && write(term.out_stream, '\n')
    end

    # Clear the rest of the screen.
    for i = (num_lines + 1):display_size[1]
        _move_cursor(term.out_stream, i - 1, 0)
        _clear_to_eol(term.out_stream)
    end

    # Show the cursor.
    _show_cursor(term.out_stream)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end

