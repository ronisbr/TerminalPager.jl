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

Return the available pager rows and columns after reserving the status bar row and the
scrollbar column, if it is shown.

# Arguments

- `p::Pager`: Pager state whose display size is queried.
"""
function _get_pager_display_size(p::Pager)
    rows, cols = p.display_size

    # We need to remove one row due to the status bar, two rows due to the column ruler, and
    # one column due to the scrollbar. Notice that a degenerate terminal must not produce
    # negative sizes.
    rows = max(rows - 1 - _column_ruler_rows(p), 0)
    p.show_scrollbar && (cols = max(cols - 1, 0))

    return rows, cols
end

"""
    _ruler_width(num_lines::Int) -> Int
    _ruler_width(p::Pager) -> Int

Return the number of columns the line-number ruler occupies for `num_lines` lines, or for the
text of `p`.

# Arguments

- `num_lines::Int`: Number of lines in the pager text.
- `p::Pager`: Pager state whose ruler is measured.
"""
function _ruler_width(num_lines::Int)
    # This must match how `_textview` sizes the ruler. Notice that `ndigits` is defined for
    # 0, whereas `floor(Int, log10(num_lines))` throws an `InexactError` for an empty text.
    return ndigits(num_lines) + 3
end

_ruler_width(p::Pager) = _ruler_width(p.num_lines)

"""
    _request_redraw!(p::Pager) -> Bool

Mark `p` for redraw and return the assigned value, `true`.

# Arguments

- `p::Pager`: Pager state to mark for redraw.
"""
_request_redraw!(p::Pager) = (p.redraw = true)

"""
    _set_message!(p::Pager, message::String; kind::Symbol = :info) -> Nothing

Show `message` on the command line of `p` until the next keystroke and request a redraw.

Unlike a modal message, the next keystroke is processed normally instead of being consumed
to dismiss the message.

# Arguments

- `p::Pager`: Pager state to update.
- `message::String`: Message to show.

# Keywords

- `kind::Symbol`: Kind of the message, `:info` or `:error`, which selects its decoration.
    (**Default**: `:info`)
"""
function _set_message!(p::Pager, message::String; kind::Symbol = :info)
    p.message = message
    p.message_kind = kind
    _request_redraw!(p)
    return nothing
end

"""
    _clear_message!(p::Pager) -> Nothing

Remove the command line message of `p`, if any, and request a redraw in that case.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _clear_message!(p::Pager)
    isempty(p.message) && return nothing
    p.message = ""
    p.message_kind = :info
    _request_redraw!(p)
    return nothing
end

"""
    _first_scrollable_row(p::Pager) -> Int

Return the first row of the text of `p` that scrolls, which is the one after the frozen
rows.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_first_scrollable_row(p::Pager) = max(1, p.frozen_rows + 1)

"""
    _view_rows(p::Pager) -> Int

Return the number of rows of the display of `p` that show scrolling text, that is, without
the status line, the column ruler, and the frozen rows.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_view_rows(p::Pager) = p.display_size[1] - 1 - _column_ruler_rows(p) - p.frozen_rows

"""
    _column_ruler_rows(p::Pager) -> Int

Return the number of rows of the display of `p` taken by the column ruler, which is `2` when
it is shown and `0` otherwise.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_column_ruler_rows(p::Pager) = p.show_column_ruler ? 2 : 0

"""
    _selecting_on_screen(p::Pager) -> Bool

Return whether `p` is in one of the on-screen selection modes, which draw the guides over the
view.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
function _selecting_on_screen(p::Pager)
    return (p.mode == :freeze_selection) || (p.mode == :title_selection)
end

"""
    _frame_rows(p::Pager) -> Int

Return the number of screen rows of the frame of `p`, which are the rows of the view plus the
column ruler.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
_frame_rows(p::Pager) = _get_pager_display_size(p)[1] + _column_ruler_rows(p)

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
        _clamp_viewport!(p)

        # The terminal dropped or revealed rows, so we no longer know what is on screen.
        _invalidate_frame!(p)
        _request_redraw!(p)
    end

    return nothing
end

"""
    _clamp_viewport!(p::Pager) -> Nothing

Keep the viewport of `p` inside the text after the display size changed.

A view that ends past the last line or past the last column is pulled back so that the
screen stays full, like `less` does. The first visible row and column never move into the
frozen region.

# Arguments

- `p::Pager`: Pager state to update.
"""
function _clamp_viewport!(p::Pager)
    rows, cols = _get_pager_display_size(p)
    ((rows <= 0) || (cols <= 0)) && return nothing

    min_row = _first_scrollable_row(p)
    view_rows = _view_rows(p)
    max_row = max(min_row, p.num_lines - view_rows + 1)
    p.start_row = clamp(p.start_row, min_row, max_row)

    min_col = max(1, p.frozen_columns + 1)
    ruler_width = p.show_ruler ? _ruler_width(p) : 0
    view_cols = cols - p.frozen_columns - ruler_width
    max_col = max(min_col, _text_width(p) - view_cols + 1)
    p.start_column = clamp(p.start_column, min_col, max_col)

    return nothing
end

"""
    _text_width(p::Pager) -> Int

Return the printable width of the widest line of `p`, computing and caching it on the first
call.

# Arguments

- `p::Pager`: Pager state to inspect.
"""
function _text_width(p::Pager)
    if p.text_width < 0
        # The layout measured every line while it was prepared.
        p.text_width = maximum(p.text_layout.printable_widths; init = 0)
    end

    return p.text_width
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
- `return_selection::Bool`: Return the [`PagerResult`](@ref) of the session instead of
    `nothing`.
    (**Default**: `false`)
- `_display_config_loader::Any`: Callable object that creates the session
    display configuration.
    (**Default**: `_display_config`)
- `_input_factory::Any`: Callable object that creates input state for a stream.
    (**Default**: `PagerInput`)
- `_layout_factory::Any`: Callable object that creates a prepared text
    layout.
    (**Default**: `ViewLayout`)
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
    return_selection::Bool = false,
    _display_config_loader = _display_config,
    _input_factory = PagerInput,
    _layout_factory = ViewLayout,
    _terminal_factory = () -> REPL.Terminals.TTYTerminal("", stdin, stdout, stderr),
    _raw_runner = _with_raw_mode,
    kwargs...,
)
    # `split` yields `SubString`s, and both `_pager_content_fits` and `ViewLayout` accept
    # them. Copying every line into a `String` here duplicated the whole text before the first
    # frame was shown.
    lines = split(str, '\n')
    display_size = displaysize(stdout)::Tuple{Int, Int}
    if auto && _pager_content_fits(lines, display_size)
        print(str)
        return return_selection ? PagerResult(String[], 1, 1, "") : nothing
    end

    text_layout = _layout_factory(lines)
    display_config = _display_config_loader()
    input = _input_factory(stdin)

    # Initialize the terminal.
    term = _terminal_factory()

    # Switch the terminal to raw mode so that every keystroke is passed immediately instead
    # of waiting for <return>.
    result = _raw_runner(term) do
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

    return return_selection ? result : nothing
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
    try
        raw_function(term, true)
        return f()
    finally
        # The terminal is restored even if enabling the raw mode threw, because a call that
        # throws can still have changed it, and leaving it in raw mode would break the
        # user's session. Restoring a terminal that was never changed is harmless.
        raw_function(term, false)
    end
end

"""
    _pager!(term::REPL.Terminals.TTYTerminal, str::String; kwargs...) -> PagerResult

Run the interactive pager for `str` using a terminal that is already in raw mode, and return
what the session left: the last yanked lines, the viewport, and the search pattern. The
result of a text printed by the automatic mode is empty.

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
- `has_help::Bool`: Enable pager help.
    (**Default**: `true`)
- `has_visual_mode::Bool`: Enable visual selection mode.
    (**Default**: `true`)
- `show_ruler::Bool`: Show the line-number ruler initially.
    (**Default**: `false`)
- `show_column_ruler::Bool`: Show the column ruler initially.
    (**Default**: the value of the preference `"show_column_ruler"`)
- `show_scrollbar::Bool`: Show the scrollbar initially.
    (**Default**: the value of the preference `"show_scrollbar"`)
- `use_alternate_screen_buffer::Bool`: Request the terminal's alternate screen
    buffer.
    (**Default**: `true`)
- `input::Union{Nothing, PagerInput}`: Input state associated with the terminal
    input stream, or `nothing` to create one.
    (**Default**: `nothing`)
- `text_layout::Union{Nothing, ViewLayout}`: Prepared layout used directly
    when supplied, or `nothing` to construct one.
    (**Default**: `nothing`)
- `_layout_factory::Any`: Callable object that creates a layout from raw
    lines.
    (**Default**: `ViewLayout`)
- `manage_cursor_key_mode::Bool`: Enable and restore terminal cursor-key mode.
    (**Default**: `true`)
- `manage_cursor::Bool`: Hide the cursor during the session, and show it and clear the
    status bar row when the session ends. A nested session must not do this.
    (**Default**: `true`)
- `manage_mouse::Bool`: Enable the mouse reporting during the session if the preference
    `"mouse"` is enabled, and disable it when the session ends. A nested session must not
    do this.
    (**Default**: `true`)
- `_waiter_factory::Any`: Callable object that receives the terminal and returns the
    [`InputWaiter`](@ref) of the session, which repaints the screen when the display size
    changes, or `nothing` to read the input directly. It is called only when the input has
    no waiter, and the session closes the waiter it created. A nested session shares the
    waiter of its parent.
    (**Default**: `_default_input_waiter`)
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
    has_help::Bool = true,
    has_visual_mode::Bool = true,
    show_ruler::Bool = false,
    show_column_ruler::Bool = _get_preference("show_column_ruler")::Bool,
    show_scrollbar::Bool = _get_preference("show_scrollbar")::Bool,
    use_alternate_screen_buffer::Bool = true,
    input::Union{Nothing, PagerInput} = nothing,
    text_layout::Union{Nothing, ViewLayout} = nothing,
    _layout_factory = ViewLayout,
    manage_cursor_key_mode::Bool = true,
    manage_cursor::Bool = true,
    manage_mouse::Bool = true,
    _waiter_factory = _default_input_waiter,
)
    # The raw text is split only when no layout is supplied, and the result feeds both the
    # auto-fit check and the layout construction.
    source_lines = isnothing(text_layout) ? split(str, '\n') : text_layout

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    if auto && _pager_content_fits(source_lines, dsize)
        print(str)
        return PagerResult(String[], 1, 1, "")
    end

    # Like the prompts that change them, the numbers of frozen and title rows and columns
    # cannot be negative. Otherwise, the view has more rows than the display, and a page
    # movement skips lines.
    frozen_rows = max(frozen_rows, 0)
    frozen_columns = max(frozen_columns, 0)
    title_rows = max(title_rows, 0)

    session_layout = isnothing(text_layout) ? _layout_factory(source_lines) : text_layout
    num_tokens = length(session_layout)
    session_config = isnothing(display_config) ? _display_config() : display_config
    session_input = isnothing(input) ? PagerInput(term.in_stream) : input
    session_input.stream === term.in_stream ||
        throw(ArgumentError("PagerInput must own the pager terminal input stream."))

    # Check if we should block the alternate screen buffer.
    block_alternate_screen_buffer = _get_preference("block_alternate_screen_buffer")::Bool
    use_alternate_screen_buffer &= !block_alternate_screen_buffer

    modes = TerminalModes()
    owns_waiter = false
    local pagerd
    try
        _enter_terminal_modes!(
            modes,
            term.out_stream;
            cursor_key_mode = manage_cursor_key_mode,
            alternate_screen = use_alternate_screen_buffer,
            hide_cursor = manage_cursor,
            mouse = manage_mouse && _get_preference("mouse")::Bool,
        )

        # The pager is divided into a view and a command line. Everything in the view is
        # written to this buffer and then flushed to the screen.
        # The color flag must come from the session terminal, not from the global `stdout`,
        # so that a terminal built for another stream honors its own color support.
        iobuf = IOBuffer()
        hascolor = get(term.out_stream, :color, true)::Bool
        buf = IOContext(iobuf, :color => hascolor)

        features = Symbol[]
        change_freeze && push!(features, :change_freeze)
        has_help && push!(features, :help)
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
            show_column_ruler = show_column_ruler,
            show_scrollbar = show_scrollbar,
            status_position = Symbol(_get_preference("status_position")::String),
            scroll_regions = _get_preference("use_scroll_regions")::Bool,
            start_column = max(1, frozen_columns + 1),
            start_row = min(max(1, frozen_rows + 1), num_tokens),
            term = term,
            terminal_modes = modes,
            text_layout = session_layout,
            title_rows = title_rows,
        )

        # The waiter lets a change of the display size interrupt the wait for the input, so
        # that the screen is repainted without a keystroke. A nested session, such as the
        # help, shares the waiter of its parent through the input.
        if isnothing(session_input.waiter)
            waiter = _waiter_factory(term)

            if !isnothing(waiter)
                owns_waiter = true
                session_input.waiter = waiter
            end
        end

        # == Application Main Loop =========================================================

        while true
            # Check if the display size was changed.
            _update_display_size!(pagerd)

            # Check if we need to redraw the screen.
            if pagerd.redraw
                _view!(pagerd)
                _redraw!(pagerd)
                _redraw_status_bar!(pagerd)
            end

            # Wait for user input. A change of the display size interrupts the wait, and the
            # screen is repainted at the top of the loop.
            _wait_for_input!(pagerd) || continue

            # A message on the command line is shown until this keystroke, which is then
            # processed normally.
            k = _read_keystroke!(pagerd.input)
            _clear_message!(pagerd)
            action = _pager_key_process!(pagerd, k)
            _coalesce_navigation!(pagerd, action)
            _pager_event_process!(pagerd) || break
        end
    finally
        try
            _leave_terminal_modes!(modes, term.out_stream)
        finally
            # The waiter is closed even if the restoration throws, so that its timer and its
            # reader task do not outlive the session.
            owns_waiter && _close_input_waiter!(session_input)
        end
    end

    return PagerResult(
        pagerd.yanked, pagerd.start_row, pagerd.start_column, pagerd.search_pattern
    )
end

"""
    _enter_terminal_modes!(modes::TerminalModes, io::IO; kwargs...) -> Nothing

Enable the requested terminal modes on `io` and record them in `modes`. Each flag of `modes`
is set before the sequence is written, so that a write that partially reached the terminal
is still undone by [`_leave_terminal_modes!`](@ref). Without the alternate screen buffer,
the screen is cleared instead.

# Arguments

- `modes::TerminalModes`: Record of the enabled modes.
- `io::IO`: Terminal output stream to update.

# Keywords

- `cursor_key_mode::Bool`: Enable the application cursor key mode.
- `alternate_screen::Bool`: Enter the alternate screen buffer.
- `hide_cursor::Bool`: Hide the cursor.
- `mouse::Bool`: Enable the mouse reporting.
"""
function _enter_terminal_modes!(
    modes::TerminalModes,
    @nospecialize(io::IO);
    cursor_key_mode::Bool,
    alternate_screen::Bool,
    hide_cursor::Bool,
    mouse::Bool,
)
    if cursor_key_mode
        modes.cursor_key_mode = true
        _turn_on_cursor_key_mode(io)
    end

    # Clear the screen and position the cursor at the top.
    if alternate_screen
        modes.alternate_screen = true
        _turn_on_alternate_screen_buffer(io)
    else
        _clear_screen(io)
    end

    # The cursor has nothing to point at in the view. Hence, it is hidden for the whole
    # session and shown only while a command is edited.
    if hide_cursor
        modes.cursor_hidden = true
        _hide_cursor(io)
    end

    # The mouse reporting lets the wheel scroll the text. It is a terminal state that
    # outlives the session if it is not disabled at the end.
    if mouse
        modes.mouse = true
        _turn_on_mouse(io)
    end

    return nothing
end

"""
    _leave_terminal_modes!(modes::TerminalModes, io::IO) -> Nothing

Undo the terminal modes recorded in `modes` on `io`, performing every step even if a
previous one throws. The flags of `modes` are kept, so that the modes can be entered again.

# Arguments

- `modes::TerminalModes`: Record of the enabled modes.
- `io::IO`: Terminal output stream to restore.
"""
function _leave_terminal_modes!(modes::TerminalModes, @nospecialize(io::IO))
    _restore_terminal(
        io;
        mouse = modes.mouse,
        clear_status_row = modes.cursor_hidden && !modes.alternate_screen,
        show_cursor = modes.cursor_hidden,
        alternate_screen = modes.alternate_screen,
        cursor_key_mode = modes.cursor_key_mode,
    )

    return nothing
end

"""
    _set_raw_mode!(term::REPL.Terminals.TTYTerminal, raw::Bool) -> Nothing

Enable or disable the raw mode of `term` if its input is a TTY. The terminals of the tests
read from buffers, which have no raw mode.

# Arguments

- `term::REPL.Terminals.TTYTerminal`: Terminal to update.
- `raw::Bool`: Whether to enable the raw mode.
"""
function _set_raw_mode!(@nospecialize(term::REPL.Terminals.TTYTerminal), raw::Bool)
    (term.in_stream isa Base.TTY) && REPL.Terminals.raw!(term, raw)
    return nothing
end

"""
    _restore_terminal(io::IO; kwargs...) -> Nothing

Undo the changes a pager session made to the terminal `io`, performing every requested step
even if a previous one throws. The first error is thrown again after the last step.

# Arguments

- `io::IO`: Terminal output stream to restore.

# Keywords

- `mouse::Bool`: Disable the mouse reporting.
- `clear_status_row::Bool`: Clear the last row of the display, where the status bar was.
- `show_cursor::Bool`: Show the cursor.
- `alternate_screen::Bool`: Leave the alternate screen buffer.
- `cursor_key_mode::Bool`: Disable the cursor key mode.
"""
function _restore_terminal(
    @nospecialize(io::IO);
    mouse::Bool,
    clear_status_row::Bool,
    show_cursor::Bool,
    alternate_screen::Bool,
    cursor_key_mode::Bool,
)
    first_error = nothing

    mouse && (first_error = _restore_step(_turn_off_mouse, io, first_error))
    clear_status_row && (first_error = _restore_step(_clear_status_row, io, first_error))
    show_cursor && (first_error = _restore_step(_show_cursor, io, first_error))
    alternate_screen &&
        (first_error = _restore_step(_turn_off_alternate_screen_buffer, io, first_error))
    cursor_key_mode &&
        (first_error = _restore_step(_turn_off_cursor_key_mode, io, first_error))

    isnothing(first_error) || throw(first_error)

    return nothing
end

"""
    _restore_step(
        f::F,
        io::IO,
        first_error::Union{Nothing, Exception}
    ) -> Union{Nothing, Exception} where {F}

Call `f(io)`, one step of the terminal restoration, and return the first error of the
restoration so far: `first_error` if it is not `nothing`, otherwise the error thrown by
`f`, if any.

# Arguments

- `f::F`: Step to perform.
- `io::IO`: Terminal output stream to restore.
- `first_error::Union{Nothing, Exception}`: First error of the previous steps.
"""
function _restore_step(f::F, @nospecialize(io::IO), first_error) where {F}
    try
        f(io)
    catch err
        isnothing(first_error) && return err
    end

    return first_error
end

"""
    _clear_status_row(io::IO) -> Nothing

Clear the last row of the display of `io`, where the status bar was.

Without the alternate screen buffer, the status bar would be left right above the next
prompt. Clearing it ends the scrollback with the last page of the text instead.

# Arguments

- `io::IO`: Terminal output stream to update.
"""
function _clear_status_row(@nospecialize(io::IO))
    _move_cursor(io, displaysize(io)[1], 1)
    write(io, _SGR_RESET)
    _clear_to_eol(io)
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
    display_size[1] - 2 >= _content_fit_rows(lines) || return false
    return all(line -> printable_textwidth(line) <= display_size[2], lines)
end

function _pager_content_fits(layout::ViewLayout, display_size::Tuple{Int, Int})
    display_size[1] - 2 >= _content_fit_rows(layout) || return false

    # The layout already measured every line while it was prepared, so there is no need to
    # scan the text again.
    return all(width -> width <= display_size[2], layout.printable_widths)
end

"""
    _content_fit_rows(lines::AbstractVector{<:AbstractString}) -> Int

Return the number of terminal rows required to print `lines`.

Text ending in a newline yields one trailing empty line after splitting, which does not
occupy a terminal row when printed. Counting it opened the pager one row too early in
automatic mode.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Lines to measure.
"""
function _content_fit_rows(lines::AbstractVector{<:AbstractString})
    num_lines = length(lines)
    (num_lines > 0) && isempty(lines[num_lines]) && return num_lines - 1
    return num_lines
end

"""
    _pager_key_process!(pagerd::Pager, k::Keystroke) -> Union{Nothing, Symbol}

Process `k`, update the viewport, the visual cursor, and the pending event of `pagerd`, and
return the resolved action.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `k::Keystroke`: Keystroke to process.
"""
function _pager_key_process!(pagerd::Pager, k::Keystroke)
    display_size = pagerd.display_size
    frozen_rows = pagerd.frozen_rows
    num_lines = pagerd.num_lines

    action = _resolve_action(pagerd, k)

    # The position of a mouse event is kept for the events that need it.
    if (k.x > 0) && (k.y > 0)
        pagerd.mouse_column = k.x
        pagerd.mouse_row = k.y
    end

    # Compute the minimum value for the start row.
    min_row = _first_scrollable_row(pagerd)

    # A page has the size of the view, which excludes the command line and the frozen rows.
    # Using the full display height here skipped `frozen_rows` lines at every page movement,
    # and those lines were never shown. Both values are clamped so that paging always moves
    # at least one line.
    view_rows = _view_rows(pagerd)
    page_rows = max(view_rows, 1)
    half_page_rows = max(div(view_rows, 2), 1)

    # We should disable the visual line mode if there is no selectable line, that is, if all
    # lines are frozen or if the first content row is beyond the view. Notice that the view
    # has `display_size[1] - 1` rows without the column ruler, because the last one is the
    # command line, and that at `min_row == num_lines` exactly one selectable line remains.
    max_view_row = display_size[1] - 1 - _column_ruler_rows(pagerd)
    if pagerd.visual_mode && ((min_row > num_lines) || (min_row > max_view_row))
        pagerd.visual_mode = false
        pagerd.visual_mode_line = 1

        # The selections must not survive the forced disable. Otherwise, they reappear the
        # next time the visual mode is enabled.
        empty!(pagerd.visual_mode_selected_lines)
        pagerd.visual_anchor = 0
    end

    axis, step, policy = _movement(action, page_rows, half_page_rows)

    if axis === :vertical
        _scroll_vertical!(pagerd, step, policy)
    elseif axis === :horizontal
        _scroll_horizontal!(pagerd, step)
    end

    pagerd.event = _action_event(action, pagerd.features)

    # The visual line is relative to the viewport, so it must always agree with `start_row`
    # and with the number of rows the view has. Clamping it inside each movement left the
    # cursor past the last line whenever the state was changed elsewhere, for example by
    # `:change_freeze`, and the yank then indexed the layout out of bounds.
    _clamp_visual_line!(pagerd)

    return action
end

"""
    _clamp_visual_line!(pagerd::Pager) -> Nothing

Keep the visual line of `pagerd` inside the view and inside the text. Nothing happens
outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _clamp_visual_line!(pagerd::Pager)
    pagerd.visual_mode || return nothing

    max_visual_line = min(_view_rows(pagerd), pagerd.num_lines - pagerd.start_row + 1)
    pagerd.visual_mode_line = clamp(pagerd.visual_mode_line, 1, max(1, max_visual_line))

    return nothing
end

# Number of lines scrolled by one movement of the mouse wheel.
const _WHEEL_LINES = 3

"""
    _movement(action::Union{Nothing, Symbol}, page_rows::Int, half_page_rows::Int) ->
        Tuple{Symbol, Int, Symbol}

Return the axis, the signed step, and the visual cursor policy of the movement `action`.

The axis is `:vertical`, `:horizontal`, or `:none` when `action` is not a movement. A step of
`typemax(Int)` or `-typemax(Int)` moves as far as possible. The policy is `:follow` when the
visual cursor moves by the step and the view scrolls only by the part of the step that
crosses its edge, `:pin` when the view scrolls by the step and the cursor is pinned to the
edge in the direction of the movement, or `:keep` when the view scrolls by the step and the
cursor keeps its row. Notice that `:follow` steps are always finite.

# Arguments

- `action::Union{Nothing, Symbol}`: Resolved pager action.
- `page_rows::Int`: Number of lines of a page.
- `half_page_rows::Int`: Number of lines of half a page.
"""
function _movement(action, page_rows::Int, half_page_rows::Int)
    action === :down && return :vertical, 1, :follow
    action === :fastdown && return :vertical, 5, :follow
    action === :halfpagedown && return :vertical, half_page_rows, :follow
    action === :pagedown && return :vertical, page_rows, :pin
    action === :end && return :vertical, typemax(Int), :pin
    action === :up && return :vertical, -1, :follow
    action === :fastup && return :vertical, -5, :follow
    action === :halfpageup && return :vertical, -half_page_rows, :follow
    action === :pageup && return :vertical, -page_rows, :pin
    action === :home && return :vertical, -typemax(Int), :pin
    action === :wheel_down && return :vertical, _WHEEL_LINES, :keep
    action === :wheel_up && return :vertical, -_WHEEL_LINES, :keep
    action === :right && return :horizontal, 1, :pin
    action === :fastright && return :horizontal, 10, :pin
    action === :eol && return :horizontal, typemax(Int), :pin
    action === :left && return :horizontal, -1, :pin
    action === :fastleft && return :horizontal, -10, :pin
    action === :bol && return :horizontal, -typemax(Int), :pin
    return :none, 0, :pin
end

"""
    _scroll_vertical!(pagerd::Pager, step::Int, policy::Symbol) -> Nothing

Scroll the view of `pagerd` by `step` lines, positive downwards, and request a redraw if the
viewport or the visual cursor changed.

The view never scrolls past the last cropped line nor above the first non-frozen line, and
the number of cropped lines follows the viewport, so that the next movement of a burst sees
the boundary without a redraw. In visual mode, `policy` selects how the cursor moves, as
described in [`_movement`](@ref).

# Arguments

- `pagerd::Pager`: Pager state to update.
- `step::Int`: Signed number of lines to move.
- `policy::Symbol`: Visual cursor policy, `:follow`, `:pin`, or `:keep`.
"""
function _scroll_vertical!(pagerd::Pager, step::Int, policy::Symbol)
    min_row = _first_scrollable_row(pagerd)
    view_rows = _view_rows(pagerd)
    cropped_lines = pagerd.cropped_lines
    start_row = pagerd.start_row
    visual_mode_line = pagerd.visual_mode_line

    if pagerd.visual_mode && (policy === :follow)
        visual_mode_line += step

        if visual_mode_line > view_rows
            start_row += min(visual_mode_line - view_rows, cropped_lines)
            visual_mode_line = view_rows
        elseif visual_mode_line < 1
            start_row = max(start_row - (1 - visual_mode_line), min_row)
            visual_mode_line = 1
        end
    else
        if step > 0
            start_row += min(step, cropped_lines)
        else
            start_row = max(start_row + step, min_row)
        end

        if pagerd.visual_mode && (policy === :pin)
            visual_mode_line = step > 0 ? view_rows : 1
        end
    end

    if (start_row != pagerd.start_row) || (visual_mode_line != pagerd.visual_mode_line)
        pagerd.cropped_lines = max(0, cropped_lines - (start_row - pagerd.start_row))
        pagerd.start_row = start_row
        pagerd.visual_mode_line = visual_mode_line
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _scroll_horizontal!(pagerd::Pager, step::Int) -> Nothing

Scroll the view of `pagerd` by `step` columns, positive rightwards, and request a redraw if
the viewport changed.

The view never scrolls past the last cropped column nor before the first non-frozen column,
and the number of cropped columns follows the viewport, so that the next movement of a
burst sees the boundary without a redraw.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `step::Int`: Signed number of columns to move.
"""
function _scroll_horizontal!(pagerd::Pager, step::Int)
    min_col = max(1, pagerd.frozen_columns + 1)
    start_column = pagerd.start_column

    if step > 0
        start_column += min(step, pagerd.cropped_columns)
    else
        start_column = max(start_column + step, min_col)
    end

    if start_column != pagerd.start_column
        pagerd.cropped_columns =
            max(0, pagerd.cropped_columns - (start_column - pagerd.start_column))
        pagerd.start_column = start_column
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _action_event(action::Union{Nothing, Symbol}, features::Vector{Symbol}) ->
        Union{Nothing, Symbol}

Return the event raised by `action`, or `nothing` if it raises none or requires a feature
that is not in `features`.

# Arguments

- `action::Union{Nothing, Symbol}`: Resolved pager action.
- `features::Vector{Symbol}`: Features enabled for the session.
"""
function _action_event(action, features::Vector{Symbol})
    isnothing(action) && return nothing
    feature = get(_EVENT_FEATURES, action, missing)
    feature === missing && return nothing
    return (isnothing(feature) || (feature in features)) ? action : nothing
end

# Feature required by every action that raises an event, or `nothing` if the action always
# raises it. The movements are not here because they do not raise events.
const _EVENT_FEATURES = Dict{Symbol, Union{Nothing, Symbol}}(
    :quit => nothing,
    :quit_eot => nothing,
    :goto_line => nothing,
    :show_position => nothing,
    :set_bookmark => nothing,
    :goto_bookmark => nothing,
    :search => nothing,
    :next_match => nothing,
    :previous_match => nothing,
    :quit_search => nothing,
    :toggle_ruler => nothing,
    :toggle_column_ruler => nothing,
    :toggle_scrollbar => nothing,
    :help => :help,
    :change_freeze => :change_freeze,
    :select_freeze => :change_freeze,
    :change_title_rows => :change_freeze,
    :select_title_rows => :change_freeze,
    :toggle_visual_mode => :visual_mode,
    :select_visual_mode_line => :visual_mode,
    :mouse_select => :visual_mode,
    :yank => :visual_mode,
    :toggle_visual_anchor => :visual_mode,
    :yank_all => nothing,
    :save => nothing,
    :yank_quit => :visual_mode,
    :edit => nothing,
)

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

"""
    _resolve_action(pagerd::Pager, k::Keystroke) -> Union{Nothing, Symbol}

Resolve the pager action for keystroke `k` in the state of `pagerd`. The action
`:yank_quit`, which copies the selection and quits, is one line down outside the visual
mode, so that Enter keeps scrolling the text there.

# Arguments

- `pagerd::Pager`: Pager state used to resolve the action.
- `k::Keystroke`: Keystroke to resolve.
"""
function _resolve_action(pagerd::Pager, k::Keystroke)
    action = _pager_action(k)
    ((action === :yank_quit) && !pagerd.visual_mode) && return :down
    return action
end

"""
    _navigation_group(action::Union{Nothing, Symbol}) -> Union{Nothing, Symbol}

Return the axis and the direction of the movement `action`, which is `:vertical_forward`,
`:vertical_backward`, `:horizontal_forward`, or `:horizontal_backward`, or `nothing` if
`action` is not a movement. Consecutive movements of the same group are coalesced.

# Arguments

- `action::Union{Nothing, Symbol}`: Resolved pager action.
"""
function _navigation_group(action)
    axis, step, _ = _movement(action, 1, 1)
    axis === :none && return nothing
    forward = step > 0
    axis === :vertical && return forward ? :vertical_forward : :vertical_backward
    return forward ? :horizontal_forward : :horizontal_backward
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

    # The display size is queried once per burst instead of once per action. On a real terminal
    # this is a `TIOCGWINSZ` system call, and issuing up to `max_actions` of them consumed a
    # noticeable part of the `max_ns` budget, which reduced how many keystrokes could be
    # coalesced. A resize during the burst is handled by `_update_display_size!` on the next
    # iteration of the main loop, and the burst itself is bounded by `max_ns`.
    display_size_function(pagerd.term.out_stream) == pagerd.display_size || return count

    # The budget must bound the loop below, so the clock starts only after the display size was
    # obtained. Otherwise a slow query, or the compilation of `display_size_function` on its
    # first call, is charged to the budget and no keystroke is coalesced at all.
    start_time = time_ns()

    while count < max_actions && time_ns() - start_time < max_ns
        key = _try_read_keystroke!(pagerd.input)
        isnothing(key) && break
        action = _resolve_action(pagerd, key)
        if _navigation_group(action) !== group
            pagerd.input.pending = key
            break
        end

        _pager_key_process!(pagerd, key)
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

    # Most keystrokes are movements, which raise no event.
    isnothing(event) && return true

    # For EOT (^D), we will implement two types of "quit" action. If we are in searching
    # mode, exit it. If not, quit the pager.
    if event == :quit_eot
        event = pagerd.mode == :searching ? :quit_search : :quit
    end

    if event == :quit
        return false
    elseif event == :help
        _help!(pagerd)
    elseif event == :search
        _search!(pagerd)
    elseif event == :goto_line
        _goto_line!(pagerd)
    elseif event == :show_position
        _show_position!(pagerd)
    elseif event == :set_bookmark
        _set_bookmark!(pagerd)
    elseif event == :goto_bookmark
        _goto_bookmark!(pagerd)
    elseif event == :next_match
        _move_to_match!(pagerd, true)
    elseif event == :previous_match
        _move_to_match!(pagerd, false)
    elseif event == :quit_search
        _quit_search!(pagerd)
    elseif event == :change_freeze
        _change_freeze!(pagerd)
    elseif event == :select_freeze
        _select_freeze!(pagerd)
    elseif event == :change_title_rows
        _change_title_rows!(pagerd)
    elseif event == :select_title_rows
        _select_title_rows!(pagerd)
    elseif event == :toggle_ruler
        _toggle_ruler!(pagerd)
    elseif event == :toggle_column_ruler
        _toggle_column_ruler!(pagerd)
    elseif event == :toggle_scrollbar
        _toggle_scrollbar!(pagerd)
    elseif event == :toggle_visual_mode
        _toggle_visual_mode!(pagerd)
    elseif event == :mouse_select
        _mouse_select!(pagerd)
    elseif event == :select_visual_mode_line
        _toggle_visual_line!(pagerd)
    elseif event == :yank
        _yank!(pagerd)
    elseif event == :toggle_visual_anchor
        _toggle_visual_anchor!(pagerd)
    elseif event == :yank_all
        _yank_all!(pagerd)
    elseif event == :save
        _save!(pagerd)
    elseif event == :yank_quit
        _yank!(pagerd)
        return false
    elseif event == :edit
        _edit!(pagerd)
    end

    # Some events move the view, such as going to a line or to a search match. The visual
    # line is relative to the view, so it must be kept inside the text again. Otherwise, the
    # next frame shows no visual line, because it points past the end of the text.
    _clamp_visual_line!(pagerd)

    return true
end

"""
    _change_freeze!(pagerd::Pager) -> Nothing

Prompt for the numbers of frozen rows and columns of `pagerd`, apply them, and request a
redraw. An invalid or cancelled number of rows also skips the prompt for the columns.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _change_freeze!(pagerd::Pager)
    status, frozen_rows = _prompt_number!(pagerd, "Frozen rows", pagerd.frozen_rows)

    # An invalid or cancelled number of rows also skips the prompt for the columns.
    if status in (:value, :empty)
        if status === :value
            # The clamped field value must be used here, not the raw parsed one, and the
            # first visible row must stay inside the text.
            pagerd.frozen_rows = max(0, frozen_rows)
            pagerd.start_row = clamp(
                pagerd.start_row,
                pagerd.frozen_rows + 1,
                max(pagerd.frozen_rows + 1, pagerd.num_lines),
            )
            pagerd.visual_mode_line = 1

            # The crop counters describe the previous layout, so they must be recomputed by
            # the next `_view!` instead of being reused by the movement handling.
            pagerd.cropped_lines = 0
            pagerd.cropped_columns = 0
        end

        status, frozen_columns = _prompt_number!(
            pagerd, "Frozen columns", pagerd.frozen_columns
        )

        if status === :value
            pagerd.frozen_columns = max(0, frozen_columns)
            pagerd.start_column = max(pagerd.start_column, pagerd.frozen_columns + 1)
            pagerd.cropped_lines = 0
            pagerd.cropped_columns = 0
        end

        if status !== :invalid
            _set_message!(
                pagerd,
                "Frozen $(pagerd.frozen_rows) rows × $(pagerd.frozen_columns) columns",
            )
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _select_freeze!(pagerd::Pager) -> Nothing

Select the frozen rows and columns of `pagerd` on the screen and request a redraw.

The view moves to the top-left corner of the text with only the title rows frozen, and the
rows and the columns that would be frozen are marked by two guide lines drawn with the
face `freeze_guide`. The movement keys and the mouse move the selection, Enter applies it,
and the keys bound to `:quit`, `:quit_search`, and `:quit_eot` cancel it. In both cases, the
viewport is restored and clamped to the frozen region. Nothing happens, and an error
message is shown, if the text is empty or if the title rows do not fit in the view.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _select_freeze!(pagerd::Pager)
    rows, cols = _get_pager_display_size(pagerd)
    title_rows = pagerd.title_rows

    if pagerd.num_lines == 0
        _set_message!(pagerd, "Nothing to freeze"; kind = :error)
        return nothing
    end

    if (rows <= 0) || (cols <= 0) || (title_rows >= rows)
        _set_message!(
            pagerd, "Not enough rows to show the $title_rows title rows"; kind = :error
        )
        return nothing
    end

    saved = (
        start_row = pagerd.start_row,
        start_column = pagerd.start_column,
        frozen_rows = pagerd.frozen_rows,
        frozen_columns = pagerd.frozen_columns,
        mode = pagerd.mode,
    )

    # Only the titles stay frozen, and everything else scrolls to the top-left corner of the
    # text, so that the screen rows and columns are the text rows and columns.
    pagerd.frozen_rows = title_rows
    pagerd.frozen_columns = 0
    pagerd.start_row = title_rows + 1
    pagerd.start_column = 1

    applied = _run_selection!(
        pagerd, :freeze_selection, saved.mode, saved.frozen_rows, saved.frozen_columns
    )

    if applied
        pagerd.frozen_rows = pagerd.freeze_selection_rows
        pagerd.frozen_columns = pagerd.freeze_selection_columns
        pagerd.visual_mode_line = 1
        _set_message!(
            pagerd,
            "Frozen $(pagerd.frozen_rows) rows × $(pagerd.frozen_columns) columns",
        )
    else
        pagerd.frozen_rows = saved.frozen_rows
        pagerd.frozen_columns = saved.frozen_columns
    end

    _end_selection!(pagerd, saved.start_row, saved.start_column)

    return nothing
end

"""
    _select_title_rows!(pagerd::Pager) -> Nothing

Select the title rows of `pagerd` on the screen and request a redraw.

The view moves to the top-left corner of the text with nothing frozen, and a guide line
drawn with the face `freeze_guide` marks the rows that would be titles. The movement keys
and the mouse move it, Enter applies the selection, and the keys bound to `:quit`,
`:quit_search`, and `:quit_eot` cancel it. Since the titles are always frozen, applying more
title rows than frozen rows freezes them as well. In both cases, the viewport is restored and
clamped to the frozen region. Nothing happens, and an error message is shown, if the text is
empty or if the view has no rows.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _select_title_rows!(pagerd::Pager)
    rows, cols = _get_pager_display_size(pagerd)

    if pagerd.num_lines == 0
        _set_message!(pagerd, "Nothing to select"; kind = :error)
        return nothing
    end

    if (rows <= 0) || (cols <= 0)
        _set_message!(pagerd, "Not enough rows to select the title rows"; kind = :error)
        return nothing
    end

    saved = (
        start_row = pagerd.start_row,
        start_column = pagerd.start_column,
        frozen_rows = pagerd.frozen_rows,
        frozen_columns = pagerd.frozen_columns,
        title_rows = pagerd.title_rows,
        mode = pagerd.mode,
    )

    # Nothing stays frozen, and the view scrolls to the top-left corner of the text, so that
    # the screen rows are the text rows.
    pagerd.frozen_rows = 0
    pagerd.frozen_columns = 0
    pagerd.title_rows = 0
    pagerd.start_row = 1
    pagerd.start_column = 1

    applied = _run_selection!(pagerd, :title_selection, saved.mode, saved.title_rows, 0)

    pagerd.frozen_rows = saved.frozen_rows
    pagerd.frozen_columns = saved.frozen_columns

    if applied
        title_rows = pagerd.freeze_selection_rows
        pagerd.title_rows = title_rows

        # The titles are always frozen.
        if title_rows > saved.frozen_rows
            pagerd.frozen_rows = title_rows
            pagerd.visual_mode_line = 1
            _set_message!(
                pagerd, "$title_rows title rows, frozen rows raised to $title_rows"
            )
        else
            _set_message!(pagerd, "$title_rows title rows")
        end
    else
        pagerd.title_rows = saved.title_rows
    end

    _end_selection!(pagerd, saved.start_row, saved.start_column)

    return nothing
end

"""
    _run_selection!(pagerd::Pager, mode::Symbol, saved_mode::Symbol, rows::Int,
        columns::Int) -> Bool

Run the on-screen selection loop of `pagerd` in `mode`, starting with `rows` rows and
`columns` columns selected, and return whether the selection was applied.

The loop redraws the screen, keeps the selection inside the view when the display is
resized, and reads the keystrokes directly: Enter applies the selection, the keys bound to
`:quit`, `:quit_search`, and `:quit_eot` cancel it, and the other keystrokes move it. The
mode of the pager is set back to `saved_mode` when the loop ends.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `mode::Symbol`: Selection mode, `:freeze_selection` or `:title_selection`.
- `saved_mode::Symbol`: Mode to restore when the loop ends.
- `rows::Int`: Initial number of selected rows.
- `columns::Int`: Initial number of selected columns.
"""
function _run_selection!(
    pagerd::Pager, mode::Symbol, saved_mode::Symbol, rows::Int, columns::Int
)
    pagerd.mode = mode
    pagerd.freeze_selection_rows = rows
    pagerd.freeze_selection_columns = columns
    _clamp_freeze_selection!(pagerd)
    _request_redraw!(pagerd)

    applied = false

    try
        while true
            if pagerd.redraw
                _view!(pagerd)
                _redraw!(pagerd)
                _redraw_status_bar!(pagerd)
            end

            # A change of the display size repaints the view without waiting for a
            # keystroke. The selection must stay inside the new view.
            if !_wait_for_input!(pagerd)
                _update_display_size!(pagerd)
                _clamp_freeze_selection!(pagerd)
                _request_redraw!(pagerd)
                continue
            end

            k = _read_keystroke!(pagerd.input)

            # Enter is bound to a movement, so it must be checked before the bindings.
            if (k.value == "<enter>") || (k.value == "<keypad_enter>")
                applied = true
                break
            end

            action = _pager_action(k)

            if (action === :quit) || (action === :quit_search) || (action === :quit_eot)
                break
            end

            _move_freeze_selection!(pagerd, action, k)
        end
    finally
        pagerd.mode = saved_mode
    end

    return applied
end

"""
    _end_selection!(pagerd::Pager, start_row::Int, start_column::Int) -> Nothing

Restore the viewport of `pagerd` to `start_row` and `start_column` after an on-screen
selection, keep it outside the frozen region, and request a redraw.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `start_row::Int`: First visible row to restore.
- `start_column::Int`: First visible column to restore.
"""
function _end_selection!(pagerd::Pager, start_row::Int, start_column::Int)
    # Notice that the display size can have changed while the selection was active.
    pagerd.start_row = start_row
    pagerd.start_column = start_column
    _clamp_viewport!(pagerd)

    # The crop counters describe the frames of the selection, so they must be recomputed by
    # the next `_view!` instead of being reused by the movement handling.
    pagerd.cropped_lines = 0
    pagerd.cropped_columns = 0

    _request_redraw!(pagerd)

    return nothing
end

"""
    _freeze_selection_bounds(pagerd::Pager) -> Tuple{Int, Int, Int}

Return the minimum and the maximum numbers of rows, and the maximum number of columns, the
freeze selection of `pagerd` can have.

The rows are bounded by the title rows, which always stay frozen, and by the view and the
text. The columns are bounded by the view, without the ruler, and by the widest line, and
the title selection has no columns. The guides are drawn after the selected rows and
columns, so the view bounds leave one row and one column for them.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _freeze_selection_bounds(pagerd::Pager)
    rows, cols = _get_pager_display_size(pagerd)
    ruler_width = pagerd.show_ruler ? _ruler_width(pagerd) : 0

    max_rows = max(min(rows - 1, pagerd.num_lines), 0)
    min_rows = clamp(pagerd.title_rows, 0, max_rows)
    max_columns = if pagerd.mode == :title_selection
        0
    else
        max(min(cols - ruler_width - 1, _text_width(pagerd)), 0)
    end

    return min_rows, max_rows, max_columns
end

"""
    _clamp_freeze_selection!(pagerd::Pager) -> Nothing

Keep the freeze selection of `pagerd` inside its bounds.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _clamp_freeze_selection!(pagerd::Pager)
    min_rows, max_rows, max_columns = _freeze_selection_bounds(pagerd)
    pagerd.freeze_selection_rows = clamp(pagerd.freeze_selection_rows, min_rows, max_rows)
    pagerd.freeze_selection_columns = clamp(pagerd.freeze_selection_columns, 0, max_columns)
    return nothing
end

"""
    _move_freeze_selection!(pagerd::Pager, action::Union{Nothing, Symbol}, k::Keystroke) ->
        Nothing

Move the freeze selection of `pagerd` according to the movement `action` or to the position
of the mouse event `k`, and request a redraw if it changed.

The single movements move the selection by one, the fast ones by five rows or ten columns,
and `:home`, `:end`, `:bol`, and `:eol` move it to the bounds. A mouse press or drag inside
the view puts the guides on the pointer, selecting the rows above it and the columns at its
left, without the ruler. Every other keystroke is ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `action::Union{Nothing, Symbol}`: Resolved pager action of `k`.
- `k::Keystroke`: Keystroke to process.
"""
function _move_freeze_selection!(pagerd::Pager, action, k::Keystroke)
    min_rows, max_rows, max_columns = _freeze_selection_bounds(pagerd)
    rows = pagerd.freeze_selection_rows
    columns = pagerd.freeze_selection_columns

    if (k.value == "<mouse_press>") || (k.value == "<mouse_drag>")
        # In this mode, the screen row of a text row is its line number, because the view
        # starts at the first line after the titles and the column ruler. The guides are put
        # on the pointer, so the rows above it and the columns at its left are selected. A
        # click on either ruler selects nothing in its direction, and one on the status line
        # is ignored.
        view_row = k.y - _column_ruler_rows(pagerd)

        if 1 <= view_row <= _get_pager_display_size(pagerd)[1]
            ruler_width = pagerd.show_ruler ? _ruler_width(pagerd) : 0
            rows = view_row - 1
            columns = k.x - ruler_width - 1
        end
    elseif action === :up
        rows -= 1
    elseif action === :down
        rows += 1
    elseif action === :fastup
        rows -= 5
    elseif action === :fastdown
        rows += 5
    elseif action === :home
        rows = min_rows
    elseif action === :end
        rows = max_rows
    elseif action === :left
        columns -= 1
    elseif action === :right
        columns += 1
    elseif action === :fastleft
        columns -= 10
    elseif action === :fastright
        columns += 10
    elseif action === :bol
        columns = 0
    elseif action === :eol
        columns = max_columns
    end

    rows = clamp(rows, min_rows, max_rows)
    columns = clamp(columns, 0, max_columns)

    if (rows != pagerd.freeze_selection_rows) ||
        (columns != pagerd.freeze_selection_columns)
        pagerd.freeze_selection_rows = rows
        pagerd.freeze_selection_columns = columns
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _goto_line!(pagerd::Pager) -> Nothing

Prompt for a position and show that line at the top of the view of `pagerd`, like `less`
does, and request a redraw. The position is a line number, a percentage of the text like
`50%`, an offset from the current top row like `+10` or `-5`, or `\$` or `end` for the last
page. The view never moves into the frozen rows, and an invalid or cancelled position keeps
it.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _goto_line!(pagerd::Pager)
    status, kind, value = _prompt_position!(pagerd, ":")

    if status === :value
        _remember_position!(pagerd)
        num_lines = pagerd.num_lines
        min_row = _first_scrollable_row(pagerd)

        line = if kind === :relative
            pagerd.start_row + value
        elseif kind === :percent
            round(Int, num_lines * value / 100)
        elseif kind === :end
            num_lines - _view_rows(pagerd) + 1
        else
            value
        end

        pagerd.start_row = clamp(line, min_row, max(min_row, num_lines))
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _remember_position!(pagerd::Pager) -> Nothing

Record the first visible row and column of `pagerd` as the position before a jump, so that
`''` returns to it.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _remember_position!(pagerd::Pager)
    pagerd.last_position = (pagerd.start_row, pagerd.start_column)
    return nothing
end

"""
    _set_bookmark!(pagerd::Pager) -> Nothing

Prompt for a letter and bookmark the first visible row of `pagerd`, or the visual line in
the visual mode, together with the first visible column. A cancelled prompt keeps the
bookmarks, and a key that is not a letter is reported.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _set_bookmark!(pagerd::Pager)
    c = _prompt_key!(pagerd, "m")
    _request_redraw!(pagerd)
    isnothing(c) && return nothing

    if !isletter(c)
        _set_message!(pagerd, "Bookmarks are letters"; kind = :error)
        return nothing
    end

    line = if pagerd.visual_mode
        pagerd.visual_mode_line + pagerd.start_row - 1
    else
        pagerd.start_row
    end

    pagerd.bookmarks[c] = (line, pagerd.start_column)
    _set_message!(pagerd, "Mark $c set")

    return nothing
end

"""
    _goto_bookmark!(pagerd::Pager) -> Nothing

Prompt for a letter and move the view of `pagerd` to its bookmark, or back to the position
before the last jump when the key is `'`. The bookmarked line is shown at the top of the
view, where the visual line is placed too. A missing bookmark is reported.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _goto_bookmark!(pagerd::Pager)
    c = _prompt_key!(pagerd, "'")
    _request_redraw!(pagerd)
    isnothing(c) && return nothing

    target = if c == '\''
        pagerd.last_position
    else
        get(pagerd.bookmarks, c, (0, 0))
    end

    if target == (0, 0)
        message = c == '\'' ? "No previous position" : "Mark $c not set"
        _set_message!(pagerd, message; kind = :error)
        return nothing
    end

    _remember_position!(pagerd)

    min_row = _first_scrollable_row(pagerd)
    pagerd.start_row = clamp(target[1], min_row, max(min_row, pagerd.num_lines))
    pagerd.start_column = max(target[2], pagerd.frozen_columns + 1)
    pagerd.visual_mode_line = 1

    return nothing
end

"""
    _bookmark_rows(pagerd::Pager) -> Union{Nothing, Set{Int}}

Return the rows marked in the line-number ruler of `pagerd`, which are its bookmarked lines,
or `nothing` if there is none.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _bookmark_rows(pagerd::Pager)
    isempty(pagerd.bookmarks) && return nothing
    return Set{Int}(first(position) for position in values(pagerd.bookmarks))
end

"""
    _show_position!(pagerd::Pager) -> Nothing

Show a message with the lines and the columns of the text that are visible in `pagerd`, the
totals, and the percentage of the text above the bottom of the view.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _show_position!(pagerd::Pager)
    num_lines = pagerd.num_lines
    view_rows = max(_view_rows(pagerd), 0)
    first_row = min(pagerd.start_row, num_lines)
    last_row = min(pagerd.start_row + view_rows - 1, num_lines)
    percentage = num_lines > 0 ? round(Int, 100 * last_row / num_lines) : 0

    cols = _get_pager_display_size(pagerd)[2]
    ruler_width = pagerd.show_ruler ? _ruler_width(pagerd) : 0
    view_cols = max(cols - pagerd.frozen_columns - ruler_width, 0)
    text_width = _text_width(pagerd)
    first_col = min(pagerd.start_column, text_width)
    last_col = min(pagerd.start_column + view_cols - 1, text_width)

    _set_message!(
        pagerd,
        "Lines $first_row-$last_row of $num_lines ($percentage%) · " *
            "Columns $first_col-$last_col of $text_width",
    )

    return nothing
end

"""
    _change_title_rows!(pagerd::Pager) -> Nothing

Prompt for the number of title rows of `pagerd`, apply it, and request a redraw. An invalid
or cancelled number keeps the current one.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _change_title_rows!(pagerd::Pager)
    status, title_rows = _prompt_number!(pagerd, "Title rows", pagerd.title_rows)

    if status === :value
        pagerd.title_rows = max(0, title_rows)
        _set_message!(pagerd, "$(pagerd.title_rows) title rows")
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_ruler!(pagerd::Pager) -> Nothing

Show or hide the line number ruler of `pagerd` and request a redraw. Hiding it scrolls the
view left if the text cropped at the right edge does not fill the reclaimed columns.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_ruler!(pagerd::Pager)
    pagerd.show_ruler = !pagerd.show_ruler

    # If the ruler is hidden, we must verify if the screen is near the right edge to fix the
    # `start_column`.
    if !pagerd.show_ruler
        ruler_spacing = _ruler_width(pagerd)

        if pagerd.cropped_columns ≤ ruler_spacing
            # Hiding the ruler reclaims `ruler_spacing` columns, of which `cropped_columns`
            # are filled by the text that was cropped at the right edge. Scrolling left by
            # the difference fills the rest. Scrolling by the full ruler width cropped that
            # text again. Notice that the reclaimed columns must not push the view into the
            # frozen region.
            pagerd.start_column = max(
                pagerd.start_column - (ruler_spacing - pagerd.cropped_columns),
                pagerd.frozen_columns + 1,
                1,
            )
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_column_ruler!(pagerd::Pager) -> Nothing

Show or hide the column ruler of `pagerd` and request a redraw. The ruler takes the first
two rows of the view, so the viewport is clamped to the new number of rows.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_column_ruler!(pagerd::Pager)
    pagerd.show_column_ruler = !pagerd.show_column_ruler
    _clamp_viewport!(pagerd)

    # Every row moved by two, so the snapshot no longer describes the screen.
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_scrollbar!(pagerd::Pager) -> Nothing

Show or hide the scrollbar of `pagerd` and request a redraw. Hiding it scrolls the view left
by one column if the text is scrolled to its right end.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_scrollbar!(pagerd::Pager)
    pagerd.show_scrollbar = !pagerd.show_scrollbar

    # Hiding the scrollbar reclaims one column that the cropped text can use. Like the
    # ruler, the reclaimed column must not push the view into the frozen region.
    if !pagerd.show_scrollbar && (pagerd.cropped_columns == 0)
        pagerd.start_column = max(pagerd.start_column - 1, pagerd.frozen_columns + 1, 1)
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _toggle_visual_mode!(pagerd::Pager) -> Nothing

Enter or leave the visual mode of `pagerd` and request a redraw. Leaving it clears the marks
and the range anchor, and moves the visual line back to the top of the view.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_mode!(pagerd::Pager)
    pagerd.visual_mode = !pagerd.visual_mode

    if !pagerd.visual_mode
        pagerd.visual_mode_line = 1
        empty!(pagerd.visual_mode_selected_lines)
        pagerd.visual_anchor = 0
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _visual_line_index(pagerd::Pager) -> Int

Return the line of the text under the visual line of `pagerd`.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
_visual_line_index(pagerd::Pager) = pagerd.visual_mode_line + pagerd.start_row - 1

"""
    _visual_range(pagerd::Pager) -> UnitRange{Int}

Return the lines between the range anchor of `pagerd` and its visual line, in both
directions, or an empty range when there is no anchor.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _visual_range(pagerd::Pager)
    anchor = pagerd.visual_anchor
    anchor == 0 && return 1:0
    visual_line = _visual_line_index(pagerd)
    return min(anchor, visual_line):max(anchor, visual_line)
end

"""
    _toggle_visual_anchor!(pagerd::Pager) -> Nothing

Anchor a range at the visual line of `pagerd`, or drop the anchor if there is one, and
request a redraw. Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_anchor!(pagerd::Pager)
    pagerd.visual_mode || return nothing
    pagerd.visual_anchor = pagerd.visual_anchor == 0 ? _visual_line_index(pagerd) : 0
    _request_redraw!(pagerd)
    return nothing
end

"""
    _selected_line_ids(pagerd::Pager) -> Vector{Int}

Return the lines selected in the visual mode of `pagerd`, sorted and without repetitions:
the visual line, the range between the anchor and the visual line, and the marked lines. The
result is empty outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _selected_line_ids(pagerd::Pager)
    pagerd.visual_mode || return Int[]

    ids = Int[_visual_line_index(pagerd)]
    append!(ids, _visual_range(pagerd))
    append!(ids, pagerd.visual_mode_selected_lines)

    return sort!(unique!(ids))
end

"""
    _num_selected_lines(pagerd::Pager) -> Int

Return the number of lines selected in the visual mode of `pagerd` without allocating, which
is the length of [`_selected_line_ids`](@ref).

# Arguments

- `pagerd::Pager`: Pager state to inspect.
"""
function _num_selected_lines(pagerd::Pager)
    pagerd.visual_mode || return 0

    visual_line = _visual_line_index(pagerd)
    range = _visual_range(pagerd)
    num_selected = isempty(range) ? 1 : length(range)

    # The marks outside the range are counted once. A mark can only be in the list once.
    for line in pagerd.visual_mode_selected_lines
        ((line in range) || (line == visual_line)) && continue
        num_selected += 1
    end

    return num_selected
end

"""
    _mouse_select!(pagerd::Pager) -> Nothing

Move the visual line of `pagerd` to the row of the last mouse click, or mark it if the click
was on the visual line, and request a redraw. Clicks outside the scrollable rows of the text
and outside the visual mode are ignored.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _mouse_select!(pagerd::Pager)
    pagerd.visual_mode || return nothing

    view_rows = _view_rows(pagerd)
    clicked_line = pagerd.mouse_row - _column_ruler_rows(pagerd) - pagerd.frozen_rows
    last_line = min(view_rows, pagerd.num_lines - pagerd.start_row + 1)

    (1 <= clicked_line <= last_line) || return nothing

    if clicked_line == pagerd.visual_mode_line
        _toggle_visual_line!(pagerd)
    else
        pagerd.visual_mode_line = clicked_line
        _request_redraw!(pagerd)
    end

    return nothing
end

"""
    _toggle_visual_line!(pagerd::Pager) -> Nothing

Mark the visual line of `pagerd`, or unmark it if it is already marked, and request a
redraw. Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _toggle_visual_line!(pagerd::Pager)
    if pagerd.visual_mode
        # With an anchor, the whole range is marked and the anchor is dropped.
        if pagerd.visual_anchor != 0
            for line in _visual_range(pagerd)
                (line in pagerd.visual_mode_selected_lines) ||
                    push!(pagerd.visual_mode_selected_lines, line)
            end

            pagerd.visual_anchor = 0
            _request_redraw!(pagerd)
            return nothing
        end

        visual_str_id = _visual_line_index(pagerd)

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

    return nothing
end

"""
    _yank!(pagerd::Pager) -> Nothing

Copy the visual line and the marked lines of `pagerd` to the system clipboard, leaving a
message telling how many lines were copied, or that the clipboard is not available.
Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _yank!(pagerd::Pager)
    pagerd.visual_mode || return nothing
    _copy_lines!(pagerd, _selected_line_ids(pagerd))
    return nothing
end

"""
    _yank_all!(pagerd::Pager) -> Nothing

Copy the whole text of `pagerd` to the system clipboard, leaving a message telling how many
lines were copied, that the clipboard is not available, or that there is nothing to copy.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _yank_all!(pagerd::Pager)
    if pagerd.num_lines == 0
        _set_message!(pagerd, "Nothing to copy"; kind = :error)
        return nothing
    end

    _copy_lines!(pagerd, 1:pagerd.num_lines)

    return nothing
end

"""
    _copy_lines!(pagerd::Pager, line_ids::AbstractVector{<:Integer}) -> Nothing

Copy the lines `line_ids` of the text of `pagerd` to the system clipboard without their
decorations, leaving a message telling how many lines were copied, or that the clipboard is
not available.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `line_ids::AbstractVector{<:Integer}`: Lines to copy.
"""
function _copy_lines!(pagerd::Pager, line_ids::AbstractVector{<:Integer})
    yanked_lines = _undecorated_lines(pagerd.text_layout, line_ids)
    num_yanked_lines = length(yanked_lines)
    yanked_text = _join_lines(yanked_lines)

    # The lines are kept before the clipboard is tried, so that they are returned by the
    # session and by `yanked` even where there is no clipboard.
    pagerd.yanked = yanked_lines
    empty!(_LAST_YANK)
    append!(_LAST_YANK, yanked_lines)

    # `clipboard` throws when no system clipboard provider is available, for example in a
    # headless session. The error must not tear down the pager.
    copied = try
        clipboard(yanked_text)
        true
    catch
        false
    end

    if copied
        _set_message!(
            pagerd,
            num_yanked_lines > 1 ? "$(num_yanked_lines) lines copied" : "1 line copied",
        )
    else
        _set_message!(pagerd, "Could not copy to the system clipboard"; kind = :error)
    end

    return nothing
end

"""
    _assemble_yank_text(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer};
        kwargs...
    ) -> Tuple{String, Int}

Assemble sorted, deduplicated lines with a trailing newline and return the text and the
selected-line count. The decorations are removed unless `keep_decorations` is `true`.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Canonical line sequence.
- `line_ids::AbstractVector{<:Integer}`: One-based line indices to sort and deduplicate.

# Keywords

- `keep_decorations::Bool`: Keep the escape sequences of the lines.
    (**Default**: `false`)
"""
function _assemble_yank_text(
    lines::AbstractVector{<:AbstractString}, line_ids; keep_decorations::Bool = false
)
    selected = _undecorated_lines(lines, line_ids; keep_decorations = keep_decorations)
    return _join_lines(selected), length(selected)
end

"""
    _undecorated_lines(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer};
        kwargs...
    ) -> Vector{String}

Return the lines `line_ids` of `lines`, sorted and deduplicated, without their decorations
unless `keep_decorations` is `true`.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Canonical line sequence.
- `line_ids::AbstractVector{<:Integer}`: One-based line indices to sort and deduplicate.

# Keywords

- `keep_decorations::Bool`: Keep the escape sequences of the lines.
    (**Default**: `false`)
"""
function _undecorated_lines(
    lines::AbstractVector{<:AbstractString}, line_ids; keep_decorations::Bool = false
)
    ids = sort!(unique!(collect(Int, line_ids)))
    selected = Vector{String}(undef, length(ids))

    for (i, id) in enumerate(ids)
        line = lines[id]
        selected[i] = keep_decorations ? String(line) : remove_decorations(line)
    end

    return selected
end

"""
    _join_lines(lines::Vector{String}) -> String

Join `lines` with a newline after each one of them.

# Arguments

- `lines::Vector{String}`: Lines to join.
"""
function _join_lines(lines::Vector{String})
    buf = IOBuffer(; sizehint = sum(sizeof, lines; init = 0) + length(lines))

    for line in lines
        write(buf, line, '\n')
    end

    return String(take!(buf))
end

# Function that opens a file in the editor at a line. It is a reference so that the tests
# can replace it.
const _EDITOR = Ref{Any}(InteractiveUtils.edit)

"""
    _edit!(pagerd::Pager) -> Nothing

Open the lines selected in the visual mode of `pagerd`, or the whole text outside it, in the
editor of `InteractiveUtils.edit` at the visual line or the first visible row. The text is
written without the decorations to a temporary file, which is deleted when the editor
returns. The terminal modes and the raw mode are left while the editor runs and entered
again afterwards, and the screen is repainted.

# Arguments

- `pagerd::Pager`: Pager state whose text is edited.
"""
function _edit!(pagerd::Pager)
    ids = pagerd.visual_mode ? _selected_line_ids(pagerd) : 1:pagerd.num_lines

    if isempty(ids)
        _set_message!(pagerd, "Nothing to edit"; kind = :error)
        return nothing
    end

    text, _ = _assemble_yank_text(pagerd.text_layout, ids)

    # The editor opens at the visual line, which is in the selection, or at the top row.
    line = if pagerd.visual_mode
        something(findfirst(==(_visual_line_index(pagerd)), ids), 1)
    else
        pagerd.start_row
    end

    path = tempname() * ".txt"
    write(path, text)

    modes = pagerd.terminal_modes
    term = pagerd.term

    # The editor needs the normal screen, a visible cursor, and the cooked input.
    _leave_terminal_modes!(modes, term.out_stream)
    _set_raw_mode!(term, false)

    try
        _EDITOR[](path, line)
    catch err
        err isa InterruptException && rethrow()
        _set_message!(
            pagerd, "Could not open the editor: $(sprint(showerror, err))"; kind = :error
        )
    finally
        _set_raw_mode!(term, true)
        _enter_terminal_modes!(
            modes,
            term.out_stream;
            cursor_key_mode = modes.cursor_key_mode,
            alternate_screen = modes.alternate_screen,
            hide_cursor = modes.cursor_hidden,
            mouse = modes.mouse,
        )
        rm(path; force = true)

        # The editor painted over the screen, so nothing of the frame is known anymore.
        _invalidate_frame!(pagerd)
        _request_redraw!(pagerd)
    end

    return nothing
end

# Lines copied by the last yank of the session, returned by `yanked`.
const _LAST_YANK = String[]

"""
    yanked() -> Vector{String}

Return a copy of the lines copied by the last yank of the current Julia session, without
their decorations, or an empty vector if nothing was copied yet. The lines are kept even
when the system clipboard is not available.

# Examples

```julia
julia> lines = TerminalPager.yanked()
```
"""
yanked() = copy(_LAST_YANK)

"""
    _save!(pagerd::Pager) -> Nothing

Prompt for a path and save the lines selected in the visual mode of `pagerd`, or the whole
text outside it, to that file without the decorations. A path starting with `!` keeps them.
A tilde is expanded, an existing file is overwritten only after a confirmation, and the
result or the error is reported on the status line.

# Arguments

- `pagerd::Pager`: Pager state whose text is saved.
"""
function _save!(pagerd::Pager)
    cmd_input = _read_cmd!(pagerd; prefix = "Save to › ", history = _SAVE_HISTORY)
    _request_redraw!(pagerd)
    isnothing(cmd_input) && return nothing

    keep_decorations = startswith(cmd_input, '!')
    path = expanduser(strip(keep_decorations ? cmd_input[2:end] : cmd_input))
    isempty(path) && return nothing

    ids = pagerd.visual_mode ? _selected_line_ids(pagerd) : 1:pagerd.num_lines

    if isempty(ids)
        _set_message!(pagerd, "Nothing to save"; kind = :error)
        return nothing
    end

    if ispath(path)
        answer = _prompt_key!(pagerd, "Overwrite $path? (y/n)")

        if answer != 'y'
            _set_message!(pagerd, "Save cancelled")
            return nothing
        end
    end

    text, num_saved_lines = _assemble_yank_text(
        pagerd.text_layout, ids; keep_decorations = keep_decorations
    )

    # The errors of the file system, like a missing directory or a denied permission, are
    # reported on the status line instead of tearing down the pager.
    try
        write(path, text)
    catch err
        err isa SystemError || rethrow()
        _set_message!(pagerd, "Could not save: $(Libc.strerror(err.errnum))"; kind = :error)
        return nothing
    end

    _push_history!(_SAVE_HISTORY, cmd_input)
    if num_saved_lines > 1
        _set_message!(pagerd, "$num_saved_lines lines saved to $path")
    else
        _set_message!(pagerd, "1 line saved to $path")
    end

    return nothing
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

Writing each piece separately would issue one system call per piece, which can cause
tearing.

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

    # Without this guard, the early return inside the loop below would report one row for
    # a screen that cannot show any.
    max_rows <= 0 && return 0

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
    max_rows = _frame_rows(pagerd)

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
        _record_viewport!(frame_cache, pagerd)
        pagerd.redraw = false
        return nothing
    end

    out = _screen_buffer!(pagerd)

    # When the view only scrolled, the terminal shifts the rows it already shows, and the
    # snapshot is shifted the same way. The comparison below then repaints only the rows
    # that entered the view, which is much cheaper than repainting every row.
    valid && pagerd.scroll_regions && _shift_frame!(out, frame_cache, pagerd, max_rows)

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

            # `_textview` always leaves the SGR state at its default, but we reset it anyway.
            # Otherwise, a row painted out of order could erase to the end of the line with a
            # colored background.
            write(out, _SGR_RESET)
        end

        _clear_to_eol(out)
        row_size > 0 &&
            GC.@preserve data unsafe_write(out, pointer(data, new_first[i]), UInt(row_size))

        previous_row = i
    end

    # Clear the rows that were painted before but are not part of this frame. If the snapshot
    # is not valid, we do not know what is on screen, so we must clear everything.
    last_stale = valid ? min(frame_cache.num_rows, max_rows) : max_rows

    @inbounds for i in (num_rows + 1):last_stale
        # A row recorded as empty is already blank.
        valid && (row_last[i] < row_first[i]) && continue
        _move_cursor(out, i, 1)
        write(out, _SGR_RESET)
        _clear_to_eol(out)
    end

    # The snapshot will not describe the screen until the frame is flushed and stored. Hence,
    # a failure in between forces a full repaint instead of leaving a stale snapshot.
    frame_cache.valid = false

    # The cursor is hidden for the whole session, so the frame is flushed as is.
    _flush_screen!(pagerd)

    _store_frame!(frame_cache, data, num_bytes, num_rows)
    _record_viewport!(frame_cache, pagerd)

    # Indicate that the redraw request was accomplished.
    pagerd.redraw = false

    return nothing
end

"""
    _record_viewport!(frame_cache::FrameCache, pagerd::Pager) -> Nothing

Record in `frame_cache` the viewport of `pagerd` that the snapshot describes.

# Arguments

- `frame_cache::FrameCache`: Cache to update.
- `pagerd::Pager`: Pager state whose viewport is recorded.
"""
function _record_viewport!(frame_cache::FrameCache, pagerd::Pager)
    frame_cache.start_row = pagerd.start_row
    frame_cache.start_column = pagerd.start_column
    frame_cache.frozen_rows = pagerd.frozen_rows
    return nothing
end

"""
    _shift_frame!(out::IOBuffer, frame_cache::FrameCache, pagerd::Pager, max_rows::Int) ->
        Bool

Shift the scrollable rows of the terminal and of the snapshot in `frame_cache` by the
vertical movement of the viewport of `pagerd` since the snapshot was painted, and return
whether the shift was performed.

The shift is performed only for a pure vertical movement smaller than the scrollable region,
that is, when the first visible column and the frozen rows are unchanged. The sequences
asking the terminal to shift the rows are written to `out`. The rows the terminal blanks
while shifting are recorded as empty in the snapshot, so that the comparison with the new
frame repaints exactly the rows that entered the view.

# Arguments

- `out::IOBuffer`: Buffer assembling everything sent to the terminal.
- `frame_cache::FrameCache`: Cache whose snapshot is shifted.
- `pagerd::Pager`: Pager state with the current viewport.
- `max_rows::Int`: Number of rows the screen can show.
"""
function _shift_frame!(out::IOBuffer, frame_cache::FrameCache, pagerd::Pager, max_rows::Int)
    delta = pagerd.start_row - frame_cache.start_row

    # The scrollable region starts after the column ruler and the frozen rows.
    top = _column_ruler_rows(pagerd) + pagerd.frozen_rows + 1
    bottom = max_rows
    height = bottom - top + 1

    (frame_cache.start_column == pagerd.start_column) || return false
    (frame_cache.frozen_rows == pagerd.frozen_rows) || return false
    ((height >= 2) && (0 < abs(delta) < height)) || return false

    # Ask the terminal to shift the rows of the scrollable region.
    write(out, CSI)
    _write_decimal(out, top)
    write(out, UInt8(';'))
    _write_decimal(out, bottom)
    write(out, UInt8('r'))
    write(out, CSI)
    _write_decimal(out, abs(delta))
    write(out, delta > 0 ? UInt8('S') : UInt8('T'))
    write(out, _RESET_SCROLL_REGION)

    # Shift the snapshot rows the same way. The rows after the ones the snapshot describes
    # were cleared by the previous redraws, and the rows vacated by the shift are blanked by
    # the terminal, so both are recorded as empty rows.
    row_first = frame_cache.row_first
    row_last = frame_cache.row_last
    num_known = length(row_first)
    resize!(row_first, max_rows)
    resize!(row_last, max_rows)

    @inbounds for i in (num_known + 1):max_rows
        row_first[i] = 1
        row_last[i] = 0
    end

    @inbounds if delta > 0
        for i in top:(bottom - delta)
            row_first[i] = row_first[i + delta]
            row_last[i] = row_last[i + delta]
        end

        for i in (bottom - delta + 1):bottom
            row_first[i] = 1
            row_last[i] = 0
        end
    else
        for i in bottom:-1:(top - delta)
            row_first[i] = row_first[i + delta]
            row_last[i] = row_last[i + delta]
        end

        for i in top:(top - delta - 1)
            row_first[i] = 1
            row_last[i] = 0
        end
    end

    frame_cache.num_rows = max_rows

    return true
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
