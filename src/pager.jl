## Description #############################################################################
#
# Functions related to the pager.
#
############################################################################################

############################################################################################
#                          Functions Related to `Pager` Structure                          #
############################################################################################

"""
    _get_pager_display_size(p::Pager) -> Tuple{Int, Int}

Return the available pager rows and columns after reserving the command line.

# Arguments

- `p::Pager`: Pager state whose display size is queried.
"""
function _get_pager_display_size(p::Pager)
    rows, cols = p.display_size

    # We need to remove one row due to the command line.
    rows -= 1

    return rows, cols
end

"""
    _ruler_width(num_lines::Int) -> Int

Return the number of columns the line-number ruler occupies for `num_lines` lines.

# Arguments

- `num_lines::Int`: Number of lines in the pager text.
"""
function _ruler_width(num_lines::Int)
    # This must match how `StringManipulation.textview` sizes the ruler. Notice that
    # `ndigits` is defined for 0, whereas `floor(Int, log10(num_lines))` throws an
    # `InexactError` for an empty text.
    return ndigits(num_lines) + 3
end

"""
    _request_redraw!(p::Pager) -> Bool

Mark `p` for redraw and return the assigned value, `true`.

# Arguments

- `p::Pager`: Pager state to mark for redraw.
"""
_request_redraw!(p::Pager) = (p.redraw = true)

"""
    _update_display_size!(p::Pager) -> Nothing

Update the recorded display size and request a redraw when the terminal size changes.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _update_display_size!(p::Pager)
    # If the terminal size has changed, then we need to redraw the view.
    newdsize::Tuple{Int, Int} = displaysize(p.term.out_stream)

    if newdsize != p.display_size
        p.display_size = newdsize

        # The terminal dropped or revealed rows, so we no longer know what is on screen.
        _invalidate_frame!(p)
        _request_redraw!(p)
    end

    return nothing
end

############################################################################################
#                              Functions Related to the Pager                              #
############################################################################################

"""
    _pager(str::String; kwargs...) -> Nothing

Open an interactive pager for `str`, or print it directly when automatic mode fits.

# Arguments

- `str::String`: Text to display.

# Keywords

- `auto::Bool`: Print fitting text without creating a layout or terminal session.
    (**Default**: `false`)
- `_display_config_loader::Any`: Callable object that creates the session
    display configuration.
    (**Default**: `_display_config`)
- `_input_factory::Any`: Callable object that creates input state for a stream.
    (**Default**: `PagerInput`)
- `_layout_factory::Any`: Callable object that creates a prepared text
    layout.
    (**Default**: `TextViewLayout`)
- `_terminal_factory::Any`: Callable object that creates the terminal. By default, create a
    `REPL.Terminals.TTYTerminal` connected to the standard streams.
    (**Default**: `() -> REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)`)
- `_raw_runner::Any`: Callable object that runs the pager callback in raw
    mode.
    (**Default**: `_with_raw_mode`)
- `kwargs...`: Additional keywords forwarded to [`_pager!`](@ref).
"""
function _pager(
    str::String;
    auto::Bool = false,
    _display_config_loader = _display_config,
    _input_factory = PagerInput,
    _layout_factory = TextViewLayout,
    _terminal_factory = () -> REPL.Terminals.TTYTerminal("", stdin, stdout, stderr),
    _raw_runner = _with_raw_mode,
    kwargs...,
)
    # `split` yields `SubString`s, and both `_pager_content_fits` and `TextViewLayout` accept
    # them. Copying every line into a `String` here duplicated the whole text before the first
    # frame was shown.
    lines = split(str, '\n')
    display_size = displaysize(stdout)::Tuple{Int, Int}
    if auto && _pager_content_fits(lines, display_size)
        print(str)
        return nothing
    end

    text_layout = _layout_factory(lines)
    display_config = _display_config_loader()
    input = _input_factory(stdin)

    # Initialize the terminal.
    term = _terminal_factory()

    # Switch the terminal to raw mode so that every keystroke is passed immediately instead
    # of waiting for <return>.
    _raw_runner(term) do
        _pager!(
            term,
            str;
            auto = false,
            display_config = display_config,
            input = input,
            text_layout = text_layout,
            kwargs...,
        )
    end

    return nothing
end

"""
    _with_raw_mode(f::Any, term::Any; raw_function::Any = REPL.Terminals.raw!) -> Any

Enable raw mode on `term` while executing `f` and restore it after normal return or an
exception.

# Arguments

- `f::Any`: Callable object to execute in raw mode.
- `term::Any`: Object passed to `raw_function` as the terminal.

# Keywords

- `raw_function::Any`: Callable object used to enable and disable raw mode.
    (**Default**: `REPL.Terminals.raw!`)

# Returns

- `Any`: Result returned by `f`.
"""
function _with_raw_mode(f, term; raw_function = REPL.Terminals.raw!)
    raw_enabled = false
    try
        raw_enabled = true
        raw_function(term, true)
        return f()
    finally
        raw_enabled && raw_function(term, false)
    end
end

"""
    _pager!(term::REPL.Terminals.TTYTerminal, str::String; kwargs...) -> Nothing

Run the interactive pager for `str` using a terminal that is already in raw mode.

# Arguments

- `term::REPL.Terminals.TTYTerminal`: Terminal used by the pager session.
- `str::String`: Text to display.

# Keywords

- `auto::Bool`: Print fitting text without opening the interactive pager.
    (**Default**: `false`)
- `change_freeze::Bool`: Enable commands that change frozen rows and columns.
    (**Default**: `true`)
- `display_config::Union{Nothing, DisplayConfig}`: Prepared session display
    configuration, or `nothing` to load one.
    (**Default**: `nothing`)
- `frozen_columns::Int`: Number of leading columns to freeze.
    (**Default**: `0`)
- `frozen_rows::Int`: Number of leading rows to freeze.
    (**Default**: `0`)
- `title_rows::Int`: Number of leading title rows.
    (**Default**: `0`)
- `hashelp::Bool`: Enable pager help.
    (**Default**: `true`)
- `has_visual_mode::Bool`: Enable visual selection mode.
    (**Default**: `true`)
- `show_ruler::Bool`: Show the line-number ruler initially.
    (**Default**: `false`)
- `use_alternate_screen_buffer::Bool`: Request the terminal's alternate screen
    buffer.
    (**Default**: `false`)
- `input::Union{Nothing, PagerInput}`: Input state associated with the terminal
    input stream, or `nothing` to create one.
    (**Default**: `nothing`)
- `lines::Union{Nothing, AbstractVector{<:AbstractString}}`: Raw lines used when no layout is
    supplied.
    (**Default**: `nothing`)
- `text_layout::Union{Nothing, TextViewLayout}`: Prepared layout used directly
    when supplied, or `nothing` to construct one.
    (**Default**: `nothing`)
- `_layout_factory::Any`: Callable object that creates a layout from raw
    lines.
    (**Default**: `TextViewLayout`)
- `manage_cursor_key_mode::Bool`: Enable and restore terminal cursor-key mode.
    (**Default**: `true`)
"""
function _pager!(
    @nospecialize(term::REPL.Terminals.TTYTerminal),
    str::String;
    auto::Bool = false,
    change_freeze::Bool = true,
    display_config::Union{Nothing, DisplayConfig} = nothing,
    frozen_columns::Int = 0,
    frozen_rows::Int = 0,
    title_rows::Int = 0,
    hashelp::Bool = true,
    has_visual_mode::Bool = true,
    show_ruler::Bool = false,
    use_alternate_screen_buffer::Bool = false,
    input::Union{Nothing, PagerInput} = nothing,
    lines::Union{Nothing, AbstractVector{<:AbstractString}} = nothing,
    text_layout::Union{Nothing, TextViewLayout} = nothing,
    _layout_factory = TextViewLayout,
    manage_cursor_key_mode::Bool = true,
)
    # Split once and reuse the result for auto-fit and layout construction.
    source_lines = if !isnothing(text_layout)
        text_layout
    elseif !isnothing(lines)
        lines
    else
        split(str, '\n')
    end

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    if auto && _pager_content_fits(source_lines, dsize)
        print(str)
        return nothing
    end

    session_layout = isnothing(text_layout) ? _layout_factory(source_lines) : text_layout
    num_tokens = length(session_layout)
    session_config = isnothing(display_config) ? _display_config() : display_config
    session_input = isnothing(input) ? PagerInput(term.in_stream) : input
    session_input.stream === term.in_stream ||
        throw(ArgumentError("PagerInput must own the pager terminal input stream."))

    # Check if we should block the alternate screen buffer.
    block_alternate_screen_buffer = _get_preference("block_alternate_screen_buffer")
    use_alternate_screen_buffer &= !block_alternate_screen_buffer

    cursor_key_mode_enabled = false
    alternate_screen_enabled = false
    try
        if manage_cursor_key_mode
            cursor_key_mode_enabled = true
            _turn_on_cursor_key_mode(term.out_stream)
        end

        # Clear the screen and position the cursor at the top.
        if use_alternate_screen_buffer
            alternate_screen_enabled = true
            _turn_on_alternate_screen_buffer(term.out_stream)
        else
            _clear_screen(term.out_stream; newlines = true)
        end

        # The pager is divided into a view buffer and command line. Everything in the view
        # buffer is written to this buffer and then flushed to the screen.
        iobuf = IOBuffer()
        hascolor = get(stdout, :color, true)::Bool
        buf = IOContext(iobuf, :color => hascolor)

        features = Symbol[]
        change_freeze && push!(features, :change_freeze)
        hashelp && push!(features, :help)
        has_visual_mode && push!(features, :visual_mode)

        # Initialize the pager structure.
        pagerd = Pager(;
            buf = buf,
            display_config = session_config,
            display_size = dsize,
            features = features,
            frozen_columns = frozen_columns,
            frozen_rows = frozen_rows,
            input = session_input,
            num_lines = num_tokens,
            show_ruler = show_ruler,
            start_column = max(1, frozen_columns + 1),
            start_row = min(max(1, frozen_rows + 1), num_tokens),
            term = term,
            text_layout = session_layout,
            title_rows = title_rows,
        )

        # == Application Main Loop =========================================================

        while true
            # Check if the display size was changed.
            _update_display_size!(pagerd)

            # Check if we need to redraw the screen.
            if pagerd.redraw
                _view!(pagerd)
                _redraw!(pagerd)
                _redraw_cmd_line!(pagerd)
            end

            # Wait for user input.
            k = _read_keystroke!(pagerd.input)
            before_row = pagerd.start_row
            before_column = pagerd.start_column
            action = _pager_key_process!(pagerd, k)
            _update_crop_after_action!(pagerd, before_row, before_column, action)
            _coalesce_navigation!(pagerd, action)
            _pager_event_process!(pagerd) || break
        end
    finally
        try
            alternate_screen_enabled && _turn_off_alternate_screen_buffer(term.out_stream)
        finally
            cursor_key_mode_enabled && _turn_off_cursor_key_mode(term.out_stream)
        end
    end

    return nothing
end

"""
    _pager_content_fits(
        lines::AbstractVector{<:AbstractString},
        display_size::Tuple{Int, Int}
    ) -> Bool

Return whether `lines` fit without opening a pager, reserving two terminal rows.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Lines to measure.
- `display_size::Tuple{Int, Int}`: Available terminal rows and columns.
"""
function _pager_content_fits(
    lines::AbstractVector{<:AbstractString}, display_size::Tuple{Int, Int}
)
    display_size[1] - 2 >= length(lines) || return false
    return all(line -> printable_textwidth(line) <= display_size[2], lines)
end

function _pager_content_fits(layout::TextViewLayout, display_size::Tuple{Int, Int})
    display_size[1] - 2 >= length(layout) || return false

    # The layout already measured every line while it was prepared, so there is no need to scan
    # the text again. This is the path every `pager>` REPL command takes.
    return all(width -> width <= display_size[2], layout._printable_widths)
end

"""
    _pager_key_process!(pagerd::Pager, k::Keystroke) -> Union{Nothing, Symbol}

Process `k`, update pager state, and return the resolved action.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `k::Keystroke`: Keystroke to process.
"""
function _pager_key_process!(pagerd::Pager, k::Keystroke)
    # Unpack variables.
    cropped_columns = pagerd.cropped_columns
    display_size = pagerd.display_size
    features = pagerd.features
    frozen_columns = pagerd.frozen_columns
    frozen_rows = pagerd.frozen_rows
    cropped_lines = pagerd.cropped_lines
    num_lines = pagerd.num_lines
    start_column = pagerd.start_column
    start_row = pagerd.start_row
    visual_mode = pagerd.visual_mode
    visual_mode_line = pagerd.visual_mode_line

    event = nothing
    action = _pager_action(k)

    # Compute the minimum values for start row and start column.
    min_row = max(1, frozen_rows + 1)
    min_col = max(1, frozen_columns + 1)

    # We should disable the visual line mode if all lines are frozen. Notice that the view has
    # `display_size[1] - 1` rows, because the last one is the command line.
    if (min_row >= num_lines) || (min_row >= display_size[1] - 1)
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

    # The visual line is relative to the viewport, so it must always agree with `start_row`
    # and with the number of rows the view has. Clamping it inside each movement branch left
    # the cursor past the last line whenever the state was changed elsewhere, for example by
    # `:change_freeze`, and the yank then indexed the layout out of bounds.
    if visual_mode
        max_visual_line = min(display_size[1] - frozen_rows - 1, num_lines - start_row + 1)
        visual_mode_line = clamp(visual_mode_line, 1, max(1, max_visual_line))
    end

    # Repack values. Notice that `cropped_lines` and `cropped_columns` are not written back,
    # because they are owned by `_update_crop_after_action!` and `_view!`.
    pagerd.start_column = start_column
    pagerd.start_row = start_row
    pagerd.event = event
    pagerd.visual_mode = visual_mode
    pagerd.visual_mode_line = visual_mode_line

    return action
end

"""
    _pager_action(k::Keystroke) -> Union{Nothing, Symbol}

Resolve the configured pager action for keystroke `k`.

# Arguments

- `k::Keystroke`: Keystroke to resolve.
"""
function _pager_action(k::Keystroke)
    key = (k.value, k.alt, k.ctrl, k.shift)
    return get(_KEYBINDINGS, key, nothing)
end

const _VERTICAL_FORWARD_ACTIONS = (:down, :fastdown, :pagedown, :halfpagedown, :end)
const _VERTICAL_BACKWARD_ACTIONS = (:up, :fastup, :pageup, :halfpageup, :home)
const _HORIZONTAL_FORWARD_ACTIONS = (:right, :fastright, :eol)
const _HORIZONTAL_BACKWARD_ACTIONS = (:left, :fastleft, :bol)

"""
    _navigation_axis(action::Union{Nothing, Symbol}) -> Union{Nothing, Symbol}

Return the navigation axis for a pure movement action.

# Arguments

- `action::Union{Nothing, Symbol}`: Resolved pager action.
"""
function _navigation_axis(action)
    group = _navigation_group(action)
    group in (:vertical_forward, :vertical_backward) && return :vertical
    group in (:horizontal_forward, :horizontal_backward) && return :horizontal
    return nothing
end

"""
    _navigation_group(action::Union{Nothing, Symbol}) -> Union{Nothing, Symbol}

Return the monotonic axis-and-direction group for a pure movement action.

# Arguments

- `action::Union{Nothing, Symbol}`: Resolved pager action.
"""
function _navigation_group(action)
    action in _VERTICAL_FORWARD_ACTIONS && return :vertical_forward
    action in _VERTICAL_BACKWARD_ACTIONS && return :vertical_backward
    action in _HORIZONTAL_FORWARD_ACTIONS && return :horizontal_forward
    action in _HORIZONTAL_BACKWARD_ACTIONS && return :horizontal_backward
    return nothing
end

"""
    _update_crop_after_action!(
        pagerd::Pager,
        old_row::Int,
        old_column::Int,
        action::Union{Nothing, Symbol}
    ) -> Nothing

Update crop metrics by the signed viewport delta after one navigation action.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `old_row::Int`: Viewport row before the action.
- `old_column::Int`: Viewport column before the action.
- `action::Union{Nothing, Symbol}`: Resolved pager action.
"""
function _update_crop_after_action!(pagerd::Pager, old_row::Int, old_column::Int, action)
    axis = _navigation_axis(action)
    if axis === :vertical
        pagerd.cropped_lines = max(0, pagerd.cropped_lines - (pagerd.start_row - old_row))
    elseif axis === :horizontal
        pagerd.cropped_columns = max(
            0, pagerd.cropped_columns - (pagerd.start_column - old_column)
        )
    end
    return nothing
end

"""
    _coalesce_navigation!(pagerd::Pager, first_action::Union{Nothing, Symbol};
        max_actions::Int = 128,
        max_ns::UInt64 = UInt64(4_000_000),
        display_size_function::Any = displaysize) -> Int

Replay already-buffered navigation in the same direction group and retain the first
boundary.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `first_action::Union{Nothing, Symbol}`: First action in the candidate navigation burst.

# Keywords

- `max_actions::Int`: Maximum number of actions to coalesce.
    (**Default**: `128`)
- `max_ns::UInt64`: Maximum elapsed nanoseconds spent coalescing.
    (**Default**: `UInt64(4_000_000)`)
- `display_size_function::Any`: Callable object used to detect display-size changes.
    (**Default**: `displaysize`)

# Returns

- `Int`: Number of actions processed, including `first_action`.
"""
function _coalesce_navigation!(
    pagerd::Pager,
    first_action;
    max_actions::Int = 128,
    max_ns::UInt64 = UInt64(4_000_000),
    display_size_function = displaysize,
)
    group = _navigation_group(first_action)
    isnothing(group) && return 1
    count = 1
    start_time = time_ns()

    # The display size is queried once per burst instead of once per action. On a real terminal
    # this is a `TIOCGWINSZ` system call, and issuing up to `max_actions` of them consumed a
    # noticeable part of the `max_ns` budget, which reduced how many keystrokes could be
    # coalesced. A resize during the burst is handled by `_update_display_size!` on the next
    # iteration of the main loop, and the burst itself is bounded by `max_ns`.
    display_size_function(pagerd.term.out_stream) == pagerd.display_size || return count

    while count < max_actions && time_ns() - start_time < max_ns
        key = _try_read_keystroke!(pagerd.input)
        isnothing(key) && break
        action = _pager_action(key)
        if _navigation_group(action) !== group
            pagerd.input.pending = key
            break
        end

        old_row = pagerd.start_row
        old_column = pagerd.start_column
        _pager_key_process!(pagerd, key)
        _update_crop_after_action!(pagerd, old_row, old_column, action)
        count += 1
    end

    return count
end

"""
    _pager_event_process!(pagerd::Pager) -> Bool

Process the pending pager event and return whether the application should continue.

# Arguments

- `pagerd::Pager`: Pager state whose pending event is processed.
"""
function _pager_event_process!(pagerd::Pager)
    event = pagerd.event

    # For EOT (^D), we will implement two types of "quit" action. If we are in searching
    # mode, exit it. If not, quit the pager.
    if event == :quit_eot
        event = pagerd.mode == :searching ? :quit_search : :quit
    end

    if event == :quit
        return false

    elseif event == :help
        _help!(pagerd)

        # The nested pager repainted the whole screen.
        _invalidate_frame!(pagerd)
        _request_redraw!(pagerd)

    elseif event == :search
        cmd_input = _read_cmd!(pagerd)

        # Do not search if the regex is empty.
        if !isempty(cmd_input)
            match_regex = _try_regex(cmd_input)

            if isnothing(match_regex)
                _print_cmd_message!(pagerd, "Invalid regex!"; crayon = crayon"red bold")
                _read_keystroke!(pagerd.input)
            else
                _find_matches!(pagerd, match_regex)
                _change_active_match!(pagerd, true)
                _move_view_to_match!(pagerd)
                pagerd.mode = :searching
            end
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
        cmd_input = _read_cmd!(pagerd; prefix = "Frozen rows # ($(pagerd.frozen_rows)): ")
        frozen_rows = tryparse(Int, cmd_input; base = 10)

        if isnothing(frozen_rows) && !isempty(cmd_input)
            _print_cmd_message!(pagerd, "Invalid data!"; crayon = crayon"red bold")
            _read_keystroke!(pagerd.input)
        else
            if !isnothing(frozen_rows)
                pagerd.frozen_rows = max(0, frozen_rows)
                pagerd.start_row = max(pagerd.start_row, frozen_rows + 1)
                pagerd.visual_mode_line = 1
            end

            cmd_input = _read_cmd!(
                pagerd; prefix = "Frozen columns # ($(pagerd.frozen_columns)): "
            )
            frozen_columns = tryparse(Int, cmd_input; base = 10)

            if isnothing(frozen_columns) && !isempty(cmd_input)
                _print_cmd_message!(pagerd, "Invalid data!"; crayon = crayon"red bold")
                _read_keystroke!(pagerd.input)

            elseif !isnothing(frozen_columns)
                pagerd.frozen_columns = max(0, frozen_columns)
                pagerd.start_column = max(pagerd.start_column, frozen_columns + 1)
            end
        end

        _request_redraw!(pagerd)

    elseif event == :change_title_rows
        cmd_input = _read_cmd!(pagerd; prefix = "Title rows ($(pagerd.title_rows)): ")
        title_rows = tryparse(Int, cmd_input; base = 10)

        if isnothing(title_rows) && !isempty(cmd_input)
            _print_cmd_message!(pagerd, "Invalid data!"; crayon = crayon"red bold")
            _read_keystroke!(pagerd.input)
        elseif !isnothing(title_rows)
            pagerd.title_rows = max(0, title_rows)
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_ruler
        pagerd.show_ruler = !pagerd.show_ruler

        # If the ruler is hidden, we must verify if the screen is on the right edge to fix
        # the `start_column`.
        if !pagerd.show_ruler
            ruler_spacing = _ruler_width(pagerd.num_lines)

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

            # If the line is already selected, we will deselect it. Notice that a line can only
            # be in the list once, so `findfirst` is enough and does not allocate.
            id = findfirst(==(visual_str_id), pagerd.visual_mode_selected_lines)

            if isnothing(id)
                push!(pagerd.visual_mode_selected_lines, visual_str_id)
            else
                deleteat!(pagerd.visual_mode_selected_lines, id)
            end

            # Without this, marking a line produced no feedback until the user happened to
            # press another key.
            _request_redraw!(pagerd)
        end

    elseif event == :yank
        if pagerd.visual_mode
            yanked_lines = vcat(
                pagerd.visual_mode_line + pagerd.start_row - 1,
                pagerd.visual_mode_selected_lines,
            )

            yanked_text, num_yanked_lines = _assemble_yank_text(
                pagerd.text_layout, yanked_lines
            )
            clipboard(yanked_text)

            _print_cmd_message!(
                pagerd,
                num_yanked_lines > 1 ? "$(num_yanked_lines) lines copied" : "1 line copied",
            )
        end
    end

    return true
end

"""
    _assemble_yank_text(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer}
    ) -> Tuple{String, Int}

Assemble sorted, deduplicated, undecorated lines with a trailing newline and return the
text and selected-line count.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Canonical line sequence.
- `line_ids::AbstractVector{<:Integer}`: One-based line indices to sort and deduplicate.
"""
function _assemble_yank_text(lines::AbstractVector{<:AbstractString}, line_ids)
    ids = sort!(unique!(collect(Int, line_ids)))
    sizehint = sum(id -> sizeof(lines[id]) + 1, ids; init = 0)
    buf = IOBuffer(; sizehint = sizehint)

    for id in ids
        write(buf, remove_decorations(lines[id]), '\n')
    end

    return String(take!(buf)), length(ids)
end

"""
    _invalidate_frame!(pagerd::Pager) -> Nothing

Discard the frame snapshot, forcing the next redraw to repaint every row.

This must be called whenever something other than [`_redraw!`](@ref) writes to the rows above
the command line.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _invalidate_frame!(pagerd::Pager)
    pagerd.frame_cache.valid = false
    return nothing
end

"""
    _frame_bytes(io::IOBuffer) -> Tuple{Any, Int}

Return the storage backing the bytes written to `io` and how many of them are valid.

The storage is a `Vector{UInt8}` up to Julia 1.11 and a `Memory{UInt8}` afterwards. In both
cases, `pointer(storage, i)` is valid, which is all the redraw path needs. Notice that we
must not use `take!` here, because it hands over the storage and forces `io` to allocate a
new one for the next frame.

# Arguments

- `io::IOBuffer`: Buffer holding a rendered frame.
"""
_frame_bytes(io::IOBuffer) = (io.data, io.size)

"""
    _screen_buffer!(pagerd::Pager) -> IOBuffer

Return the reusable buffer that assembles everything sent to the terminal, after resetting it.

# Arguments

- `pagerd::Pager`: Pager state whose buffer is returned.
"""
function _screen_buffer!(pagerd::Pager)
    out = pagerd.frame_cache.out
    truncate(out, 0)
    seekstart(out)
    return out
end

"""
    _flush_screen!(pagerd::Pager) -> Nothing

Send everything assembled in the reusable screen buffer to the terminal in a single write.

Writing each piece separately would issue one system call per piece, which can show tearing.

# Arguments

- `pagerd::Pager`: Pager state to flush.
"""
function _flush_screen!(pagerd::Pager)
    data, num_bytes = _frame_bytes(pagerd.frame_cache.out)
    num_bytes > 0 && _write_all(pagerd.term.out_stream, data, num_bytes)
    return nothing
end

"""
    _write_all(io::IO, data, num_bytes::Int) -> Nothing

Write the first `num_bytes` bytes of `data` to `io`.

Notice that this function returns `nothing`. `TTYTerminal` declares its streams as `IO`, so a
`write` to them is a dynamic dispatch whose `Int` return value would have to be boxed.

# Arguments

- `io::IO`: Output stream to update.
- `data`: Byte storage to write from.
- `num_bytes::Int`: Number of bytes to write.
"""
function _write_all(io::IO, data, num_bytes::Int)
    GC.@preserve data unsafe_write(io, pointer(data, 1), UInt(num_bytes))
    return nothing
end

"""
    _bytes_equal(a, ai::Int, b, bi::Int, n::Int) -> Bool

Return whether the `n` bytes of `a` starting at `ai` equal those of `b` starting at `bi`.

# Arguments

- `a`: First byte storage.
- `ai::Int`: One-based first index in `a`.
- `b`: Second byte storage.
- `bi::Int`: One-based first index in `b`.
- `n::Int`: Number of bytes to compare.
"""
function _bytes_equal(a, ai::Int, b, bi::Int, n::Int)
    n <= 0 && return true

    return GC.@preserve a b (
        ccall(
            :memcmp,
            Cint,
            (Ptr{UInt8}, Ptr{UInt8}, Csize_t),
            pointer(a, ai),
            pointer(b, bi),
            n,
        ) == 0
    )
end

"""
    _scan_frame_rows!(frame_cache::FrameCache, data, num_bytes::Int, max_rows::Int) -> Int

Fill the scratch row table of `frame_cache` from the newline positions in `data`.

Return the number of rows found, which is at most `max_rows`.

# Arguments

- `frame_cache::FrameCache`: Cache whose scratch row table is filled.
- `data`: Byte storage holding the rendered frame.
- `num_bytes::Int`: Number of valid bytes in `data`.
- `max_rows::Int`: Maximum number of rows the screen can show.
"""
function _scan_frame_rows!(frame_cache::FrameCache, data, num_bytes::Int, max_rows::Int)
    new_first = frame_cache.new_first
    new_last = frame_cache.new_last

    empty!(new_first)
    empty!(new_last)

    num_rows = 0
    row_first = 1

    @inbounds for i in 1:num_bytes
        data[i] == UInt8('\n') || continue

        num_rows += 1
        push!(new_first, row_first)
        push!(new_last, i - 1)
        row_first = i + 1

        num_rows >= max_rows && return num_rows
    end

    # The last row is not terminated by a newline.
    if row_first <= num_bytes + 1
        num_rows += 1
        push!(new_first, row_first)
        push!(new_last, num_bytes)
    end

    return min(num_rows, max_rows)
end

"""
    _redraw!(pagerd::Pager) -> Nothing

Write the rows of the prepared view buffer that changed to the terminal.

# Arguments

- `pagerd::Pager`: Pager state to redraw.
"""
function _redraw!(pagerd::Pager)
    frame_cache = pagerd.frame_cache
    term = pagerd.term
    max_rows = _get_pager_display_size(pagerd)[1]

    data, num_bytes = _frame_bytes(pagerd.buf.io)
    num_rows = _scan_frame_rows!(frame_cache, data, num_bytes, max_rows)

    new_first = frame_cache.new_first
    new_last = frame_cache.new_last
    snapshot = frame_cache.bytes
    row_first = frame_cache.row_first
    row_last = frame_cache.row_last
    valid = frame_cache.valid

    # If the whole frame is unchanged, we do not need to touch the terminal at all.
    if valid &&
        (num_rows == frame_cache.num_rows) &&
        (num_bytes == length(snapshot)) &&
        _bytes_equal(snapshot, 1, data, 1, num_bytes)
        pagerd.redraw = false
        return nothing
    end

    out = _screen_buffer!(pagerd)

    # We must not use the ANSI escape sequence `\e[2J` to clear the screen because it adds new
    # lines to it. Hence, every row we paint is cleared to the end of the line.
    previous_row = -1

    @inbounds for i in 1:num_rows
        row_size = new_last[i] - new_first[i] + 1

        if valid &&
            (i <= frame_cache.num_rows) &&
            (row_last[i] - row_first[i] + 1 == row_size) &&
            _bytes_equal(snapshot, row_first[i], data, new_first[i], row_size)
            continue
        end

        if i == previous_row + 1
            # A carriage return also cancels the pending-wrap state left by a row that filled
            # the display width.
            write(out, "\r\n")
        else
            _move_cursor(out, i, 1)

            # `textview` always leaves the SGR state at its default, but we reset it anyway.
            # Otherwise, a row painted out of order could erase to the end of the line with a
            # colored background.
            write(out, _CRAYON_RESET)
        end

        _clear_to_eol(out)
        row_size > 0 && GC.@preserve data unsafe_write(
            out, pointer(data, new_first[i]), UInt(row_size)
        )

        previous_row = i
    end

    # Clear the rows that were painted before but are not part of this frame. If the snapshot
    # is not valid, we do not know what is on screen, so we must clear everything.
    last_stale = valid ? min(frame_cache.num_rows, max_rows) : max_rows

    for i in (num_rows + 1):last_stale
        _move_cursor(out, i, 1)
        write(out, _CRAYON_RESET)
        _clear_to_eol(out)
    end

    # The snapshot will not describe the screen until the frame is flushed and stored. Hence,
    # a failure in between forces a full repaint instead of leaving a stale snapshot.
    frame_cache.valid = false

    cursor_hidden = false
    try
        # Hide the cursor while drawing the frame. Notice that the flag is set before the
        # write, because a failing write can still have reached the terminal. Hence, we must
        # show the cursor again in that case.
        cursor_hidden = true
        _hide_cursor(term.out_stream)

        _flush_screen!(pagerd)
    finally
        cursor_hidden && _show_cursor(term.out_stream)
    end

    _store_frame!(frame_cache, data, num_bytes, num_rows)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end

"""
    _store_frame!(frame_cache::FrameCache, data, num_bytes::Int, num_rows::Int) -> Nothing

Record the frame in `data` as what is currently on screen.

# Arguments

- `frame_cache::FrameCache`: Cache to update.
- `data`: Byte storage holding the rendered frame.
- `num_bytes::Int`: Number of valid bytes in `data`.
- `num_rows::Int`: Number of rows that were painted.
"""
function _store_frame!(frame_cache::FrameCache, data, num_bytes::Int, num_rows::Int)
    snapshot = frame_cache.bytes
    resize!(snapshot, num_bytes)
    num_bytes > 0 && copyto!(snapshot, 1, data, 1, num_bytes)

    resize!(frame_cache.row_first, num_rows)
    resize!(frame_cache.row_last, num_rows)
    copyto!(frame_cache.row_first, 1, frame_cache.new_first, 1, num_rows)
    copyto!(frame_cache.row_last, 1, frame_cache.new_last, 1, num_rows)

    frame_cache.num_rows = num_rows
    frame_cache.valid = true

    return nothing
end
