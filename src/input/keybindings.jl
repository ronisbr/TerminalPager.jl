## Description #############################################################################
#
# Functions related to key bindings.
#
############################################################################################

# Dictionary with the default bindings. Notice that the key type must stay concrete:
# `Tuple{Union{Symbol, String}, Bool, Bool, Bool}` is not `isbits`, so every lookup has to
# dereference a boxed tuple. `_pager_action` only ever builds `String` keys anyway.
const _DEFAULT_KEYBINDINGS = Dict{Tuple{String, Bool, Bool, Bool}, Symbol}(
    ("q", false, false, false) => :quit,
    ("?", false, false, false) => :help,
    ("<up>", false, false, false) => :up,
    ("k", false, false, false) => :up,
    ("<down>", false, false, false) => :down,
    ("j", false, false, false) => :down,
    ("<enter>", false, false, false) => :down,
    ("<left>", false, false, false) => :left,
    ("h", false, false, false) => :left,
    ("<right>", false, false, false) => :right,
    ("l", false, false, false) => :right,
    ("<up>", false, false, true) => :fastup,
    ("<down>", false, false, true) => :fastdown,
    ("<left>", false, false, true) => :fastleft,
    ("<right>", false, false, true) => :fastright,
    ("<left>", true, false, false) => :bol,
    ("0", false, false, false) => :bol,
    ("^", false, false, false) => :bol,
    ("<right>", true, false, false) => :eol,
    ("\$", false, false, false) => :eol,
    ("u", false, false, false) => :halfpageup,
    ("d", false, false, false) => :halfpagedown,
    ("<pageup>", false, false, false) => :pageup,
    ("b", false, false, false) => :pageup,
    ("<pagedown>", false, false, false) => :pagedown,
    (" ", false, false, false) => :pagedown,
    ("<home>", false, false, false) => :home,
    ("<up>", true, false, false) => :home,
    ("g", false, false, false) => :home,
    ("<", false, false, false) => :home,
    ("<end>", false, false, false) => :end,
    ("<down>", true, false, false) => :end,
    ("G", false, false, false) => :end,
    (">", false, false, false) => :end,
    (":", false, false, false) => :goto_line,
    ("=", false, false, false) => :show_position,
    ("/", false, false, false) => :search,
    ("n", false, false, false) => :next_match,
    ("N", false, false, false) => :previous_match,
    ("<esc>", false, false, false) => :quit_search,
    # The raw mode delivers CTRL-C as a keystroke. Like in `less`, it cancels the current
    # operation instead of quitting the pager.
    ("c", false, true, false) => :quit_search,
    ("f", false, false, false) => :change_freeze,
    ("F", false, false, false) => :select_freeze,
    ("<eot>", false, false, false) => :quit_eot,
    ("r", false, false, false) => :toggle_ruler,
    ("R", false, false, false) => :toggle_column_ruler,
    ("s", false, false, false) => :toggle_scrollbar,
    ("t", false, false, false) => :change_title_rows,
    ("T", false, false, false) => :select_title_rows,
    ("v", false, false, false) => :toggle_visual_mode,
    ("M", false, false, false) => :select_visual_mode_line,
    ("m", false, false, false) => :set_bookmark,
    ("'", false, false, false) => :goto_bookmark,
    ("y", false, false, false) => :yank,
    ("Y", false, false, false) => :yank_all,
    ("S", false, false, false) => :save,
    ("V", false, false, false) => :toggle_visual_anchor,
    ("<wheel_up>", false, false, false) => :wheel_up,
    ("<wheel_down>", false, false, false) => :wheel_down,
    ("<wheel_up>", false, false, true) => :fastleft,
    ("<wheel_down>", false, false, true) => :fastright,
    ("<wheel_left>", false, false, false) => :fastleft,
    ("<wheel_right>", false, false, false) => :fastright,
    ("<mouse_press>", false, false, false) => :mouse_select,
)

# Dictionary with the current keybindings. It is initialized here with the default values
# to improve startup time.
const _KEYBINDINGS = copy(_DEFAULT_KEYBINDINGS)

# Bumped whenever `_KEYBINDINGS` changes, so that everything derived from it, such as the help
# screen, knows that it must be rebuilt.
const _KEYBINDINGS_GENERATION = Ref(0)

"""
    _keybindings_changed!() -> Nothing

Mark everything derived from `_KEYBINDINGS` as outdated.
"""
function _keybindings_changed!()
    _KEYBINDINGS_GENERATION[] += 1
    return nothing
end

# Every pager action, in the order they are documented. The key bindings are validated
# against this list, so a typo in an action name is reported instead of binding a dead key.
const _ACTIONS = Symbol[
    :quit,
    :quit_eot,
    :help,
    :up,
    :down,
    :left,
    :right,
    :fastup,
    :fastdown,
    :fastleft,
    :fastright,
    :bol,
    :eol,
    :pageup,
    :pagedown,
    :halfpageup,
    :halfpagedown,
    :home,
    :end,
    :wheel_up,
    :wheel_down,
    :goto_line,
    :show_position,
    :set_bookmark,
    :goto_bookmark,
    :search,
    :next_match,
    :previous_match,
    :quit_search,
    :change_freeze,
    :select_freeze,
    :change_title_rows,
    :select_title_rows,
    :toggle_ruler,
    :toggle_column_ruler,
    :toggle_scrollbar,
    :toggle_visual_mode,
    :select_visual_mode_line,
    :mouse_select,
    :yank,
    :toggle_visual_anchor,
    :yank_all,
    :save,
]

# Name of the preference that stores the persisted key bindings.
const _KEYBINDINGS_PREFERENCE = "keybindings"

# Value stored in the preference for a default binding that was deleted.
const _DELETED_BINDING = "delete"

"""
    _check_action(action::Symbol) -> Nothing

Throw an `ArgumentError` if `action` is not a pager action.

# Arguments

- `action::Symbol`: Action to check.
"""
function _check_action(action::Symbol)
    action in _ACTIONS && return nothing

    throw(
        ArgumentError(
            "$action is not a pager action. The valid actions are: " *
                join((":$a" for a in _ACTIONS), ", ") * ".",
        ),
    )
end

"""
    _actions_docstring() -> String

Return the list of the pager actions wrapped for the docstring of [`set_keybinding`](@ref).
"""
function _actions_docstring()
    return join(_wrap_words(join((":$a" for a in _ACTIONS), ", "), 80), "\n    ")
end

"""
    _encode_binding(kb::Tuple{String, Bool, Bool, Bool}) -> String

Return the key of the binding `kb` in the preference `"keybindings"`, which is the modifiers
`alt+`, `ctrl+`, and `shift+`, in this order, followed by the key value.

# Arguments

- `kb::Tuple{String, Bool, Bool, Bool}`: Key value and ALT, CTRL, and SHIFT flags.
"""
function _encode_binding(kb::Tuple{String, Bool, Bool, Bool})
    value, alt, ctrl, shift = kb
    return (alt ? "alt+" : "") * (ctrl ? "ctrl+" : "") * (shift ? "shift+" : "") * value
end

"""
    _decode_binding(str::AbstractString) -> Tuple{String, Bool, Bool, Bool}

Return the binding encoded in `str` by [`_encode_binding`](@ref). The modifiers are
stripped in the order `alt+`, `ctrl+`, and `shift+`, and the rest is the key value, so that
`"alt++"` is the key `+` with ALT.

# Arguments

- `str::AbstractString`: Encoded binding.
"""
function _decode_binding(str::AbstractString)
    value = String(str)
    alt = startswith(value, "alt+") && ncodeunits(value) > 4
    alt && (value = value[5:end])
    ctrl = startswith(value, "ctrl+") && ncodeunits(value) > 5
    ctrl && (value = value[6:end])
    shift = startswith(value, "shift+") && ncodeunits(value) > 6
    shift && (value = value[7:end])
    return (value, alt, ctrl, shift)
end

"""
    _keybinding_preferences() -> Dict{String, String}

Return a copy of the key bindings persisted with [`set_keybinding`](@ref) and
[`delete_keybinding`](@ref), keyed by the encoded binding. Entries whose value is not a
string are dropped.
"""
function _keybinding_preferences()
    stored = @load_preference(_KEYBINDINGS_PREFERENCE, nothing)
    stored isa AbstractDict || return Dict{String, String}()
    return Dict{String, String}(String(k) => v for (k, v) in stored if v isa AbstractString)
end

"""
    _store_keybinding!(kb::Tuple{String, Bool, Bool, Bool}, value::String) -> Nothing

Persist `value`, an action name or [`_DELETED_BINDING`](@ref), for the binding `kb` in the
preference `"keybindings"`.

# Arguments

- `kb::Tuple{String, Bool, Bool, Bool}`: Key value and ALT, CTRL, and SHIFT flags.
- `value::String`: Value to store.
"""
function _store_keybinding!(kb::Tuple{String, Bool, Bool, Bool}, value::String)
    stored = _keybinding_preferences()
    stored[_encode_binding(kb)] = value
    @set_preferences!(_KEYBINDINGS_PREFERENCE => stored)
    return nothing
end

"""
    _load_keybindings!() -> Nothing

Apply the key bindings persisted in the preference `"keybindings"` to `_KEYBINDINGS`. An
entry with the value [`_DELETED_BINDING`](@ref) removes the binding. The entries with an
unknown action are skipped, and one warning lists them, so that an old preference never
breaks the package initialization.
"""
function _load_keybindings!()
    stored = @load_preference(_KEYBINDINGS_PREFERENCE, nothing)
    isnothing(stored) && return nothing

    if !(stored isa AbstractDict)
        @warn "The preference \"$_KEYBINDINGS_PREFERENCE\" must be a table. It was ignored."
        return nothing
    end

    skipped = String[]

    for (encoded, value) in stored
        kb = _decode_binding(String(encoded))

        if value == _DELETED_BINDING
            delete!(_KEYBINDINGS, kb)
        elseif (value isa AbstractString) && (Symbol(value) in _ACTIONS)
            _KEYBINDINGS[kb] = Symbol(value)
        else
            push!(skipped, "$encoded => $value")
        end
    end

    if !isempty(skipped)
        sort!(skipped)
        @warn(
            "The preference \"$_KEYBINDINGS_PREFERENCE\" has unknown actions, which were " *
                "ignored: " * join(skipped, ", ") * "."
        )
    end

    _keybindings_changed!()

    return nothing
end

# Short names of the special keys, used wherever a key binding is shown to the user.
const _KEY_NAMES = Dict{String, String}(
    " " => "Space",
    "<backspace>" => "Bksp",
    "<delete>" => "Del",
    "<down>" => "↓",
    "<end>" => "End",
    "<enter>" => "Enter",
    "<eot>" => "Ctrl-D",
    "<esc>" => "Esc",
    "<home>" => "Home",
    "<left>" => "←",
    "<pagedown>" => "PgDn",
    "<pageup>" => "PgUp",
    "<right>" => "→",
    "<shiftin>" => "Ctrl-U",
    "<tab>" => "Tab",
    "<up>" => "↑",
    "<wheel_up>" => "Wheel↑",
    "<wheel_down>" => "Wheel↓",
    "<wheel_left>" => "Wheel←",
    "<wheel_right>" => "Wheel→",
    "<mouse_press>" => "Click",
)

"""
    _pretty_key(kb::Tuple{String, Bool, Bool, Bool}) -> String

Return a short human-readable name for the key binding `kb`, such as `Alt-↑` or `Ctrl-D`.

Special keys without a dedicated short name, such as the function keys, are shown without
their angle brackets.

# Arguments

- `kb::Tuple{String, Bool, Bool, Bool}`: Key value and ALT, CTRL, and SHIFT flags.
"""
function _pretty_key(kb::Tuple{String, Bool, Bool, Bool})
    value = kb[1]
    key = get(_KEY_NAMES, value, nothing)

    if isnothing(key)
        is_special =
            (ncodeunits(value) > 2) && startswith(value, '<') && endswith(value, '>')
        key = is_special ? value[2:(end - 1)] : value
    end

    # The CTRL combinations with a letter are always reported in lowercase.
    kb[3] && (length(key) == 1) && (key = uppercase(key))

    kb[4] && (key = "Shift-" * key)
    kb[3] && (key = "Ctrl-" * key)
    kb[2] && (key = "Alt-" * key)

    return key
end

"""
    _primary_key(action::Symbol) -> Union{Nothing, String}

Return the shortest human-readable name among the keys bound to `action`, or `nothing` if
the action is unbound.

# Arguments

- `action::Symbol`: Pager action.
"""
function _primary_key(action::Symbol)
    names = _action_keys(action)
    return isempty(names) ? nothing : first(names)
end

"""
    delete_keybinding(key::String; alt::Bool = false, ctrl::Bool = false,
        shift::Bool = false, persist::Bool = false) -> Nothing

Delete the keybinding `key`. The modifier keys can be selected using the keywords `alt`,
`ctrl`, and `shift`. If `persist` is `true`, the deletion is stored in the preference
`"keybindings"` and applied at every session start.

For more information about how to specify `key`, see [`set_keybinding`](@ref).

# Arguments

- `key::String`: Key value whose binding is deleted.

# Keywords

- `alt::Bool`: Select a binding that requires ALT.
    (**Default**: `false`)
- `ctrl::Bool`: Select a binding that requires CTRL.
    (**Default**: `false`)
- `shift::Bool`: Select a binding that requires SHIFT.
    (**Default**: `false`)
- `persist::Bool`: Store the deletion with **Preferences.jl**.
    (**Default**: `false`)
"""
function delete_keybinding(
    key::String;
    alt::Bool = false,
    ctrl::Bool = false,
    shift::Bool = false,
    persist::Bool = false,
)
    kb = (key, alt, ctrl, shift)
    delete!(_KEYBINDINGS, kb)
    persist && _store_keybinding!(kb, _DELETED_BINDING)
    _keybindings_changed!()
    return nothing
end

"""
    _apply_mode_keybindings!(get_preference::F = _get_preference) -> Nothing where
        {F <: Function}

Apply the key bindings that depend on the `pager_mode` preference to `_KEYBINDINGS`.

# Arguments

- `get_preference::F`: Callable preference getter used to read `pager_mode`.
    (**Default**: `_get_preference`)
"""
function _apply_mode_keybindings!(get_preference::F = _get_preference) where {F <: Function}
    if get_preference("pager_mode") == "vi"
        _KEYBINDINGS[("<eot>", false, false, false)] = :halfpagedown
        _KEYBINDINGS[("<shiftin>", false, false, false)] = :halfpageup
    else
        _KEYBINDINGS[("<eot>", false, false, false)] = :quit_eot

        # The vi mode also binds CTRL-U, which has no default binding. Switching back must
        # remove it, unless the user has meanwhile reassigned the key to another action.
        shiftin_key = ("<shiftin>", false, false, false)

        if get(_KEYBINDINGS, shiftin_key, nothing) === :halfpageup
            delete!(_KEYBINDINGS, shiftin_key)
        end
    end

    _keybindings_changed!()

    return nothing
end

"""
    reset_keybindings(; persist::Bool = false) -> Nothing

Reset the key bindings to the original ones, which are the defaults, the bindings of the
preference `"pager_mode"`, and the bindings persisted in the preference `"keybindings"`. If
`persist` is `true`, the persisted bindings are dropped first, so that only the defaults and
the mode bindings remain.

# Keywords

- `persist::Bool`: Drop the key bindings persisted with **Preferences.jl**.
    (**Default**: `false`)
"""
function reset_keybindings(; persist::Bool = false)
    persist && @delete_preferences!(_KEYBINDINGS_PREFERENCE)

    empty!(_KEYBINDINGS)
    merge!(_KEYBINDINGS, _DEFAULT_KEYBINDINGS)

    # Key bindings that depend on the mode.
    _apply_mode_keybindings!()

    # The persisted bindings are part of the session defaults. Otherwise, a reset after a
    # persisted change would silently drop the stored bindings until the next session.
    _load_keybindings!()

    return nothing
end

"""
    set_keybinding(key::String, action::Symbol; alt::Bool = false,
        ctrl::Bool = false, shift::Bool = false, persist::Bool = false) -> Nothing

Set key binding `key` to the action `action`. The modifier keys can be selected using the
keywords `alt`, `ctrl`, and `shift`.

`key` can contain a character or one of the following special key names:

    "<up>", "<down>", "<right>", "<left>", "<home>", "<end>", "<F1>", "<F2>",
    "<F3>", "<F4>", "<F5>", "<F6>", "<F7>", "<F8>", "<F9>", "<F10>", "<F11>",
    "<F12>", "<keypad_dot>", "<keypad_enter>", "<keypad_asterisk>",
    "<keypad_plus>", "<keypad_minus>", "<keypad_slash>", "<keypad_equal>",
    "<keypad_0>", "<keypad_1>", "<keypad_2>", "<keypad_3>", "<keypad_4>",
    "<keypad_5>", "<keypad_6>", "<keypad_7>", "<keypad_8>", "<keypad_9>",
    "<delete>", "<pageup>", "<pagedown>", "<tab>", "<enter>", "<esc>",
    "<backspace>", "<eot>", "<shiftin>", "<wheel_up>", "<wheel_down>",
    "<wheel_left>", "<wheel_right>", "<mouse_press>", "<mouse_press_middle>",
    "<mouse_press_right>", "<mouse_release>", "<mouse_drag>"

`"<eot>"` is CTRL-D and `"<shiftin>"` is CTRL-U. Every other CTRL combination with a letter must
be selected with the keyword `ctrl` instead, for example
`set_keybinding("a", :quit; ctrl = true)`. The mouse keys are reported when the preference
`"mouse"` is enabled.

`action` can be one of the following symbols:

    $(_actions_docstring())

Any other action throws an `ArgumentError`.

If `persist` is `true`, the binding is stored in the preference `"keybindings"` and applied
at every session start, after the bindings of the preference `"pager_mode"`. The stored
bindings are dropped with `reset_keybindings(; persist = true)` or
[`drop_all_preferences!`](@ref).

# Arguments

- `key::String`: Key value whose binding is set.
- `action::Symbol`: Pager action assigned to the key.

# Keywords

- `alt::Bool`: Require ALT for the binding.
    (**Default**: `false`)
- `ctrl::Bool`: Require CTRL for the binding.
    (**Default**: `false`)
- `shift::Bool`: Require SHIFT for the binding.
    (**Default**: `false`)
- `persist::Bool`: Store the binding with **Preferences.jl**.
    (**Default**: `false`)
"""
function set_keybinding(
    key::String,
    action::Symbol;
    alt::Bool = false,
    ctrl::Bool = false,
    shift::Bool = false,
    persist::Bool = false,
)
    _check_action(action)
    kb = (key, alt, ctrl, shift)
    _KEYBINDINGS[kb] = action
    persist && _store_keybinding!(kb, String(action))
    _keybindings_changed!()
    return nothing
end
