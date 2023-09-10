# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions related to the pager.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

############################################################################################
#                          Functions Related to `Pager` Structure
############################################################################################

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

############################################################################################
#                              Functions Related to the Pager
############################################################################################

# Initialize the pager with the string `str`.
function _pager(str::String; kwargs...)
    # Initialize the terminal.
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

    # Switch the terminal to raw mode, meaning that all keystroke is immediately passed to
    # us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    _pager!(term, str; kwargs...)

    REPL.Terminals.raw!(term, false)

    return nothing
end

# Initialize the pager with the string `str` using the terminal `term`. The user must ensure
# that `term` is in raw mode.
function _pager!(
    term::REPL.Terminals.TTYTerminal,
    str::String;
    auto::Bool = false,
    change_freeze::Bool = true,
    frozen_columns::Int = 0,
    frozen_rows::Int = 0,
    title_rows::Int = 0,
    hashelp::Bool = true,
    has_visual_mode::Bool = true,
    show_ruler::Bool = false
)
    # Get the tokens (lines) of the input.
    tokens = split(str, '\n')
    num_tokens = length(tokens)

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    # If `auto` is true, then only show the pager if the text is larger than the screen.
    if auto
        use_pager = false

        # Check if we can display everything vertically. Notice that here we must account
        # two lines at the end.
        if dsize[1] - 2 ≥ num_tokens
            for t in tokens
                # Compute the printable textwidth.
                ptw = printable_textwidth(t)

                if ptw > dsize[2]
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

    # The pager is divided in two parts, the view buffer and command line. The view buffer
    # contains the string that is shown. To improve speed, everything in the view buffer is
    # written to this buffer and then flushed to the screen.
    iobuf    = IOBuffer()
    hascolor = get(stdout, :color, true)::Bool
    buf      = IOContext(iobuf, :color => hascolor)

    features = Symbol[]
    change_freeze && push!(features, :change_freeze)
    hashelp && push!(features, :help)
    has_visual_mode && push!(features, :visual_mode)

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

    # Application Main Loop
    # ======================================================================================

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

# Process the keystroke `k` in pager `pagerd`.
function _pager_key_process!(pagerd::Pager, k::Keystroke)
    # Unpack variables.
    cropped_columns  = pagerd.cropped_columns
    display_size     = pagerd.display_size
    features         = pagerd.features
    frozen_columns   = pagerd.frozen_columns
    frozen_rows      = pagerd.frozen_rows
    cropped_lines    = pagerd.cropped_lines
    num_lines        = pagerd.num_lines
    start_column     = pagerd.start_column
    start_row        = pagerd.start_row
    visual_mode      = pagerd.visual_mode
    visual_mode_line = pagerd.visual_mode_line

    redraw = false
    event = nothing
    key = (k.value, k.alt, k.ctrl, k.shift)
    action = get(_keybindings, key, nothing)

    # Compute the minimum values for start row and start column.
    min_row = max(1, frozen_rows + 1)
    min_col = max(1, frozen_columns + 1)

    # We should disable the visual line mode if all lines are frozen.
    if (min_row >= num_lines) || (min_row >= display_size[1])
        visual_mode = false
    end

    if action == :quit
        event = :quit

    elseif action == :help
        if :help ∈ features
            event = :help
        end

    elseif action == :down
        if visual_mode && (visual_mode_line < display_size[1] - frozen_rows - 1)
            visual_mode_line += 1

            # The visual line must not be placed after the last line.
            if min_row + visual_mode_line - 1 > num_lines
                visual_mode_line = num_lines - min_row + 1
            end

            _request_redraw!(pagerd)
        else
            if cropped_lines > 0
                start_row += 1
                _request_redraw!(pagerd)
            end
        end

    elseif action == :fastdown
        if visual_mode && (visual_mode_line < display_size[1] - frozen_rows - 1)
            visual_mode_line += 5

            # If we passed the last line, we should keep the visual line in the last line,
            # but scroll the view.
            Δy = visual_mode_line - (display_size[1] - frozen_rows - 1)

            if Δy > 0
                start_row += min(Δy, cropped_lines)
                visual_mode_line = display_size[1] - frozen_rows - 1
            end

            # The visual line must not be placed after the last line.
            if min_row + visual_mode_line - 1 > num_lines
                visual_mode_line = num_lines - min_row + 1
            end

            _request_redraw!(pagerd)
        else
            if cropped_lines > 0
                start_row += min(5, cropped_lines)
                _request_redraw!(pagerd)
            end
        end

    elseif action == :up
        if visual_mode && (visual_mode_line > 1)
            visual_mode_line -= 1
            _request_redraw!(pagerd)
        else
            if start_row > min_row
                start_row -= 1
                _request_redraw!(pagerd)
            end
        end

    elseif action == :fastup
        if visual_mode && (visual_mode_line > 1)
            visual_mode_line -= 5

            if visual_mode_line < 1
                visual_mode_line = 1
            end

            _request_redraw!(pagerd)
        else
            if start_row > min_row
                start_row -= 5
                _request_redraw!(pagerd)
            end

            if start_row < min_row
                start_row = min_row
            end
        end

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

    elseif action == (:end)
        if cropped_lines > 0
            start_row += cropped_lines
            _request_redraw!(pagerd)
        end

        if visual_mode && (visual_mode_line ≠ display_size[1] - frozen_rows - 1)
            visual_mode_line = display_size[1] - frozen_rows - 1

            # The visual line must not be placed after the last line.
            if min_row + visual_mode_line - 1 > num_lines
                visual_mode_line = num_lines - min_row + 1
            end

            _request_redraw!(pagerd)
        end

    elseif action == :home
        if start_row ≠ min_row
            start_row = min_row
            _request_redraw!(pagerd)
        end

        if visual_mode && (visual_mode_line != 1)
            visual_mode_line = 1
            _request_redraw!(pagerd)
        end

    elseif action == :pagedown
        if cropped_lines > 0
            start_row += min(display_size[1] - 1, cropped_lines)

            _request_redraw!(pagerd)
        end

        if visual_mode && (visual_mode_line ≠ display_size[1] - frozen_rows - 1)
            visual_mode_line = display_size[1] - frozen_rows - 1

            # The visual line must not be placed after the last line.
            if min_row + visual_mode_line - 1 > num_lines
                visual_mode_line = num_lines - min_row + 1
            end

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

        if visual_mode && (visual_mode_line ≠ 1)
            visual_mode_line = 1
            _request_redraw!(pagerd)
        end

    elseif action == :halfpagedown
        if visual_mode && (visual_mode_line < display_size[1] - frozen_rows - 1)
            visual_mode_line += div(display_size[1] - 1, 2)

            # If we passed the last line, we should keep the visual line in the last line,
            # but scroll the view.
            Δy = visual_mode_line - (display_size[1] - frozen_rows - 1)

            if Δy > 0
                start_row += min(Δy, cropped_lines)
                visual_mode_line = display_size[1] - frozen_rows - 1
            end

            # The visual line must not be placed after the last line.
            if min_row + visual_mode_line - 1 > num_lines
                visual_mode_line = num_lines - min_row + 1
            end

            _request_redraw!(pagerd)
        else
            if cropped_lines > 0
                start_row += min(div(display_size[1] - 1, 2), cropped_lines)
                _request_redraw!(pagerd)
            end
        end

    elseif action == :halfpageup
        if visual_mode && (visual_mode_line > 1)
            visual_mode_line -= div(display_size[1] - 1, 2)

            if visual_mode_line < 1
                visual_mode_line = 1
            end

            _request_redraw!(pagerd)
        else
            if start_row ≠ min_row
                start_row -= div(display_size[1] - 1, 2)

                if start_row < min_row
                    start_row = min_row
                end

                _request_redraw!(pagerd)
            end
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

    elseif action == :toggle_visual_mode
        if :visual_mode ∈ features
            event = :toggle_visual_mode
        end

    elseif action == :select_visual_mode_line
        if :visual_mode ∈ features
            event = :select_visual_mode_line
        end

    elseif action == :yank
        if :visual_mode ∈ features
            event = :yank
        end

    elseif action == :quit_eot
        event = :quit_eot

    end

    # Repack values.
    pagerd.start_column     = start_column
    pagerd.start_row        = start_row
    pagerd.cropped_lines    = cropped_lines
    pagerd.cropped_columns  = cropped_columns
    pagerd.event            = event
    pagerd.visual_mode_line = visual_mode_line

    return nothing
end

# Process the event in `pagerd`. If this function return `false`, the application must exit.
function _pager_event_process!(pagerd::Pager)
    event = pagerd.event
    lines = pagerd.lines

    # For EOT (^D), we will implement two types of "quit" action. If we are in searching
    # mode, exit it. If not, quit the pager.
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
                pagerd.visual_mode_line = 1
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

        # If the ruler is hidden, we must verify if the screen is on the right edge to fix
        # the `start_column`.
        if !pagerd.show_ruler
            ruler_spacing = floor(Int, pagerd.num_lines |> abs |> log10) + 4

            if pagerd.cropped_columns ≤ ruler_spacing
                pagerd.start_column -= ruler_spacing
                pagerd.start_column < 1 && (pagerd.start_column = 1)
            end
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_visual_mode
        pagerd.visual_mode = !pagerd.visual_mode

        if !pagerd.visual_mode
            pagerd.visual_mode_line = 1
            empty!(pagerd.visual_mode_selected_lines)
        end

        _request_redraw!(pagerd)

    elseif event == :select_visual_mode_line
        if pagerd.visual_mode
            visual_str_id = pagerd.visual_mode_line + pagerd.start_row - 1

            # If the line is already selected, we will deselect it.
            ids = findall(==(visual_str_id), pagerd.visual_mode_selected_lines)

            if !isempty(ids)
                deleteat!(pagerd.visual_mode_selected_lines, ids)
            else
                push!(pagerd.visual_mode_selected_lines, visual_str_id)
            end
        end

    elseif event == :yank
        if pagerd.visual_mode
            yanked_lines = vcat(
                pagerd.visual_mode_line + pagerd.start_row - 1,
                pagerd.visual_mode_selected_lines
            ) |> unique! |> sort!

            num_yanked_lines = length(yanked_lines)

            buf = IOBuffer(sizehint = floor(Int, sum(sizeof.(yanked_lines)) + num_yanked_lines))

            for l in yanked_lines
                write(buf, pagerd.lines[l] |> remove_decorations, '\n')
            end

            clipboard(String(take!(buf)))

            _print_cmd_message!(
                pagerd,
                num_yanked_lines > 1 ? "$(num_yanked_lines) lines copied" : "1 line copied"
            )
        end
    end

    return true
end

# Redraw the screen of pager `pagerd`.
function _redraw!(pagerd::Pager)
    buf              = pagerd.buf
    term             = pagerd.term
    display_size     = _get_pager_display_size(pagerd)
    visual_mode      = pagerd.visual_mode
    visual_mode_line = pagerd.visual_mode_line

    # We will split the lines to make sure that every line is cleaned. We will not use the
    # ANSI escape sequence `\e[2J` because it adds new lines to the screen.
    str       = String(take!(buf.io))
    lines     = split(str, '\n')
    num_lines = length(lines)

    # To improve the speed, it is advisable to create an intermediate buffer to write
    # everything and then flush to the terminal.
    ibuf = IOBuffer()

    @inbounds for i in 1:num_lines
        _clear_to_eol(ibuf)
        write(ibuf, lines[i], '\n')
    end

    # Clear the rest of the screen.
    for i in (num_lines + 1):display_size[1]
        _move_cursor(ibuf, i, 1)
        _clear_to_eol(ibuf)
    end

    # Now, we can flush everything to the terminal.

    # Hide the cursor when drawing the buffer.
    _hide_cursor(term.out_stream)

    # Move the cursor to the beginning of the screen.
    _move_cursor(term.out_stream, 1, 1)

    # Write everything.
    write(term.out_stream, take!(ibuf))

    # Show the cursor again.
    _show_cursor(term.out_stream)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end
