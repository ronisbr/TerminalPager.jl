## Description #############################################################################
#
# Functions related to help screen.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The help screen only depends on the keybindings. Hence, everything derived from them is
# cached and rebuilt when `_KEYBINDINGS_GENERATION` changes.
const _ACTION_KEYBINDINGS = Dict{Symbol, String}()
const _ACTION_KEYBINDINGS_GENERATION = Ref(-1)

# One cache entry per color support, holding the generation it was built for, the help text,
# and its prepared layout.
const _HELP_CACHE = Dict{Bool, Tuple{Int, String, TextViewLayout}}()

"""
    _help!(pagerd::Pager) -> Nothing

Open a new pager with the help.

# Arguments

- `pagerd::Pager`: Parent pager state whose terminal and input are reused.
"""
function _help!(pagerd::Pager)
    help_str, help_layout = _help_screen(get(pagerd.term.out_stream, :color, true)::Bool)

    _pager!(
        pagerd.term,
        help_str;
        display_config = pagerd.display_config,
        hashelp = false,
        has_visual_mode = false,
        input = pagerd.input,
        text_layout = help_layout,
        manage_cursor_key_mode = false,
    )

    return nothing
end

"""
    _help_screen(use_color::Bool) -> Tuple{String, TextViewLayout}

Return the help text and its prepared layout, rebuilding them only when the keybindings change.

# Arguments

- `use_color::Bool`: Decorate the help screen with ANSI escape sequences.
"""
function _help_screen(use_color::Bool)
    generation = _KEYBINDINGS_GENERATION[]
    cached = get(_HELP_CACHE, use_color, nothing)

    if !isnothing(cached) && (cached[1] == generation)
        return cached[2], cached[3]
    end

    help_str = _help_string(use_color)
    help_layout = TextViewLayout(split(help_str, '\n'))
    _HELP_CACHE[use_color] = (generation, help_str, help_layout)

    return help_str, help_layout
end

"""
    _pkg_version() -> VersionNumber

Return the version of this package.

Notice that this must not be stored in a constant. `pkgversion` evaluated while the package is
precompiled captures the version that was current at that moment, so the help screen kept
showing a stale one after a new version was released.
"""
_pkg_version() = pkgversion(@__MODULE__)

"""
    _help_string(use_color::Bool) -> String

Assemble the pager help screen from the current key bindings.

# Arguments

- `use_color::Bool`: Decorate the help screen with ANSI escape sequences.
"""
function _help_string(use_color::Bool)
    if use_color
        _b = _CRAYON_B
        _c = _CRAYON_C
        _cb = _CRAYON_CB
        _d = _CRAYON_RESET
        _g = _CRAYON_G
        _y = _CRAYON_Y
    else
        _b = ""
        _c = ""
        _cb = ""
        _d = ""
        _g = ""
        _y = ""
    end

    # Get the current key bindings.

    # Collect general keybindings.
    kb_help = _getkb(:help)
    kb_quit = _getkb(:quit)
    kb_quit_eot = _getkb(:quit_eot)
    kb_toggle_ruler = _getkb(:toggle_ruler)

    # Collect movement keybindings.
    kb_up = _getkb(:up)
    kb_down = _getkb(:down)
    kb_left = _getkb(:left)
    kb_right = _getkb(:right)
    kb_fastup = _getkb(:fastup)
    kb_fastdown = _getkb(:fastdown)
    kb_fastleft = _getkb(:fastleft)
    kb_fastright = _getkb(:fastright)
    kb_pageup = _getkb(:pageup)
    kb_pagedown = _getkb(:pagedown)
    kb_hpageup = _getkb(:halfpageup)
    kb_hpagedown = _getkb(:halfpagedown)
    kb_bol = _getkb(:bol)
    kb_eol = _getkb(:eol)
    kb_home = _getkb(:home)
    kb_end = _getkb(:end)

    # Collect search keybindings.
    kb_search = _getkb(:search)
    kb_next_match = _getkb(:next_match)
    kb_previous_match = _getkb(:previous_match)
    kb_quit_search = _getkb(:quit_search)

    # Collect data-freezing keybindings.
    kb_change_freeze = _getkb(:change_freeze)
    kb_change_title_rows = _getkb(:change_title_rows)

    # Collect visual-mode keybindings.
    kb_toggle_visual_mode = _getkb(:toggle_visual_mode)
    kb_select_visual_mode_line = _getkb(:select_visual_mode_line)
    kb_yank = _getkb(:yank)

    help_str = """
                 $(_cb)TerminalPager.jl $(_pkg_version())$(_d)

                 The pager can execute several types of actions, as shown below. The key
                 bindings of each action can be changed using the function
                 $(_c)set_keybinding$(_d).

                 Some actions are only available if a feature is enabled. The enabled
                 features depend on how the pager was called and on the object being
                 displayed.

               $(_b)                                          General$(_d)
               $(_y)  :help$(_d)
                   Show this screen.
               $(_c)    Keybindings: $(kb_help)$(_d)
               $(_g)    This action requires the feature :help.
               $(_y)  :quit$(_d)
                   Quit the pager.
               $(_c)    Keybindings: $(kb_quit)$(_d)
               $(_y)  :quit_eot$(_d)
                   This is a special quit action designed for the
                   $(_c)END OF TRANSMISSION (^D)$(_d) keycode. If we are in a search
                   operation, then it quits the search. If not, then it
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
                   Move the display one page up (a page has the same size as the view).
               $(_c)    Keybindings: $(kb_pageup)$(_d)
               $(_y)  :pagedown$(_d)
                   Move the display one page down (a page has the same size as the view).
               $(_c)    Keybindings: $(kb_pagedown)$(_d)
               $(_y)  :halfpageup$(_d)
                   Move the display half page up (a page has the same size as the view).
               $(_c)    Keybindings: $(kb_hpageup)$(_d)
               $(_y)  :halfpagedown$(_d)
                   Move the display half page down (a page has the same size as the view).
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
               $(_g)  These actions require the feature :change_freeze.
               $(_y)  :change_freeze$(_d)
                   Two values will be requested in the command line. The first is the
                   number of rows and the second is the number of columns that will be
                   frozen. If a value is equal to or lower than 0, then no row or column
                   will be frozen.
               $(_c)    Keybindings: $(kb_change_freeze)$(_d)
               $(_y)  :change_title_rows$(_d)
                   Define the number of rows within the frozen rows that will be
                   considered as titles. In
                   this case, these rows will not scroll horizontally.
               $(_c)    Keybindings: $(kb_change_title_rows)$(_d)

               $(_b)                                        Visual Mode$(_d)
               $(_g)  These actions require the feature :visual_mode.
               $(_y)  :toggle_visual_mode$(_d)
                   Toggle visual mode, where a visual line is displayed on the screen.
                   In this mode, the
                   movements are slightly modified to be relative to the visual line.
               $(_c)    Keybindings: $(kb_toggle_visual_mode)$(_d)
               $(_y)  :select_visual_mode_line$(_d)
                   Mark the current visual line. Notice if the line is already marked,
                   it will be unmarked.
                   All the lines are unmarked when we exit the visual mode.
               $(_c)    Keybindings: $(kb_select_visual_mode_line)$(_d)
               $(_y)  :yank$(_d)
                   Copy (yank) the selected and current visual lines to the system
                   clipboard.
               $(_c)    Keybindings: $(kb_yank)$(_d)
               """

    return help_str
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _getkb(action::Symbol) -> String

Return a comma-separated description of every keybinding assigned to `action`.

# Arguments

- `action::Symbol`: Pager action whose keybindings are described.
"""
_getkb(action::Symbol) = get(_action_keybindings(), action, "")

"""
    _action_keybindings() -> Dict{Symbol, String}

Return a description of the keybindings of every action, keyed by action.

The result is cached until the keybindings change. Building it scanned `_KEYBINDINGS` once per
action, which the help screen did 27 times every time it was opened.

The descriptions of each action are sorted, so that the help screen does not depend on the
iteration order of `_KEYBINDINGS`.
"""
function _action_keybindings()
    generation = _KEYBINDINGS_GENERATION[]
    _ACTION_KEYBINDINGS_GENERATION[] == generation && return _ACTION_KEYBINDINGS

    descriptions = Dict{Symbol, Vector{String}}()

    for (kb, action) in _KEYBINDINGS
        push!(get!(() -> String[], descriptions, action), _kbtostr(kb))
    end

    empty!(_ACTION_KEYBINDINGS)

    for (action, keys) in descriptions
        _ACTION_KEYBINDINGS[action] = join(sort!(keys), ", ")
    end

    _ACTION_KEYBINDINGS_GENERATION[] = generation

    return _ACTION_KEYBINDINGS
end

"""
    _kbtostr(kb::Tuple{String, Bool, Bool, Bool}) -> String

Convert a keybinding tuple to a human-readable description.

# Arguments

- `kb::Tuple{String, Bool, Bool, Bool}`: Key value and ALT, CTRL, and SHIFT flags.
"""
function _kbtostr(kb::Tuple{String, Bool, Bool, Bool})
    str = kb[1] == " " ? "space" : string(kb[1])

    kb[2] && (str = "ALT " * str)
    kb[3] && (str = "CTRL " * str)
    kb[4] && (str = "SHIFT " * str)

    return str
end
