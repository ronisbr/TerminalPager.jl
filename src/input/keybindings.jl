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
    delete!(_default_keybindings, dict_key)
    return nothing
end

"""
    reset_keybindings()

Reset key bindings to the original ones.

"""
function reset_keybindings()
    empty!(_default_keybindings)
    _default_keybindings[("q",       false, false, false)] = :quit
    _default_keybindings[("?",       false, false, false)] = :help
    _default_keybindings[(:up,       false, false, false)] = :up
    _default_keybindings[(:down,     false, false, false)] = :down
    _default_keybindings[(:left,     false, false, false)] = :left
    _default_keybindings[(:right,    false, false, false)] = :right
    _default_keybindings[(:up,       false, false, true )] = :fastup
    _default_keybindings[(:down,     false, false, true )] = :fastdown
    _default_keybindings[(:left,     false, false, true )] = :fastleft
    _default_keybindings[(:right,    false, false, true )] = :fastright
    _default_keybindings[(:left,     true,  false, false)] = :bol
    _default_keybindings[(:right,    true,  false, false)] = :eol
    _default_keybindings[(:pageup,   false, false, false)] = :pageup
    _default_keybindings[(:pagedown, false, false, false)] = :pagedown
    _default_keybindings[(:home,     false, false, false)] = :home
    _default_keybindings[(:end,      false, false, false)] = :end
    _default_keybindings[("/",       false, false, false)] = :search
    _default_keybindings[("n",       false, false, false)] = :next_match
    _default_keybindings[("N",       false, false, false)] = :previous_match
    _default_keybindings[(:esc,      false, false, false)] = :quit_search
    _default_keybindings[("f",       false, false, false)] = :change_freeze
end

# Call `reset_keybindings` to populate the keybindings.
reset_keybindings()

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
    _default_keybindings[dict_key] = action
    return nothing
end

