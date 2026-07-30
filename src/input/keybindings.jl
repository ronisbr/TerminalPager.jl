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
    ("/", false, false, false) => :search,
    ("n", false, false, false) => :next_match,
    ("N", false, false, false) => :previous_match,
    ("<esc>", false, false, false) => :quit_search,
    ("f", false, false, false) => :change_freeze,
    ("<eot>", false, false, false) => :quit_eot,
    ("r", false, false, false) => :toggle_ruler,
    ("t", false, false, false) => :change_title_rows,
    ("v", false, false, false) => :toggle_visual_mode,
    ("m", false, false, false) => :select_visual_mode_line,
    ("y", false, false, false) => :yank,
)

# Dictionary with the current keybindings, it is initialized here with the default values to
# improve startup time.
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

"""
    delete_keybinding(key::String; alt::Bool = false, ctrl::Bool = false,
        shift::Bool = false) -> Nothing

Delete the keybinding `key`. The modifiers keys can be selected using the keywords `alt`,
`ctrl`, and `shift`.

For more information about how specify `key` see [`set_keybinding`](@ref).

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
    end

    _keybindings_changed!()

    return nothing
end

"""
    reset_keybindings() -> Nothing

Reset key bindings to the original ones.
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

Set key binding `key` to the action `action`. The modifiers keys can be selected using the
keywords `alt`, `ctrl`, and `shift`.

`key` can contain a character or one of the following special key names:

    "<up>", "<down>", "<right>", "<left>", "<home>", "<end>", "<F1>", "<F2>",
    "<F3>", "<F4>", "<F5>", "<F6>", "<F7>", "<F8>", "<F9>", "<F10>", "<F11>",
    "<F12>", "<keypad_dot>", "<keypad_enter>", "<keypad_asterisk>",
    "<keypad_plus>", "<keypad_minus>", "<keypad_slash>", "<keypad_equal>",
    "<keypad_0>", "<keypad_1>", "<keypad_2>", "<keypad_3>", "<keypad_4>",
    "<keypad_5>", "<keypad_6>", "<keypad_7>", "<keypad_8>", "<keypad_9>",
    "<delete>", "<pageup>", "<pagedown>", "<tab>", "<enter>", "<esc>",
    "<backspace>", "<eot>", "<shiftin>"

`"<eot>"` is CTRL-D and `"<shiftin>"` is CTRL-U. Every other CTRL combination with a letter must
be selected with the keyword `ctrl` instead, for example
`set_keybinding("a", :quit; ctrl = true)`.

`action` can be one of the following symbols:

    :quit, :quit_eot, :help, :up, :down, :left, :right, :fastup, :fastdown,
    :fastleft, :fastright, :bol, :eol, :pageup, :pagedown, :halfpageup,
    :halfpagedown, :home, :end, :search, :next_match, :previous_match,
    :quit_search, :change_freeze, :change_title_rows, :toggle_ruler,
    :toggle_visual_mode, :select_visual_mode_line, :yank

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
