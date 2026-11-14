## Description #############################################################################
#
# Pager session: its options, the terminal modes it enables, and its main loop.
#
############################################################################################

"""
    _session_options(kwargs::Any) -> SessionOptions

Return the options of a pager session given `kwargs`, the keywords received by the function
that starts it, as a named tuple or as the pairs of a keyword slurp.

# Arguments

- `kwargs::Any`: Keywords of the session.

# Extended help

## Throws

- `MethodError`: If a keyword is not an option of the session.
- `TypeError`: If the value of a keyword has the wrong type.
"""
function _session_options(@nospecialize(kwargs))
    # NOTE: This function reads the keywords with built-in functions only. Hence, nothing
    # is compiled for each combination of keywords, which is why they are collected here.
    keywords = kwargs isa NamedTuple ? kwargs : getfield(kwargs, :data)
    names = fieldnames(typeof(keywords))
    options = SessionOptions()

    for i in 1:nfields(keywords)
        name = names[i]::Symbol

        # This is the error thrown for a keyword that a function does not support.
        hasfield(SessionOptions, name) ||
            throw(MethodError(Core.kwcall, (keywords, _pager!), Base.get_world_counter()))

        setfield!(options, name, getfield(keywords, i))
    end

    return options
end

"""
    _default_terminal() -> REPL.Terminals.TTYTerminal

Create the terminal of a pager session, which is connected to the standard streams.
"""
_default_terminal() = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

"""
    _pager(
        str::String,
        options::SessionOptions,
        history_options::Union{Nothing, NamedTuple} = nothing
    ) -> PagerResult
    _pager(str::String; kwargs...) -> Union{Nothing, PagerResult}

Open an interactive pager for `str` with the session `options`, or print it directly when
the automatic mode is selected and it fits in the display, and return the result of the
session. The method with keywords creates the options from them, and it returns `nothing`
unless the keyword `return_selection` is `true`.

If `history_options` is not `nothing`, the text is recorded in the pager history with those
options when the session starts, so that it can be reopened. A text that was only printed
is not recorded, because the pager did not show it.

# Arguments

- `str::String`: Text to display.
- `options::SessionOptions`: Options of the session.
- `history_options::Union{Nothing, NamedTuple}`: Keywords recorded with the text in the pager
    history, or `nothing` to not record it.
    (**Default**: `nothing`)

# Keywords

- `kwargs...`: Fields of [`SessionOptions`](@ref).
"""
function _pager(
    str::String,
    options::SessionOptions,
    @nospecialize(history_options::Union{Nothing, NamedTuple} = nothing),
)
    # `split` yields `SubString`s, and both `_pager_content_fits` and `ViewLayout` accept
    # them. Copying every line into a `String` here duplicated the whole text before the first
    # frame was shown.
    lines = split(str, '\n')
    display_size = displaysize(stdout)::Tuple{Int, Int}

    if options.auto && _pager_content_fits(lines, display_size)
        print(str)
        return _empty_result()
    end

    # The text is recorded before the session, so that a session interrupted with CTRL-C is
    # in the history too. Its result restores the viewport when the text is reopened.
    entry = if isnothing(history_options)
        nothing
    else
        _push_pager_history!(str, history_options)
    end

    text_layout = options._layout_factory(_drop_trailing_empty_line!(lines))
    display_config = options._display_config_loader()
    input = options._input_factory(stdin)

    # Initialize the terminal.
    term = options._terminal_factory()

    # Switch the terminal to raw mode so that every keystroke is passed immediately instead
    # of waiting for <return>.
    result = options._raw_runner(term) do
        options.auto = false
        options.text_layout = text_layout
        options.display_config = display_config
        options.input = input

        _pager!(term, str, options)
    end

    (!isnothing(entry) && (result isa PagerResult)) && (entry.result = result)

    return result
end

function _pager(str::String; @nospecialize(kwargs...))
    options = _session_options(kwargs)
    result = _pager(str, options)
    return options.return_selection ? result : nothing
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
    _pager!(
        term::REPL.Terminals.TTYTerminal,
        str::String,
        options::SessionOptions
    ) -> PagerResult
    _pager!(term::REPL.Terminals.TTYTerminal, str::String; kwargs...) -> PagerResult

Run the interactive pager for `str` with the session `options` using a terminal that is
already in raw mode, and return what the session left: the last yanked lines, the viewport,
and the search pattern. The result of a text printed by the automatic mode is empty. The
method with keywords creates the options from them.

# Arguments

- `term::REPL.Terminals.TTYTerminal`: Terminal used by the pager session.
- `str::String`: Text to display.
- `options::SessionOptions`: Options of the session.

# Keywords

- `kwargs...`: Fields of [`SessionOptions`](@ref).
"""
function _pager!(
    @nospecialize(term::REPL.Terminals.TTYTerminal), str::String; @nospecialize(kwargs...)
)
    return _pager!(term, str, _session_options(kwargs))
end

function _pager!(
    @nospecialize(term::REPL.Terminals.TTYTerminal), str::String, options::SessionOptions
)
    text_layout = options.text_layout
    display_config = options.display_config
    input = options.input
    use_alternate_screen_buffer = options.use_alternate_screen_buffer

    # The raw text is split only when no layout is supplied, and the result feeds both the
    # auto-fit check and the layout construction.
    source_lines = isnothing(text_layout) ? split(str, '\n') : text_layout

    # Get the display size and make sure it is type stable.
    dsize = displaysize(term.out_stream)::Tuple{Int, Int}

    if options.auto && _pager_content_fits(source_lines, dsize)
        print(str)
        return _empty_result()
    end

    # Like the prompts that change them, the numbers of frozen and title rows and columns
    # cannot be negative. Otherwise, the view has more rows than the display, and a page
    # movement skips lines.
    frozen_rows = max(options.frozen_rows, 0)
    frozen_columns = max(options.frozen_columns, 0)
    title_rows = max(options.title_rows, 0)

    session_layout = if isnothing(text_layout)
        options._layout_factory(_drop_trailing_empty_line!(source_lines))
    else
        text_layout
    end

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
            cursor_key_mode = options.manage_cursor_key_mode,
            alternate_screen = use_alternate_screen_buffer,
            hide_cursor = options.manage_cursor,
            mouse = options.manage_mouse && _get_preference("mouse")::Bool,
        )

        # The pager is divided into a view and a command line. Everything in the view is
        # written to this buffer and then flushed to the screen.
        # The color flag must come from the session terminal, not from the global `stdout`,
        # so that a terminal built for another stream honors its own color support.
        iobuf = IOBuffer()
        hascolor = get(term.out_stream, :color, true)::Bool
        buf = IOContext(iobuf, :color => hascolor)

        features = Symbol[]
        options.change_freeze && push!(features, :change_freeze)
        options.has_help && push!(features, :help)
        options.has_visual_mode && push!(features, :visual_mode)

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
            show_ruler = options.show_ruler,
            show_column_ruler = options.show_column_ruler,
            show_scrollbar = options.show_scrollbar,
            status_position = Symbol(_get_preference("status_position")::String),
            scroll_regions = _get_preference("use_scroll_regions")::Bool,
            start_column = max(1, frozen_columns + 1),
            start_row = min(max(1, frozen_rows + 1), num_tokens),
            term = term,
            terminal_modes = modes,
            text_layout = session_layout,
            title_rows = title_rows,
        )

        restore = options._restore
        isnothing(restore) || _restore_state!(pagerd, restore)

        # A session can start with bookmarks, like the chapters of the extended help.
        merge!(pagerd.bookmarks, options._bookmarks)

        # The waiter lets a change of the display size interrupt the wait for the input, so
        # that the screen is repainted without a keystroke. A nested session, such as the
        # help, shares the waiter of its parent through the input.
        if isnothing(session_input.waiter)
            waiter = options._waiter_factory(term)

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
            pagerd.redraw && _paint!(pagerd)

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

            # The files created by the session are not needed anymore.
            (@isdefined pagerd) && _remove_temporary_files!(pagerd)
        end
    end

    # The first visible line is a line of the text, not a row of the view, which are not
    # the same when a filter is active. Otherwise, the position could not be restored.
    return PagerResult(
        pagerd.yanked,
        _source_line(pagerd, pagerd.start_row),
        pagerd.start_column,
        pagerd.search_pattern,
    )
end

"""
    _remove_temporary_files!(pagerd::Pager) -> Nothing

Remove the files created by the session of `pagerd`, like the ones opened in the editor. A
file that cannot be removed is left where it is.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _remove_temporary_files!(pagerd::Pager)
    for path in pagerd.temporary_files
        # The file is in the temporary directory, so that it is not worth an error.
        try
            rm(path; force = true)
        catch err
            err isa Base.IOError || rethrow()
        end
    end

    empty!(pagerd.temporary_files)

    return nothing
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
    _drop_trailing_empty_line!(lines::Vector{<:AbstractString}) -> Vector{<:AbstractString}

Remove the last element of `lines`, the lines of a text split at the newlines, if it is the
empty string after the newline that ends the text, and return `lines`.

A text that ends with a newline has no line after it. Otherwise, the pager would show, count,
copy, and save an empty line that the text does not have. A text with a single empty line is
kept as it is.

# Arguments

- `lines::Vector{<:AbstractString}`: Lines of the text.
"""
function _drop_trailing_empty_line!(lines::Vector{<:AbstractString})
    ((length(lines) > 1) && isempty(lines[end])) && pop!(lines)
    return lines
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
