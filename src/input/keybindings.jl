# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   This file contains functions related to key bindings.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Dictionary with the default bindings.
const _default_keybindings = Dict{Tuple{Union{Symbol, String}, Bool, Bool, Bool}, Symbol}(
    ("q",          false, false, false) => :quit,
    ("?",          false, false, false) => :help,
    ("<up>",       false, false, false) => :up,
    ("k",          false, false, false) => :up,
    ("<down>",     false, false, false) => :down,
    ("j",          false, false, false) => :down,
    ("<enter>",    false, false, false) => :down,
    ("<left>",     false, false, false) => :left,
    ("h",          false, false, false) => :left,
    ("<right>",    false, false, false) => :right,
    ("l",          false, false, false) => :right,
    ("<up>",       false, false, true ) => :fastup,
    ("<down>",     false, false, true ) => :fastdown,
    ("<left>",     false, false, true ) => :fastleft,
    ("<right>",    false, false, true ) => :fastright,
    ("<left>",     true,  false, false) => :bol,
    ("0",          false, false, false) => :bol,
    ("<right>",    true,  false, false) => :eol,
    ("\$",         false, false, false) => :eol,
    ("u",          false, false, false) => :halfpageup,
    ("d",          false, false, false) => :halfpagedown,
    ("<pageup>",   false, false, false) => :pageup,
    ("b",          false, false, false) => :pageup,
    ("<pagedown>", false, false, false) => :pagedown,
    (" ",          false, false, false) => :pagedown,
    ("<home>",     false, false, false) => :home,
    ("<up>",       true,  false, false) => :home,
    ("g",          false, false, false) => :home,
    ("<",          false, false, false) => :home,
    ("<end>",      false, false, false) => :end,
    ("<down>",     true,  false, false) => :end,
    ("G",          false, false, false) => :end,
    (">",          false, false, false) => :end,
    ("/",          false, false, false) => :search,
    ("n",          false, false, false) => :next_match,
    ("N",          false, false, false) => :previous_match,
    ("<esc>",      false, false, false) => :quit_search,
    ("f",          false, false, false) => :change_freeze,
    ("<eot>",      false, false, false) => :quit_eot,
    ("r",          false, false, false) => :toggle_ruler,
    ("t",          false, false, false) => :change_title_rows,
)

# Dictionary with the current keybindings, it is initialized here with the
# default values to improve startup time.
const _keybindings = copy(_default_keybindings)

"""
    delete_keybinding(key::Union{Char, Symbol}; alt::Bool = false, ctrl::Bool = false, shift::Bool = false)

Delete the keybinding `key`. The modifiers keys can be selected using the
keywords `alt`, `ctrl`, and `shift`.

For more information about how specify `key` see [`set_keybinding`](@ref).
"""
function delete_keybinding(
    key::String;
    alt::Bool = false,
    ctrl::Bool = false,
    shift::Bool = false
)
    dict_key = (key isa Char ? string(key) : key, alt, ctrl, shift)
    delete!(_keybindings, dict_key)
    return nothing
end

"""
    reset_keybindings()

Reset key bindings to the original ones.
"""
function reset_keybindings()
    empty!(_keybindings)
    merge!(_keybindings, _default_keybindings)

    # Key bindings that depends on the mode.
    if get(ENV, "PAGER_MODE", "default") == "vi"
        _keybindings[("<eot>",     false, false, false)] = :halfpagedown
        _keybindings[("<shiftin>", false, false, false)] = :halfpageup
    else
        _keybindings[("<eot>", false, false, false)] = :quit_eot
    end

    return nothing
end

"""
    set_keybinding(key::Union{Char, Symbol}, action::Symbol; alt::Bool = false, ctrl::Bool = false, shift::Bool = false)

Set key binding `key` to the action `action`. The modifiers keys can be selected
using the keywords `alt`, `ctrl`, and `shift`.

`key` can be a `Char` or a `Symbol` indicating one of the following special
keys:

    "<up>", "<down>", "<right>", "<left>", "<home>", "<end>", "<F1>", "<F2>",
    "<F3>", "<F4>", "<F5>", "<F6>", "<F7>", "<F8>", "<F9>", "<F10>", "<F11>",
    "<F12>", "<keypad_dot>", "<keypad_enter>", "<keypad_asterisk>",
    "<keypad_plus>", "<keypad_minus>", "<keypad_slash>", "<keypad_equal>",
    "<keypad_0>", "<keypad_1>", "<keypad_2>", "<keypad_3>", "<keypad_4>",
    "<keypad_5>", "<keypad_6>", "<keypad_7>", "<keypad_8>", "<keypad_9>",
    "<delete>", "<pageup>", "<pagedown>", "<tab>"

`action` can be one of the following symbols:

    :quit, :help, :up, :down, :left, :right, :fastup, :fastdown, :fastleft,
    :fastright :bol, :eol, :pageup, :pagedown, :home, :end
"""
function set_keybinding(
    key::String,
    action::Symbol;
    alt::Bool = false,
    ctrl::Bool = false,
    shift::Bool = false
)
    dict_key = (key isa Char ? string(key) : key, alt, ctrl, shift)
    _keybindings[dict_key] = action
    return nothing
end

