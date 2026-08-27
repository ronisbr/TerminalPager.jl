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
    # The color flag must come from the session view buffer, which is the single source of
    # truth for the session rendering. The terminal stream of a programmatically built
    # pager does not necessarily carry the flag.
    help_str, help_layout = _help_screen(get(pagerd.buf, :color, true)::Bool)

    _pager!(
        pagerd.term,
        help_str;
        display_config = pagerd.display_config,
        hashelp = false,
        has_visual_mode = false,
        input = pagerd.input,
        text_layout = help_layout,
        manage_cursor_key_mode = false,
        manage_cursor = false,
        manage_mouse = false,
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
    struct ActionHelp

Describe one pager action in the help screen.

# Fields

- `action::Symbol`: Pager action.
- `description::String`: Description of the action, possibly spanning multiple lines.
- `feature::Union{Nothing, Symbol}`: Feature required by the action, or `nothing`.
"""
struct ActionHelp
    action::Symbol
    description::String
    feature::Union{Nothing, Symbol}
end

"""
    ActionHelp(action::Symbol, description::String) -> ActionHelp

Describe the pager `action` with `description` when it does not require a feature.

# Arguments

- `action::Symbol`: Pager action.
- `description::String`: Description of the action, possibly spanning multiple lines.
"""
ActionHelp(action::Symbol, description::String) = ActionHelp(action, description, nothing)

"""
    struct HelpSection

Group the actions of the help screen under a title.

# Fields

- `title::String`: Section title.
- `feature::Union{Nothing, Symbol}`: Feature required by every action in the section, or
    `nothing`.
- `actions::Vector{ActionHelp}`: Actions documented in the section.
"""
struct HelpSection
    title::String
    feature::Union{Nothing, Symbol}
    actions::Vector{ActionHelp}
end

# The help screen is generated from this table, so that the documentation of an action lives
# in a single place.
const _HELP_SECTIONS = HelpSection[
    HelpSection(
        "General",
        nothing,
        ActionHelp[
            ActionHelp(:help, "Show this screen.", :help),
            ActionHelp(:quit, "Quit the pager."),
            ActionHelp(
                :quit_eot,
                """
                This is a special quit action designed for the
                END OF TRANSMISSION (^D) keycode. If we are in a search
                operation, then it quits the search. If not, then it
                quits the pager.""",
            ),
            ActionHelp(:toggle_ruler, "Toggle the vertical ruler."),
        ],
    ),
    HelpSection(
        "Movement",
        nothing,
        ActionHelp[
            ActionHelp(:up, "Move the display one line up."),
            ActionHelp(:down, "Move the display one line down."),
            ActionHelp(:left, "Move the display one column to the left."),
            ActionHelp(:right, "Move the display one column to the right."),
            ActionHelp(:fastup, "Move the display five lines up."),
            ActionHelp(:fastdown, "Move the display five lines down."),
            ActionHelp(:fastleft, "Move the display ten columns to the left."),
            ActionHelp(:fastright, "Move the display ten columns to the right."),
            ActionHelp(
                :pageup,
                "Move the display one page up (a page has the same size as the view).",
            ),
            ActionHelp(
                :pagedown,
                "Move the display one page down (a page has the same size as the view).",
            ),
            ActionHelp(
                :halfpageup,
                "Move the display half page up (a page has the same size as the view).",
            ),
            ActionHelp(
                :halfpagedown,
                "Move the display half page down (a page has the same size as the view).",
            ),
            ActionHelp(:bol, "Move the display to the first column."),
            ActionHelp(:eol, "Move the display to show the last column."),
            ActionHelp(:home, "Move the display to the first line."),
            ActionHelp(:end, "Move the display to show the last line."),
            ActionHelp(
                :goto_line,
                "Request a line number in the command line and move the display to it.",
            ),
            ActionHelp(:wheel_up, "Move the display three lines up."),
            ActionHelp(:wheel_down, "Move the display three lines down."),
        ],
    ),
    HelpSection(
        "Searching",
        nothing,
        ActionHelp[
            ActionHelp(
                :search,
                "Request a regex in the command line and highlight all the matches.",
            ),
            ActionHelp(:next_match, "Go to the next match of the search."),
            ActionHelp(:previous_match, "Go to the previous match of the search."),
            ActionHelp(
                :quit_search,
                "Quit searching, removing all the highlights (only during search mode).",
            ),
        ],
    ),
    HelpSection(
        "Freezing Data",
        :change_freeze,
        ActionHelp[
            ActionHelp(
                :change_freeze,
                """
                Two values will be requested in the command line. The first is the
                number of rows and the second is the number of columns that will be
                frozen. If a value is equal to or lower than 0, then no row or column
                will be frozen.""",
            ),
            ActionHelp(
                :change_title_rows,
                """
                Define the number of rows within the frozen rows that will be
                considered as titles. In this case, these rows will not scroll
                horizontally.""",
            ),
        ],
    ),
    HelpSection(
        "Visual Mode",
        :visual_mode,
        ActionHelp[
            ActionHelp(
                :toggle_visual_mode,
                """
                Toggle visual mode, where a visual line is displayed on the screen.
                In this mode, the movements are slightly modified to be relative to
                the visual line.""",
            ),
            ActionHelp(
                :select_visual_mode_line,
                """
                Mark the current visual line. Notice that if the line is already
                marked, it will be unmarked. All the lines are unmarked when we exit
                the visual mode.""",
            ),
            ActionHelp(
                :mouse_select,
                """
                Move the visual line to the clicked line, or mark the clicked line
                when it is already the visual line.""",
            ),
            ActionHelp(
                :yank,
                """
                Copy (yank) the selected and current visual lines to the system
                clipboard.""",
            ),
        ],
    ),
]

# Width used to center the section titles of the help screen.
const _HELP_WIDTH = 92

"""
    _help_string(use_color::Bool) -> String

Assemble the pager help screen from [`_HELP_SECTIONS`](@ref) and the current key bindings.

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

    buf = IOBuffer()

    print(buf, "  ", _cb, "TerminalPager.jl ", _pkg_version(), _d, "\n\n")
    print(
        buf,
        "  The pager can execute several types of actions, as shown below. The key\n",
        "  bindings of each action can be changed using the function\n",
        "  ", _c, "set_keybinding", _d, ".\n\n",
        "  Some actions are only available if a feature is enabled. The enabled\n",
        "  features depend on how the pager was called and on the object being\n",
        "  displayed.\n",
    )

    for section in _HELP_SECTIONS
        title = section.title
        print(buf, '\n', _b, " "^div(_HELP_WIDTH - length(title), 2), title, _d, '\n')

        if !isnothing(section.feature)
            feature = section.feature
            print(buf, _g, "  These actions require the feature :", feature, ".", _d, '\n')
        end

        for entry in section.actions
            print(buf, _y, "  :", entry.action, _d, '\n')

            for line in eachsplit(entry.description, '\n')
                print(buf, "    ", line, '\n')
            end

            print(buf, _c, "    Keybindings: ", _getkb(entry.action), _d, '\n')

            if !isnothing(entry.feature)
                feature = entry.feature
                note = "    This action requires the feature :"
                print(buf, _g, note, feature, ".", _d, '\n')
            end
        end
    end

    return String(take!(buf))
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

The result is cached until the keybindings change. Without the cache, opening the help
screen scanned `_KEYBINDINGS` once per action, that is, 27 times.

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
