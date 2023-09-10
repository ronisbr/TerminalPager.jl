# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions related to help screen.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _help!(pargerd::Pager) -> Nothing

Open a new pager with the help.
"""
function _help!(pagerd::Pager)
    # Unpack values.
    term = pagerd.term
    buf  = pagerd.buf

    if get(term.out_stream, :color, true)::Bool
        _b  = _CRAYON_B
        _c  = _CRAYON_C
        _cb = _CRAYON_CB
        _d  = _CRAYON_RESET
        _g  = _CRAYON_G
        _r  = _CRAYON_R
        _y  = _CRAYON_Y
    else
        _b = ""
        _c = ""
        _d = ""
        _g = ""
        _r = ""
        _y = ""
    end

    # Get the current key bindings.

    # General
    kb_help         = _getkb(:help)
    kb_quit         = _getkb(:quit)
    kb_quit_eot     = _getkb(:quit_eot)
    kb_toggle_ruler = _getkb(:toggle_ruler)

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
    kb_hpageup   = _getkb(:halfpageup)
    kb_hpagedown = _getkb(:halfpagedown)
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
    kb_change_freeze     = _getkb(:change_freeze)
    kb_change_title_rows = _getkb(:change_title_rows)

    # Visual mode
    kb_toggle_visual_mode      = _getkb(:toggle_visual_mode)
    kb_select_visual_mode_line = _getkb(:select_visual_mode_line)
    kb_yank                    = _getkb(:yank)

    help_str =
"""
  $(_cb)TerminalPager.jl $(PKG_VERSION)$(_d)

  The pager can execute some type of actions as shown in the following. The key bindings of
  each actions can be changed using the function $(_c)set_keybinding$(_d).

  Some actions are only available if a feature is enabled. The set of enabled features can
  be selected using the keyword $(_c)features$(_d) when calling the pager.

$(_b)                                          General$(_d)
$(_y)  :help$(_d)
    Show this screen.
$(_c)    Keybindings: $(kb_help)$(_d)
$(_g)    This action requires the feature :help.
$(_y)  :quit$(_d)
    Quit the pager.
$(_c)    Keybindings: $(kb_quit)$(_d)
$(_y)  :quit_eot$(_d)
    This is an special quit action design for the $(_c)END OF TRANSMISSION (^D)$(_d)
    keycode. If we are in a search operation, then it quits the search. If not, then it
    quits the pager.
$(_c)    Keybindings: $(kb_quit_eot)$(_d)
$(_y)  :toggle_ruler$(_d)
    Toggle the vertical ruler.
$(_c)    Keybindings: $(kb_toggle_ruler)$(_d)

$(_b)                                          Movement$(_d)
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
$(_y)  :halfpageup$(_d)
    Move the display half page up (a page has the same size of the view).
$(_c)    Keybindings: $(kb_hpageup)$(_d)
$(_y)  :halfpagedown$(_d)
    Move the display half page down (a page has the same size of the view).
$(_c)    Keybindings: $(kb_hpagedown)$(_d)
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

$(_b)                                         Searching$(_d)
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

$(_b)                                       Freezing Data$(_d)
$(_g)  These actions requires the feature :change_freeze.
$(_y)  :change_freeze$(_d)
    Two values will be requested in the command line. The first is the number of columns and
    the second is the number of rows that will be frozen. If the value is equal or lower
    than 0, then no row or column will be frozen.
$(_c)    Keybindings: $(kb_change_freeze)$(_d)
$(_y)  :change_title_rows$(_d)
    Define the number of rows within the frozen rows that will be considered as titles. In
    this case, these rows will not scroll horizontally.
$(_c)    Keybindings: $(kb_change_title_rows)$(_d)

$(_b)                                        Visual Mode$(_d)
$(_g)  These actions requires the feature :visual_mode.
$(_y)  :toggle_visual_mode$(_d)
    Toggle visual mode, where a visual line is displayed on the screen. In this mode, the
    movements are slight modified to be relative to the visual line.
$(_c)    Keybindings: $(kb_toggle_visual_mode)$(_d)
$(_y)  :select_visual_mode_line$(_d)
    Mark the current visual line. Notice if the line is already marked, it will be unmarked.
    All the lines are unmarked when we exit the visual mode.
$(_c)    Keybindings: $(kb_select_visual_mode_line)$(_d)
$(_y)  :yank$(_d)
    Copy (yank) the selected and current visual lines to the system clipboard.
$(_c)    Keybindings: $(kb_yank)$(_d)
"""

    _pager!(pagerd.term, help_str; hashelp = false, has_visual_mode = false)

    return nothing
end

############################################################################################
#                                    Private Functions
############################################################################################

function _getkb(action::Symbol)
    kb = [_kbtostr(k) for (k, v) in _keybindings if v == action]
    num_kb = length(kb)

    str = ""

    @inbounds for i = 1:num_kb
        str *= kb[i]
        i != num_kb && (str *= ", ")
    end

    return str
end

function _kbtostr(kb::Tuple{String, Bool, Bool, Bool})
    str = kb[1] == " " ? "space" : string(kb[1])

    kb[2] && (str = "ALT " * str)
    kb[3] && (str = "CTRL " * str)
    kb[4] && (str = "SHIFT " * str)

    return str
end
