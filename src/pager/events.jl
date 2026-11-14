## Description #############################################################################
#
# Processing of the keystrokes of a pager session: the movements of the view and the
# dispatch of the events raised by the other actions.
#
############################################################################################

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
    min_col = _first_scrollable_column(pagerd)
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
    :filter => nothing,
    :next_match => nothing,
    :previous_match => nothing,
    :quit_search => nothing,
    :toggle_ruler => nothing,
    :toggle_column_ruler => nothing,
    :toggle_scrollbar => nothing,
    :help => :help,
    :extended_help => :help,
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
    elseif event == :extended_help
        _extended_help!(pagerd)
    elseif event == :search
        _search!(pagerd)
    elseif event == :filter
        _filter!(pagerd)
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
        _select_on_screen!(pagerd, :freeze_selection)
    elseif event == :change_title_rows
        _change_title_rows!(pagerd)
    elseif event == :select_title_rows
        _select_on_screen!(pagerd, :title_selection)
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
