# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   This file contains functions related to keybindings.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    delete_keybinding(key::Union{Char, Symbol}; alt::Bool = false, ctrl::Bool = false, shift::Bool = false)

Delete the keybinding `key`. The modifiers keys can be selected using the
keywords `alt`, `ctrl`, and `shift`.

For more information about how specify `key` see [`set_keybinding`](@ref).

"""
function delete_keybinding(key::Union{Char, Symbol};
                           alt::Bool = false,
                           ctrl::Bool = false,
                           shift::Bool = false)
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
    _keybindings[("q",       false, false, false)] = :quit
    _keybindings[("?",       false, false, false)] = :help
    _keybindings[(:up,       false, false, false)] = :up
    _keybindings[("k",       false, false, false)] = :up
    _keybindings[(:down,     false, false, false)] = :down
    _keybindings[("j",       false, false, false)] = :down
    _keybindings[(:left,     false, false, false)] = :left
    _keybindings[("h",       false, false, false)] = :left
    _keybindings[(:right,    false, false, false)] = :right
    _keybindings[("l",       false, false, false)] = :right
    _keybindings[(:up,       false, false, true )] = :fastup
    _keybindings[(:down,     false, false, true )] = :fastdown
    _keybindings[(:left,     false, false, true )] = :fastleft
    _keybindings[(:right,    false, false, true )] = :fastright
    _keybindings[(:left,     true,  false, false)] = :bol
    _keybindings[("0",       false, false, false)] = :bol
    _keybindings[(:right,    true,  false, false)] = :eol
    _keybindings[("\$",      false, false, false)] = :eol
    _keybindings[(:pageup,   false, false, false)] = :pageup
    _keybindings[(:pagedown, false, false, false)] = :pagedown
    _keybindings[(:home,     false, false, false)] = :home
    _keybindings[("g",       false, false, false)] = :home
    _keybindings[(:end,      false, false, false)] = :end
    _keybindings[("G",       false, false, false)] = :end
    _keybindings[("/",       false, false, false)] = :search
    _keybindings[("n",       false, false, false)] = :next_match
    _keybindings[("N",       false, false, false)] = :previous_match
    _keybindings[(:esc,      false, false, false)] = :quit_search
    _keybindings[("f",       false, false, false)] = :change_freeze

    # Key bindings that depends on the mode.
    if get(ENV, "PAGER_MODE", "default") == "vi"
        _keybindings[(:eot,     false, false, false)] = :halfpagedown
        _keybindings[(:shiftin, false, false, false)] = :halfpageup
    else
        _keybindings[(:eot, false, false, false)] = :quit_eot
    end
end

"""
    set_keybinding(key::Union{Char, Symbol}, action::Symbol; alt::Bool = false, ctrl::Bool = false, shift::Bool = false)

Set key binding `key` to the action `action`. The modifiers keys can be selected
using the keywords `alt`, `ctrl`, and `shift`.

`key` can be a `Char` or a `Symbol` indicating one of the following special
keys:

    :up, :down, :right, :left, :home, :end, :F1, :F2, :F3, :F4, :F5, :F6, :F7,
    :F8, :F9, :F10, :F11, :F12, :keypad_dot, :keypad_enter, :keypad_asterisk,
    :keypad_plus, :keypad_minus, :keypad_slash, :keypad_equal, :keypad_0,
    :keypad_1, :keypad_2, :keypad_3, :keypad_4, :keypad_5, :keypad_6, :keypad_7,
    :keypad_8, :keypad_9, :delete, :pageup, :pagedown, :tab,

`action` can be one of the following symbols:

    :quit, :help, :up, :down, :left, :right, :fastup, :fastdown, :fastleft,
    :fastright :bol, :eol, :pageup, :pagedown, :home, :end

"""
function set_keybinding(key::Union{Char, Symbol}, action::Symbol;
                        alt::Bool = false,
                        ctrl::Bool = false,
                        shift::Bool = false)
    dict_key = (key isa Char ? string(key) : key, alt, ctrl, shift)
    _keybindings[dict_key] = action
    return nothing
end

