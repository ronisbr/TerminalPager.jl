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
    ("/", false, false, false) => :search,
    ("n", false, false, false) => :next_match,
    ("N", false, false, false) => :previous_match,
    ("<esc>", false, false, false) => :quit_search,
    # The raw mode delivers CTRL-C as a keystroke. Like in `less`, it cancels the current
    # operation instead of quitting the pager.
    ("c", false, true, false) => :quit_search,
    ("f", false, false, false) => :change_freeze,
    ("<eot>", false, false, false) => :quit_eot,
    ("r", false, false, false) => :toggle_ruler,
    ("s", false, false, false) => :toggle_scrollbar,
    ("t", false, false, false) => :change_title_rows,
    ("v", false, false, false) => :toggle_visual_mode,
    ("m", false, false, false) => :select_visual_mode_line,
    ("y", false, false, false) => :yank,
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
    best = nothing

    for (kb, bound_action) in _KEYBINDINGS
        bound_action === action || continue
        name = _pretty_key(kb)

        if isnothing(best) || ((textwidth(name), name) < (textwidth(best), best))
            best = name
        end
    end

    return best
end

"""
    delete_keybinding(key::String; alt::Bool = false, ctrl::Bool = false,
        shift::Bool = false) -> Nothing

Delete the keybinding `key`. The modifier keys can be selected using the keywords `alt`,
`ctrl`, and `shift`.

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
"""
function delete_keybinding(
    key::String; alt::Bool = false, ctrl::Bool = false, shift::Bool = false
)
    delete!(_KEYBINDINGS, (key, alt, ctrl, shift))
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
    reset_keybindings() -> Nothing

Reset the key bindings to the original ones.
"""
function reset_keybindings()
    empty!(_KEYBINDINGS)
    merge!(_KEYBINDINGS, _DEFAULT_KEYBINDINGS)

    # Key bindings that depend on the mode.
    _apply_mode_keybindings!()

    return nothing
end

"""
    set_keybinding(key::String, action::Symbol; alt::Bool = false,
        ctrl::Bool = false, shift::Bool = false) -> Nothing

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

    :quit, :quit_eot, :help, :up, :down, :left, :right, :fastup, :fastdown,
    :fastleft, :fastright, :bol, :eol, :pageup, :pagedown, :halfpageup,
    :halfpagedown, :home, :end, :wheel_up, :wheel_down, :goto_line, :search,
    :next_match, :previous_match, :quit_search, :change_freeze,
    :change_title_rows, :toggle_ruler, :toggle_scrollbar, :toggle_visual_mode,
    :select_visual_mode_line, :mouse_select, :yank

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
"""
function set_keybinding(
    key::String, action::Symbol; alt::Bool = false, ctrl::Bool = false, shift::Bool = false
)
    _KEYBINDINGS[(key, alt, ctrl, shift)] = action
    _keybindings_changed!()
    return nothing
end
