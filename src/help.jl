## Description #############################################################################
#
# Functions related to help screen.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The help screen only depends on the key bindings. Hence, everything derived from them is
# cached and rebuilt when `_KEYBINDINGS_GENERATION` changes.
const _ACTION_KEYS = Dict{Symbol, Vector{String}}()
const _ACTION_KEYS_GENERATION = Ref(-1)

# One cache entry per color support, holding the generation it was built for, the help text,
# and its prepared layout.
const _HELP_CACHE = Dict{Bool, Tuple{Int, String, TextViewLayout}}()

# Layout of the help screen: its width, and the widths of the key and description columns.
const _HELP_WIDTH = 90
const _HELP_KEY_WIDTH = 20
const _HELP_DESCRIPTION_WIDTH = 40

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

    # The nested session must not toggle the alternate screen buffer: leaving it would
    # switch the terminal back to the normal screen while the parent session keeps painting
    # as if it were on the alternate one. The help clears the screen instead, and the parent
    # repaints everything afterwards.
    _pager!(
        pagerd.term,
        help_str;
        display_config = pagerd.display_config,
        hashelp = false,
        has_visual_mode = false,
        input = pagerd.input,
        text_layout = help_layout,
        use_alternate_screen_buffer = false,
        manage_cursor_key_mode = false,
        manage_cursor = false,
        manage_mouse = false,
    )

    return nothing
end

"""
    _help_screen(use_color::Bool) -> Tuple{String, TextViewLayout}

Return the help text and its prepared layout, rebuilding them only when the keybindings
change.

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

Notice that this must not be stored in a constant. `pkgversion` evaluated while the package
is precompiled captures the version that was current at that moment, so the help screen kept
showing a stale one after a new version was released.
"""
_pkg_version() = pkgversion(@__MODULE__)

"""
    struct ActionHelp

Describe one pager action in the help screen.

# Fields

- `action::Symbol`: Pager action.
- `description::String`: Short description of the action.
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
- `description::String`: Short description of the action.
"""
ActionHelp(action::Symbol, description::String) = ActionHelp(action, description, nothing)

"""
    struct HelpSection

Group the actions of the help screen under a title.

# Fields

- `title::String`: Section title.
- `description::String`: Introduction shown under the title, or an empty string.
- `feature::Union{Nothing, Symbol}`: Feature required by every action in the section, or
    `nothing`.
- `actions::Vector{ActionHelp}`: Actions documented in the section.
"""
struct HelpSection
    title::String
    description::String
    feature::Union{Nothing, Symbol}
    actions::Vector{ActionHelp}
end

# The help screen is generated from this table, so that the documentation of an action lives
# in a single place.
const _HELP_SECTIONS = HelpSection[
    HelpSection(
        "General",
        "",
        nothing,
        ActionHelp[
            ActionHelp(:help, "Show this screen.", :help),
            ActionHelp(:quit, "Quit the pager."),
            ActionHelp(:quit_eot, "Quit the search, or the pager."),
            ActionHelp(:toggle_ruler, "Toggle the line number ruler."),
            ActionHelp(:toggle_scrollbar, "Toggle the scrollbar."),
        ],
    ),
    HelpSection(
        "Movement",
        "In the visual mode, the movements are relative to the visual line.",
        nothing,
        ActionHelp[
            ActionHelp(:up, "One line up."),
            ActionHelp(:down, "One line down."),
            ActionHelp(:left, "One column left."),
            ActionHelp(:right, "One column right."),
            ActionHelp(:fastup, "Five lines up."),
            ActionHelp(:fastdown, "Five lines down."),
            ActionHelp(:fastleft, "Ten columns left."),
            ActionHelp(:fastright, "Ten columns right."),
            ActionHelp(:wheel_up, "Three lines up."),
            ActionHelp(:wheel_down, "Three lines down."),
            ActionHelp(:pageup, "One page up."),
            ActionHelp(:pagedown, "One page down."),
            ActionHelp(:halfpageup, "Half a page up."),
            ActionHelp(:halfpagedown, "Half a page down."),
            ActionHelp(:bol, "First column."),
            ActionHelp(:eol, "Last column."),
            ActionHelp(:home, "First line."),
            ActionHelp(:end, "Last line."),
            ActionHelp(:goto_line, "Go to a line number."),
        ],
    ),
    HelpSection(
        "Searching",
        "The search is case-insensitive unless the pattern has an uppercase letter.",
        nothing,
        ActionHelp[
            ActionHelp(:search, "Search for a regex."),
            ActionHelp(:next_match, "Go to the next match."),
            ActionHelp(:previous_match, "Go to the previous match."),
            ActionHelp(:quit_search, "Quit the search."),
        ],
    ),
    HelpSection(
        "Freezing Data",
        "Frozen rows and columns stay visible while scrolling. Title rows are frozen rows " *
            "that do not scroll horizontally either.",
        :change_freeze,
        ActionHelp[
            ActionHelp(:change_freeze, "Set the frozen rows and columns."),
            ActionHelp(:change_title_rows, "Set the title rows."),
        ],
    ),
    HelpSection(
        "Visual Mode",
        "The visual line is highlighted, and the marked lines can be copied to the " *
            "clipboard. Marks are cleared when the mode is left.",
        :visual_mode,
        ActionHelp[
            ActionHelp(:toggle_visual_mode, "Toggle the visual mode."),
            ActionHelp(:select_visual_mode_line, "Mark or unmark the visual line."),
            ActionHelp(:mouse_select, "Move or mark the clicked line."),
            ActionHelp(:yank, "Copy the marked lines to the clipboard."),
        ],
    ),
]

"""
    _help_string(use_color::Bool) -> String

Assemble the pager help screen from [`_HELP_SECTIONS`](@ref) and the current key bindings.

The screen is a cheat sheet with one row per action: the keys, the description, and the
action name to use with [`set_keybinding`](@ref). Long key lists and descriptions continue
on the following rows.

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
        "  The key bindings can be changed with ", _c, "set_keybinding", _d, ". A section or\n",
        "  an action marked with a feature is only available when the feature is enabled,\n",
        "  which depends on how the pager was called.\n",
    )

    for section in _HELP_SECTIONS
        title = section.title
        isnothing(section.feature) || (title *= " (feature :$(section.feature))")
        rule = "─"^max(_HELP_WIDTH - textwidth(title) - 4, 0)
        print(buf, '\n', _b, "── ", title, " ", rule, _d, '\n')

        for line in _wrap_words(section.description, _HELP_WIDTH - 2)
            print(buf, "  ", _g, line, _d, '\n')
        end

        for entry in section.actions
            key_rows = _wrap_keys(_action_keys(entry.action), _HELP_KEY_WIDTH)
            description_rows = _wrap_words(entry.description, _HELP_DESCRIPTION_WIDTH)
            num_rows = max(length(key_rows), length(description_rows), 1)

            for i in 1:num_rows
                keys = i <= length(key_rows) ? key_rows[i] : ""
                description = i <= length(description_rows) ? description_rows[i] : ""

                print(buf, "  ", _c, keys, _d)
                print(buf, " "^max(_HELP_KEY_WIDTH - textwidth(keys), 0), "  ")

                if i == 1
                    padding = max(_HELP_DESCRIPTION_WIDTH - textwidth(description), 0)
                    print(buf, description, " "^padding, "  ", _y, ':', entry.action, _d)
                    isnothing(entry.feature) || print(buf, _g, " [", entry.feature, "]", _d)
                else
                    print(buf, description)
                end

                print(buf, '\n')
            end
        end
    end

    return String(take!(buf))
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _action_keys() -> Dict{Symbol, Vector{String}}

Return the human-readable names of the keys bound to every action, keyed by action and
sorted from the shortest name to the longest one.

The result is cached until the key bindings change and must not be modified.
"""
function _action_keys()
    generation = _KEYBINDINGS_GENERATION[]
    _ACTION_KEYS_GENERATION[] == generation && return _ACTION_KEYS

    empty!(_ACTION_KEYS)

    for (kb, action) in _KEYBINDINGS
        push!(get!(() -> String[], _ACTION_KEYS, action), _pretty_key(kb))
    end

    for names in values(_ACTION_KEYS)
        sort!(names; by = name -> (textwidth(name), name))
    end

    _ACTION_KEYS_GENERATION[] = generation

    return _ACTION_KEYS
end

"""
    _action_keys(action::Symbol) -> Vector{String}

Return the human-readable names of the keys bound to `action`, which must not be modified.

# Arguments

- `action::Symbol`: Pager action.
"""
_action_keys(action::Symbol) = get(_action_keys(), action, String[])

"""
    _wrap_keys(names::Vector{String}, width::Int) -> Vector{String}

Join the key `names` with commas into rows of at most `width` columns, breaking only between
names. A name wider than `width` gets a row of its own.

# Arguments

- `names::Vector{String}`: Key names to lay out.
- `width::Int`: Maximum width of a row.
"""
function _wrap_keys(names::Vector{String}, width::Int)
    rows = String[]
    isempty(names) && return rows

    row = ""

    for name in names
        if isempty(row)
            row = name
        elseif textwidth(row) + 2 + textwidth(name) <= width
            row *= ", " * name
        else
            push!(rows, row * ",")
            row = name
        end
    end

    push!(rows, row)

    return rows
end

"""
    _wrap_words(text::String, width::Int) -> Vector{String}

Wrap `text` greedily at the spaces into rows of at most `width` columns. A word wider than
`width` gets a row of its own. An empty text yields no row.

# Arguments

- `text::String`: Text to wrap.
- `width::Int`: Maximum width of a row.
"""
function _wrap_words(text::String, width::Int)
    rows = String[]
    row = ""

    for word in eachsplit(text, ' '; keepempty = false)
        if isempty(row)
            row = String(word)
        elseif textwidth(row) + 1 + textwidth(word) <= width
            row *= " " * word
        else
            push!(rows, row)
            row = String(word)
        end
    end

    isempty(row) || push!(rows, row)

    return rows
end
