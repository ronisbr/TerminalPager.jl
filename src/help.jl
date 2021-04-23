# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to help screen.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _help!(pargerd::Pager)

Open a new pager with the help.

"""
function _help!(pagerd::Pager)
    # Unpack values.
    @unpack term, buf = pagerd

    if get(term.out_stream, :color, true)::Bool
        _b  = string(crayon"bold")
        _d  = string(Crayon(reset = true))
        _cb = string(crayon"cyan bold")
        _c  = string(crayon"cyan")
        _g  = string(crayon"dark_gray")
        _r  = string(crayon"red bold")
        _y  = string(crayon"yellow bold")
    else
        _b = ""
        _d = ""
        _c = ""
        _g = ""
        _r = ""
        _y = ""
    end

    # Get the current key bindings.

    # General
    kb_help = _getkb(:help)
    kb_quit = _getkb(:quit)

    # Movement
    kb_up        = _getkb(:up)
    kb_down      = _getkb(:down)
    kb_left      = _getkb(:left)
    kb_right     = _getkb(:right)
    kb_fastup    = _getkb(:fastup)
    kb_fastdown  = _getkb(:fastdown)
    kb_fastleft  = _getkb(:fastleft)
    kb_fastright = _getkb(:fastright)
    kb_pageup    = _getkb(:pageup)
    kb_pagedown  = _getkb(:pagedown)
    kb_bol       = _getkb(:bol)
    kb_eol       = _getkb(:eol)
    kb_home      = _getkb(:home)
    kb_end       = _getkb(:end)

    # Searching
    kb_search         = _getkb(:search)
    kb_next_match     = _getkb(:next_match)
    kb_previous_match = _getkb(:previous_match)
    kb_quit_search    = _getkb(:quit_search)

    # Freezing data
    kb_change_freeze = _getkb(:change_freeze)

    help_str =
"""
  $(_cb)TerminalPager.jl $(PKG_VERSION)$(_d)

  The pager can execute some type of actions as shown in the following. The key
  bindings of each actions can be changed using the function $(_c)set_keybinding$(_d).

  Some actions are only available if a feature is enabled. The set of enabled
  features can be selected using the keyword $(_c)features$(_d) when calling the
  pager.

$(_b)                                     General$(_d)
$(_y)  :help$(_d)
    Show this screen.
$(_c)    Keybindings: $(kb_help)$(_d)
$(_g)    This action requires the feature :help.
$(_y)  :quit$(_d)
    Quit the pager.
$(_c)    Keybindings: $(kb_quit)$(_d)
$(_y)  :quit_eot$(_d)
    This is an special quit action design for the $(_c)END OF TRANSMISSION (^D)$(_d)
    keycode. If we are in a search operation, then it quits the search. If not,
    then it quits the pager.
$(_c)    Keybindings: $(kb_quit)$(_d)

$(_b)                                    Movement$(_d)
$(_y)  :up$(_d)
    Move the display one line up.
$(_c)    Keybindings: $(kb_up)$(_d)
$(_y)  :down$(_d)
    Move the display one line down.
$(_c)    Keybindings: $(kb_down)$(_d)
$(_y)  :left$(_d)
    Move the display one column to the left.
$(_c)    Keybindings: $(kb_left)$(_d)
$(_y)  :right$(_d)
    Move the display one column to the right.
$(_c)    Keybindings: $(kb_right)$(_d)
$(_y)  :fastup$(_d)
    Move the display five lines up.
$(_c)    Keybindings: $(kb_fastup)$(_d)
$(_y)  :fastdown$(_d)
    Move the display five lines down.
$(_c)    Keybindings: $(kb_fastdown)$(_d)
$(_y)  :fastleft$(_d)
    Move the display ten columns to the left.
$(_c)    Keybindings: $(kb_fastleft)$(_d)
$(_y)  :fastright$(_d)
    Move the display ten columns to the right.
$(_c)    Keybindings: $(kb_fastright)$(_d)
$(_y)  :pageup$(_d)
    Move the display one page up (a page has the same size of the view).
$(_c)    Keybindings: $(kb_pageup)$(_d)
$(_y)  :pagedown$(_d)
    Move the display one page down (a page has the same size of the view).
$(_c)    Keybindings: $(kb_pagedown)$(_d)
$(_y)  :bol$(_d)
    Move the display to the first column.
$(_c)    Keybindings: $(kb_bol)$(_d)
$(_y)  :eol$(_d)
    Move the display to show the last column.
$(_c)    Keybindings: $(kb_eol)$(_d)
$(_y)  :home$(_d)
    Move the display to the first line.
$(_c)    Keybindings: $(kb_home)$(_d)
$(_y)  :end$(_d)
    Move the display to show the last line.
$(_c)    Keybindings: $(kb_end)$(_d)

$(_b)                                   Searching$(_d)
$(_y)  :search$(_d)
    Request a regex in the command line and highlight all the matches.
$(_c)    Keybindings: $(kb_search)$(_d)
$(_y)  :next_match$(_d)
    Go to the next match of the search.
$(_c)    Keybindings: $(kb_next_match)$(_d)
$(_y)  :previous_match$(_d)
    Go to the previous match of the search.
$(_c)    Keybindings: $(kb_previous_match)$(_d)
$(_y)  :quit_search$(_d)
    Quit searching, removing all the highlights (only during search mode).
$(_c)    Keybindings: $(kb_quit_search)$(_d)

$(_b)                                 Freezing data$(_d)
$(_y)  :change_freeze$(_d)
    Two values will be requested in the command line. The first is the number of
    columns and the second is the number of rows that will be frozen. If the
    value is equal or lower than 0, then no row or column will be frozen.
$(_c)    Keybindings: $(kb_change_freeze)$(_d)
"""

    _pager!(pagerd.term, help_str; hashelp = false)

    return nothing
end

################################################################################
#                              Private functions
################################################################################

function _getkb(action::Symbol)
    kb = [_kbtostr(k) for (k, v) in _default_keybindings if v == action]
    num_kb = length(kb)

    str = ""

    @inbounds for i = 1:num_kb
        str *= kb[i]
        i != num_kb && (str *= ", ")
    end

    return str
end

function _kbtostr(kb::Tuple{Union{Symbol, String}, Bool, Bool, Bool})
    str = string(kb[1])

    kb[2] && (str = "ALT " * str)
    kb[3] && (str = "CTRL " * str)
    kb[4] && (str = "SHIFT " * str)

    return str
end
