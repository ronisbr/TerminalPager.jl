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

# Get the display size of the pager `p`.
function _get_pager_display_size(p::Pager)
    rows, cols = p.display_size

    # We need to remove one row due to the command line.
    rows -= 1

    return rows, cols
end

# Request a redraw of pager `p`.
_request_redraw!(p::Pager) = (p.redraw = true)

# Update the display size information in the pager `p`.
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

# Initialize the pager with the string `str`.
function _pager(str::String; kwargs...)
    # Initialize the terminal.
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

    # Switch the terminal to raw mode, meaning that all keystroke is immediatly
    # passed to us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    _pager!(term, str; kwargs...)

    REPL.Terminals.raw!(term, false)

    return nothing
end

# Initialize the pager with the string `str` using the terminal `term`. The user
# must ensure that `term` is in raw mode.
function _pager!(
    term::REPL.Terminals.TTYTerminal,
    str::String;
    auto::Bool = false,
    change_freeze::Bool = true,
    frozen_columns::Int = 0,
    frozen_rows::Int = 0,
    title_rows::Int = 0,
    hashelp::Bool = true,
    show_ruler::Bool = false
)
    # Get the tokens (lines) of the input.
    tokens = split(str, '\n')
    num_tokens = length(tokens)

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    # If `auto` is true, then only show the pager if the text is larger than the
    # screen.
    if auto
        # Regex to remove the ANSI escape sequence so that we can obtain the
        # printable size of the text.
        regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
        use_pager = false

        # Check if we can display everything vertically. Notice that here we
        # must account two lines at the end.
        if dsize[1] - 2 ≥ num_tokens
            for t in tokens
                t_undecorated = String(*(split(t, regex_ansi)...))
                if textwidth(t_undecorated) > dsize[2]
                    use_pager = true
                    break
                end
            end

        else
            use_pager = true
        end

        if !use_pager
            print(str)
            return nothing
        end
    end

    # Clear the screen and position the cursor at the top.
    _clear_screen(term.out_stream, newlines = true)

    # The pager is divided in two parts, the view buffer and command line. The
    # view buffer contains the string that is shown. To improve speed,
    # everything in the view buffer is written to this buffer and then flushed
    # to the screen.
    iobuf    = IOBuffer()
    hascolor = get(stdout, :color, true)::Bool
    buf      = IOContext(iobuf, :color => hascolor)

    features = Symbol[]
    change_freeze && push!(features, :change_freeze)
    hashelp && push!(features, :help)

    # Initialize the pager structure.
    pagerd = Pager(
        buf            = buf,
        display_size   = dsize,
        features       = features,
        frozen_columns = frozen_columns,
        frozen_rows    = frozen_rows,
        lines          = tokens,
        num_lines      = num_tokens,
        show_ruler     = show_ruler,
        start_column   = max(1, frozen_columns + 1),
        start_row      = min(max(1, frozen_rows + 1), num_tokens),
        term           = term,
        title_rows     = title_rows
    )

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
    cropped_columns = pagerd.cropped_columns
    display_size    = pagerd.display_size
    features        = pagerd.features
    frozen_columns  = pagerd.frozen_columns
    frozen_rows     = pagerd.frozen_rows
    cropped_lines   = pagerd.cropped_lines
    start_column    = pagerd.start_column
    start_row       = pagerd.start_row

    redraw = false
    event = nothing
    key = (k.value, k.alt, k.ctrl, k.shift)
    action = get(_keybindings, key, nothing)

    # Compute the minimum values for start row and start column.
    min_row = max(1, frozen_rows + 1)
    min_col = max(1, frozen_columns + 1)

    if action == :quit
        event = :quit

    elseif action == :help
        if :help ∈ features
            event = :help
        end

    elseif action == :down
        if cropped_lines > 0
            start_row += 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastdown
        if cropped_lines > 0
            start_row += min(5, cropped_lines)
            _request_redraw!(pagerd)
        end

    elseif action == :up
        if start_row > min_row
            start_row -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastup
        if start_row > min_row
            start_row -= 5
        end

        if start_row < min_row
            start_row = min_row
        end

        _request_redraw!(pagerd)

    elseif action == :right
        if cropped_columns > 0
            start_column += 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastright
        if cropped_columns > 0
            start_column += min(10, cropped_columns)
            _request_redraw!(pagerd)
        end

    elseif action == :eol
        if cropped_columns > 0
            start_column += cropped_columns
            _request_redraw!(pagerd)
        end

    elseif action == :left
        if start_column > min_col
            start_column -= 1
            _request_redraw!(pagerd)
        end

    elseif action == :fastleft
        if start_column > min_col
            start_column -= 10

            if start_column < min_col
                start_column = min_col
            end

            _request_redraw!(pagerd)
        end

    elseif action == :bol
        if start_column ≠ min_col
            start_column = min_col
            _request_redraw!(pagerd)
        end

    elseif action == :end
        if cropped_lines > 0
            start_row += cropped_lines
            _request_redraw!(pagerd)
        end

    elseif action == :home
        if start_row ≠ min_row
            start_row = min_row
            _request_redraw!(pagerd)
        end

    elseif action == :pagedown
        if cropped_lines > 0
            start_row += min(display_size[1] - 1, cropped_lines)
            _request_redraw!(pagerd)
        end

    elseif action == :pageup
        if start_row ≠ min_row
            start_row -= (display_size[1] - 1)

            if start_row < min_row
                start_row = min_row
            end

            _request_redraw!(pagerd)
        end

    elseif action == :halfpagedown
        if cropped_lines > 0
            start_row += min(div(display_size[1] - 1, 2), cropped_lines)
            _request_redraw!(pagerd)
        end

    elseif action == :halfpageup
        if start_row ≠ min_row
            start_row -= div(display_size[1] - 1, 2)

            if start_row < min_row
                start_row = min_row
            end

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

    elseif action == :change_title_rows
        if :change_freeze ∈ features
            event = :change_title_rows
        end

    elseif action == :toggle_ruler
        event = :toggle_ruler

    elseif action == :quit_eot
        event = :quit_eot

    end

    # Repack values.
    pagerd.start_column    = start_column
    pagerd.start_row       = start_row
    pagerd.cropped_lines   = cropped_lines
    pagerd.cropped_columns = cropped_columns
    pagerd.event           = event

    return nothing
end

# Process the event in `pagerd`. If this function return `false`, then the
# application must exit.
function _pager_event_process!(pagerd::Pager)
    event = pagerd.event
    lines = pagerd.lines

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
        cmd_input = _read_cmd!(
            pagerd;
            prefix = "Frozen rows # ($(pagerd.frozen_rows)): "
        )
        frozen_rows = tryparse(Int, cmd_input; base = 10)

        if (frozen_rows == nothing) && !isempty(cmd_input)
            _print_cmd_message!(
                pagerd,
                "Invalid data!";
                crayon = crayon"red bold"
            )
            _jlgetch(pagerd.term.in_stream)
        else
            if frozen_rows != nothing
                pagerd.frozen_rows = max(0, frozen_rows)
                pagerd.start_row = max(pagerd.start_row, frozen_rows + 1)
            end

            cmd_input = _read_cmd!(
                pagerd;
                prefix = "Frozen columns # ($(pagerd.frozen_columns)): "
            )
            frozen_columns = tryparse(Int, cmd_input; base = 10)

            if (frozen_columns == nothing) && !isempty(cmd_input)
                _print_cmd_message!(
                    pagerd, "Invalid data!";
                    crayon = crayon"red bold"
                )
                _jlgetch(pagerd.term.in_stream)

            elseif frozen_columns != nothing
                pagerd.frozen_columns = max(0, frozen_columns)
                pagerd.start_column = max(pagerd.start_column, frozen_columns + 1)
            end
        end

        _request_redraw!(pagerd)

    elseif event == :change_title_rows
        cmd_input = _read_cmd!(
            pagerd;
            prefix = "Title rows ($(pagerd.title_rows)): "
        )
        title_rows = tryparse(Int, cmd_input; base = 10)

        if (title_rows == nothing) && !isempty(cmd_input)
            _print_cmd_message!(
                pagerd,
                "Invalid data!";
                crayon = crayon"red bold"
            )
            _jlgetch(pagerd.term.in_stream)
        else
            title_rows != nothing && (pagerd.title_rows = max(0, title_rows))
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_ruler
        pagerd.show_ruler = !pagerd.show_ruler

        # If the ruler is hidden, we must verify if the screen is on the right
        # edge to fix the `start_column`.
        if !pagerd.show_ruler
            ruler_spacing = floor(Int, pagerd.num_lines |> abs |> log10) + 4

            if pagerd.cropped_columns ≤ ruler_spacing
                pagerd.start_column -= ruler_spacing
                pagerd.start_column < 1 && (pagerd.start_column = 1)
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
    buf          = pagerd.buf
    term         = pagerd.term
    display_size = _get_pager_display_size(pagerd)

    str       = String(take!(buf.io))
    lines     = split(str, '\n')
    num_lines = length(lines)

    _move_cursor(term.out_stream, 1, 1)

    # Hide the cursor when drawing the buffer.
    _hide_cursor(term.out_stream)

    @inbounds for i = 1:num_lines
        _clear_to_eol(term.out_stream)
        write(term.out_stream, lines[i])
        write(term.out_stream, '\n')
    end

    # Clear the rest of the screen.
    for i = (num_lines + 1):display_size[1]
        _move_cursor(term.out_stream, i, 1)
        _clear_to_eol(term.out_stream)
    end

    # Show the cursor.
    _show_cursor(term.out_stream)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end
