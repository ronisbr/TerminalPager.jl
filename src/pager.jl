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

    # We need to remove one row due to the status bar and one column due to the scrollbar.
    # Notice that a degenerate terminal must not produce negative sizes.
    rows = max(rows - 1, 0)
    p.show_scrollbar && (cols = max(cols - 1, 0))

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

    min_row = max(1, p.frozen_rows + 1)
    view_rows = rows - p.frozen_rows
    max_row = max(min_row, p.num_lines - view_rows + 1)
    p.start_row = clamp(p.start_row, min_row, max_row)

    min_col = max(1, p.frozen_columns + 1)
    ruler_width = p.show_ruler ? _ruler_width(p.num_lines) : 0
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
        p.text_width = maximum(p.text_layout._printable_widths; init = 0)
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
- `show_scrollbar::Bool`: Show the scrollbar initially.
    (**Default**: the value of the preference `"show_scrollbar"`)
- `use_alternate_screen_buffer::Bool`: Request the terminal's alternate screen
    buffer.
    (**Default**: `true`)
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
- `manage_cursor::Bool`: Hide the cursor during the session, and show it and clear the
    status bar row when the session ends. A nested session must not do this.
    (**Default**: `true`)
- `manage_mouse::Bool`: Enable the mouse reporting during the session if the preference
    `"mouse"` is enabled, and disable it when the session ends. A nested session must not
    do this.
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
    show_scrollbar::Bool = _get_preference("show_scrollbar")::Bool,
    use_alternate_screen_buffer::Bool = true,
    input::Union{Nothing, PagerInput} = nothing,
    lines::Union{Nothing, AbstractVector{<:AbstractString}} = nothing,
    text_layout::Union{Nothing, TextViewLayout} = nothing,
    _layout_factory = TextViewLayout,
    manage_cursor_key_mode::Bool = true,
    manage_cursor::Bool = true,
    manage_mouse::Bool = true,
)
    # Reuse a supplied layout or line vector; the raw text is split only when neither is
    # available, and the result feeds both the auto-fit check and the layout construction.
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
    block_alternate_screen_buffer = _get_preference("block_alternate_screen_buffer")::Bool
    use_alternate_screen_buffer &= !block_alternate_screen_buffer

    cursor_key_mode_enabled = false
    alternate_screen_enabled = false
    cursor_hidden = false
    mouse_enabled = false
    try
        if manage_cursor_key_mode
            cursor_key_mode_enabled = true
            _turn_on_cursor_key_mode(term.out_stream)
        end

        # Clear the screen and position the cursor at the top.
        if use_alternate_screen_buffer
            # As in `_with_raw_mode`, the flag is set before the write, so that a write that
            # partially reached the terminal is still undone.
            alternate_screen_enabled = true
            _turn_on_alternate_screen_buffer(term.out_stream)
        else
            _clear_screen(term.out_stream)
        end

        # The cursor has nothing to point at in the view. Hence, it is hidden for the whole
        # session and shown only while a command is edited. As above, the flag is set before
        # the write.
        if manage_cursor
            cursor_hidden = true
            _hide_cursor(term.out_stream)
        end

        # The mouse reporting lets the wheel scroll the text. It is a terminal state that
        # outlives the session if it is not disabled at the end.
        if manage_mouse && _get_preference("mouse")::Bool
            mouse_enabled = true
            _turn_on_mouse(term.out_stream)
        end

        # The pager is divided into a view and a command line. Everything in the view is
        # written to this buffer and then flushed to the screen.
        # The color flag must come from the session terminal, not from the global `stdout`,
        # so that a terminal built for another stream honors its own color support.
        iobuf = IOBuffer()
        hascolor = get(term.out_stream, :color, true)::Bool
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
            show_scrollbar = show_scrollbar,
            scroll_regions = _get_preference("use_scroll_regions")::Bool,
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
                _redraw_status_bar!(pagerd)
            end

            # Wait for user input. A message on the command line is shown until this
            # keystroke, which is then processed normally.
            k = _read_keystroke!(pagerd.input)
            _clear_message!(pagerd)
            action = _pager_key_process!(pagerd, k)
            _coalesce_navigation!(pagerd, action)
            _pager_event_process!(pagerd) || break
        end
    finally
        _restore_terminal(
            term.out_stream;
            mouse = mouse_enabled,
            clear_status_row = cursor_hidden && !alternate_screen_enabled,
            show_cursor = cursor_hidden,
            alternate_screen = alternate_screen_enabled,
            cursor_key_mode = cursor_key_mode_enabled,
        )
    end

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

function _pager_content_fits(layout::TextViewLayout, display_size::Tuple{Int, Int})
    display_size[1] - 2 >= _content_fit_rows(layout) || return false

    # The layout already measured every line while it was prepared, so there is no need to scan
    # the text again. This is the path every `pager>` REPL command takes.
    return all(width -> width <= display_size[2], layout._printable_widths)
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

    action = _pager_action(k)

    # The position of a mouse event is kept for the events that need it.
    if (k.x > 0) && (k.y > 0)
        pagerd.mouse_column = k.x
        pagerd.mouse_row = k.y
    end

    # Compute the minimum value for the start row.
    min_row = max(1, frozen_rows + 1)

    # A page has the size of the view, which excludes the command line and the frozen rows.
    # Using the full display height here skipped `frozen_rows` lines at every page movement,
    # and those lines were never shown. Both values are clamped so that paging always moves
    # at least one line.
    view_rows = display_size[1] - 1 - frozen_rows
    page_rows = max(view_rows, 1)
    half_page_rows = max(div(view_rows, 2), 1)

    # We should disable the visual line mode if there is no selectable line, that is, if all
    # lines are frozen or if the first content row is beyond the view. Notice that the view
    # has `display_size[1] - 1` rows, because the last one is the command line, and that at
    # `min_row == num_lines` exactly one selectable line remains.
    if pagerd.visual_mode && ((min_row > num_lines) || (min_row > display_size[1] - 1))
        pagerd.visual_mode = false
        pagerd.visual_mode_line = 1

        # The selections must not survive the forced disable. Otherwise, they reappear the
        # next time the visual mode is enabled.
        empty!(pagerd.visual_mode_selected_lines)
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
    if pagerd.visual_mode
        max_visual_line = min(view_rows, num_lines - pagerd.start_row + 1)
        pagerd.visual_mode_line = clamp(pagerd.visual_mode_line, 1, max(1, max_visual_line))
    end

    return action
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
    frozen_rows = pagerd.frozen_rows
    min_row = max(1, frozen_rows + 1)
    view_rows = pagerd.display_size[1] - 1 - frozen_rows
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

    if action in (
        :quit,
        :quit_eot,
        :goto_line,
        :search,
        :next_match,
        :previous_match,
        :quit_search,
        :toggle_ruler,
        :toggle_scrollbar,
    )
        return action
    end

    action === :help && return :help ∈ features ? action : nothing

    if action in (:change_freeze, :change_title_rows)
        return :change_freeze ∈ features ? action : nothing
    end

    if action in (:toggle_visual_mode, :select_visual_mode_line, :mouse_select, :yank)
        return :visual_mode ∈ features ? action : nothing
    end

    return nothing
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
        action = _pager_action(key)
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
        _search!(pagerd)

    elseif event == :goto_line
        status, line = _prompt_number!(pagerd, ":")

        if status === :value
            # The requested line is shown at the top of the view, like `less` does, and the
            # view never moves into the frozen rows.
            min_row = max(1, pagerd.frozen_rows + 1)
            pagerd.start_row = clamp(line, min_row, max(min_row, pagerd.num_lines))
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

    elseif event == :change_title_rows
        status, title_rows = _prompt_number!(pagerd, "Title rows", pagerd.title_rows)

        if status === :value
            pagerd.title_rows = max(0, title_rows)
            _set_message!(pagerd, "$(pagerd.title_rows) title rows")
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_ruler
        pagerd.show_ruler = !pagerd.show_ruler

        # If the ruler is hidden, we must verify if the screen is near the right edge to fix
        # the `start_column`.
        if !pagerd.show_ruler
            ruler_spacing = _ruler_width(pagerd.num_lines)

            if pagerd.cropped_columns ≤ ruler_spacing
                # Hiding the ruler reclaims `ruler_spacing` columns, of which
                # `cropped_columns` are filled by the text that was cropped at the right
                # edge. Scrolling left by the difference fills the rest. Scrolling by the
                # full ruler width cropped that text again. Notice that the reclaimed
                # columns must not push the view into the frozen region.
                pagerd.start_column = max(
                    pagerd.start_column - (ruler_spacing - pagerd.cropped_columns),
                    pagerd.frozen_columns + 1,
                    1,
                )
            end
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_scrollbar
        pagerd.show_scrollbar = !pagerd.show_scrollbar

        # Hiding the scrollbar reclaims one column that the cropped text can use. Like the
        # ruler, the reclaimed column must not push the view into the frozen region.
        if !pagerd.show_scrollbar && (pagerd.cropped_columns == 0)
            pagerd.start_column = max(pagerd.start_column - 1, pagerd.frozen_columns + 1, 1)
        end

        _request_redraw!(pagerd)

    elseif event == :toggle_visual_mode
        pagerd.visual_mode = !pagerd.visual_mode

        if !pagerd.visual_mode
            pagerd.visual_mode_line = 1
            empty!(pagerd.visual_mode_selected_lines)
        end

        _request_redraw!(pagerd)

    elseif event == :mouse_select
        # A click moves the visual line to the clicked row, and a click on the visual line
        # marks it. Clicks outside the scrollable rows are ignored.
        if pagerd.visual_mode
            view_rows = pagerd.display_size[1] - 1 - pagerd.frozen_rows
            clicked_line = pagerd.mouse_row - pagerd.frozen_rows
            last_line = min(view_rows, pagerd.num_lines - pagerd.start_row + 1)

            if 1 <= clicked_line <= last_line
                if clicked_line == pagerd.visual_mode_line
                    pagerd.event = :select_visual_mode_line
                    return _pager_event_process!(pagerd)
                end

                pagerd.visual_mode_line = clicked_line
                _request_redraw!(pagerd)
            end
        end

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

            # `clipboard` throws when no system clipboard provider is available, for
            # example in a headless session. The error must not tear down the pager.
            copied = try
                clipboard(yanked_text)
                true
            catch
                false
            end

            if copied
                _set_message!(
                    pagerd,
                    num_yanked_lines > 1 ? "$(num_yanked_lines) lines copied" :
                        "1 line copied",
                )
            else
                _set_message!(
                    pagerd, "Could not copy to the system clipboard"; kind = :error
                )
            end
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

            # `textview` always leaves the SGR state at its default, but we reset it anyway.
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
    top = pagerd.frozen_rows + 1
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
