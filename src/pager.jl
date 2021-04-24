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

Initialize the pager with the string `str`.

"""
function _pager(str::AbstractString; kwargs...)
    # Initialize the terminal.
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

    # Switch the terminal to raw mode, meaning that all keystroke is immediatly
    # passed to us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    _pager!(term, str; kwargs...)

    REPL.Terminals.raw!(term, false)

    return nothing
end

"""
    _pager!(term::REPL.Terminals.TTYTerminal, str::AbstractString)

Initialize the pager with the string `str` using the terminal `term`. The user
must ensure that `term` is in raw mode.

"""
function _pager!(term::REPL.Terminals.TTYTerminal, str::AbstractString;
                 freeze_columns::Int = 0,
                 freeze_rows::Int = 0,
                 change_freeze::Bool = true,
                 hashelp::Bool = true)

    # Get the tokens (lines) of the input.
    tokens = split(str, '\n')
    num_tokens = length(tokens)

    # Clear the screen and position the cursor at the top.
    _clear_screen(term.out_stream, newlines = true)

    # The pager is divided in two parts, the view buffer and command line. The
    # view buffer contains the string that is shown. To improve speed,
    # everything in the view buffer is written to this buffer and then flushed
    # to the screen.
    iobuf = IOBuffer()
    hascolor = get(stdout, :color, true)::Bool
    buf = IOContext(iobuf, :color => hascolor)

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    features = Symbol[]
    change_freeze && push!(features, :change_freeze)
    hashelp && push!(features, :help)

    # Initialize the pager structure.
    pagerd = Pager(term = term,
                   buf = buf,
                   display_size = dsize,
                   start_row = min(max(1, freeze_rows + 1), num_tokens),
                   start_col = max(1, freeze_columns + 1),
                   lines = tokens,
                   num_lines = num_tokens,
                   freeze_columns = freeze_columns,
                   freeze_rows = freeze_rows,
                   features = features)

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

    return nothing
end

"""
    _pager_key_process!(pagerd::Pager, k::Keystroke)

Process the keystroke `k` in pager `pagerd`.

"""
function _pager_key_process!(pagerd::Pager, k::Keystroke)
    # Unpack variables.
    @unpack display_size, start_col, start_row, lines_cropped, columns_cropped,
            freeze_columns, freeze_rows, features = pagerd

    redraw = false
    event = nothing
    key = (k.value, k.alt, k.ctrl, k.shift)
    action = get(_keybindings, key, nothing)

    if action == :quit
        event = :quit

    elseif action == :help
        if :help ∈ features
            event = :help
        end

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
        min_row = max(1, freeze_rows + 1)

        if start_row > min_row
            start_row -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastup
        min_row = max(1, freeze_rows + 1)

        if start_row > min_row
            start_row -= 5
        end
        start_row < min_row && (start_row = min_row)
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
        min_col = max(1, freeze_columns + 1)

        if start_col > min_col
            start_col -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastleft
        min_col = max(1, freeze_columns + 1)

        if start_col > min_col
            start_col -= 10
            start_col < min_col && (start_col = min_col)
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

    elseif action == :halfpagedown
        if lines_cropped > 0
            start_row += min(div(display_size[1] - 1, 2), lines_cropped)
            _request_redraw!(pagerd)
        end

    elseif action == :halfpageup
        if start_row > 1
            start_row -= div(display_size[1] - 1, 2)
            start_row < 1 && (start_row = 1)
            _request_redraw!(pagerd)
        end

    elseif action == :search
        event = :search

    elseif action == :next_match
        event = :next_match

    elseif action == :previous_match
        event = :previous_match

    elseif action == :quit_search
        event = :quit_search

    elseif action == :change_freeze
        if :change_freeze ∈ features
            event = :change_freeze
        end

    elseif action == :quit_eot
        event = :quit_eot
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

    # For EOT (^D), we will implement two types of "quit" action. If we are in
    # searching mode, then exit it. If not, quit the pager.
    if event == :quit_eot
        event = pagerd.mode == :searching ? :quit_search : :quit
    end

    if event == :quit
        return false

    elseif event == :help
        _help!(pagerd)
        _request_redraw!(pagerd)

    elseif event == :search
        cmd_input = _read_cmd!(pagerd)

        # Do not search if the regex is empty.
        if !isempty(cmd_input)
            match_regex = Regex(cmd_input)
            _find_matches!(pagerd, match_regex)
            _change_active_match!(pagerd, true)
            _move_view_to_match!(pagerd)
            pagerd.mode = :searching
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

    elseif event == :quit_search
        _quit_search!(pagerd)
        _request_redraw!(pagerd)
        pagerd.mode = :view

    elseif event == :change_freeze
        cmd_input = _read_cmd!(pagerd; prefix = "Freeze rows ($(pagerd.freeze_rows)): ")
        freeze_rows = tryparse(Int, cmd_input; base = 10)

        if (freeze_rows == nothing) && !isempty(cmd_input)
            _print_cmd_message!(pagerd, "Invalid data!";
                                crayon = crayon"red bold")
            _jlgetch(pagerd.term.in_stream)

        else
            if freeze_rows != nothing
                pagerd.freeze_rows = max(0, freeze_rows)
                pagerd.start_row = max(pagerd.start_row, freeze_rows)
            end

            cmd_input = _read_cmd!(pagerd; prefix = "Freeze columns ($(pagerd.freeze_columns)): ")
            freeze_columns = tryparse(Int, cmd_input; base = 10)

            if (freeze_columns == nothing) && !isempty(cmd_input)
                _print_cmd_message!(pagerd, "Invalid data!";
                                    crayon = crayon"red bold")
                _jlgetch(pagerd.term.in_stream)

            elseif freeze_columns != nothing
                pagerd.freeze_columns = max(0, freeze_columns)
                pagerd.start_col = max(pagerd.start_col, freeze_columns)
            end
        end

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

