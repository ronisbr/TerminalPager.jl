## Description #############################################################################
#
# Functions related to the help screen, which is a cheat sheet of the actions, and what it
# shares with the extended help: the style, the banner, the section titles, and the marked
# text.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The help screen only depends on the key bindings. Hence, everything derived from them is
# cached and rebuilt when `_KEYBINDINGS_GENERATION` changes.
const _ACTION_KEYS = Dict{Symbol, Vector{String}}()
const _ACTION_KEYS_GENERATION = Ref(-1)

# One cache entry per color support, holding the generation and the display configuration it
# was built for, the help text, and its prepared layout.
const _HELP_CACHE = Dict{Bool, Tuple{Int, DisplayConfig, String, ViewLayout}}()

# Layout of the help screens: their width, the blank columns at their left and at their
# right, and the widths of the key and description columns of the cheat sheet.
const _HELP_WIDTH = 92
const _HELP_MARGIN = 2
const _HELP_KEY_WIDTH = 20
const _HELP_DESCRIPTION_WIDTH = 40

"""
    _help!(pagerd::Pager) -> Nothing

Open a new pager with the help and request a full repaint of `pagerd` after it is closed.

The help, the visual mode, the line filter, and the freeze of columns are not available in
it, but the rows can be frozen.

# Arguments

- `pagerd::Pager`: Parent pager state whose terminal and input are reused.
"""
function _help!(pagerd::Pager)
    # The color flag must come from the session view buffer, which is the single source of
    # truth for the session rendering. The terminal stream of a programmatically built
    # pager does not necessarily carry the flag.
    help_str, help_layout = _help_screen(
        get(pagerd.buf, :color, true)::Bool, pagerd.display_config
    )

    # The nested session must not toggle the alternate screen buffer: leaving it would
    # switch the terminal back to the normal screen while the parent session keeps painting
    # as if it were on the alternate one. The help clears the screen instead, and the parent
    # repaints everything afterwards. A help has nothing to filter and no leading columns to
    # freeze, but its banner can be frozen.
    options = SessionOptions(;
        change_frozen_columns = false,
        display_config = pagerd.display_config,
        has_filter = false,
        has_help = false,
        has_visual_mode = false,
        input = pagerd.input,
        text_layout = help_layout,
        use_alternate_screen_buffer = false,
        manage_cursor_key_mode = false,
        manage_cursor = false,
        manage_mouse = false,
    )

    _pager!(pagerd.term, help_str, options)

    # The nested pager repainted the whole screen.
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _help_screen(use_color::Bool, display_config::DisplayConfig) ->
        Tuple{String, ViewLayout}

Return the help text and its prepared layout, rebuilding them only when the keybindings or
the faces change.

# Arguments

- `use_color::Bool`: Decorate the help screen with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
"""
function _help_screen(use_color::Bool, display_config::DisplayConfig)
    generation = _KEYBINDINGS_GENERATION[]
    cached = get(_HELP_CACHE, use_color, nothing)

    if !isnothing(cached) && (cached[1] == generation) && (cached[2] == display_config)
        return cached[3], cached[4]
    end

    help_str = _help_string(use_color, display_config)
    help_layout = ViewLayout(split(help_str, '\n'))
    _HELP_CACHE[use_color] = (generation, display_config, help_str, help_layout)

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
            ActionHelp(:help, "Show this cheat sheet.", :help),
            ActionHelp(:extended_help, "Show the extended help, a full manual.", :help),
            ActionHelp(:quit, "Quit the pager."),
            ActionHelp(:quit_eot, "Quit the search, or the pager."),
            ActionHelp(:toggle_ruler, "Toggle the line number ruler."),
            ActionHelp(:toggle_column_ruler, "Toggle the column ruler on top of the view."),
            ActionHelp(:toggle_scrollbar, "Toggle the scrollbar."),
            ActionHelp(:show_position, "Show the visible lines and columns."),
            ActionHelp(:yank_all, "Copy the whole text to the clipboard."),
            ActionHelp(:save, "Save the text, or the selection, to a file."),
            ActionHelp(:edit, "Open the text, or the selection, in the editor."),
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
            ActionHelp(:goto_line, "Go to a line, a percentage, an offset, or the end."),
            ActionHelp(:set_bookmark, "Bookmark the top line under the next letter typed."),
            ActionHelp(:goto_bookmark, "Go to the bookmark of the next letter, or back."),
        ],
    ),
    HelpSection(
        "Searching",
        "The search is case-insensitive unless the pattern has an uppercase letter. " *
            "<kbd>Alt-l</kbd> at the prompt toggles the literal mode, which searches the " *
            "pattern as typed. A pattern like `@12:20 x` matches only in the printable " *
            "columns 12 to 20; `@12 x` and `@:20 x` open one end. The columns are " *
            "highlighted while the range is typed, and `@@` selects them on the screen: " *
            "move the cursor, press <kbd>Enter</kbd> on the first column and again on " *
            "the last one. <kbd>Esc</kbd> clears the search, and then the filter.",
        nothing,
        ActionHelp[
            ActionHelp(:search, "Search for a regex."),
            ActionHelp(
                :filter, "Show only the lines matching a regex; ! inverts it.", :filter
            ),
            ActionHelp(:next_match, "Go to the next match."),
            ActionHelp(:previous_match, "Go to the previous match."),
            ActionHelp(:quit_search, "Quit the search."),
        ],
    ),
    HelpSection(
        "Freezing Data",
        "Frozen rows and columns stay visible while scrolling. Title rows are frozen " *
            "rows that do not scroll horizontally either. The selections on the screen " *
            "are moved with the movement keys or the mouse, applied with " *
            "<kbd>Enter</kbd>, and cancelled with <kbd>Esc</kbd>. The features " *
            "`:change_frozen_rows` and `:change_frozen_columns` tell which of them can " *
            "be changed, and the title rows need the former.",
        :change_freeze,
        ActionHelp[
            ActionHelp(:change_freeze, "Set the frozen rows and columns."),
            ActionHelp(:select_freeze, "Select the frozen rows and columns on the screen."),
            ActionHelp(:change_title_rows, "Set the title rows."),
            ActionHelp(:select_title_rows, "Select the title rows on the screen."),
        ],
    ),
    HelpSection(
        "Visual Mode",
        "The visual line is highlighted, and it can be copied to the clipboard together " *
            "with the marked lines and the range anchored at a line. Marking while a " *
            "range is anchored marks the whole range. Marks are cleared when the mode is " *
            "left.",
        :visual_mode,
        ActionHelp[
            ActionHelp(:toggle_visual_mode, "Toggle the visual mode."),
            ActionHelp(:select_visual_mode_line, "Mark or unmark the visual line."),
            ActionHelp(:toggle_visual_anchor, "Anchor a range at the visual line."),
            ActionHelp(:mouse_select, "Move or mark the clicked line."),
            ActionHelp(:yank, "Copy the visual and the marked lines."),
            ActionHelp(:yank_quit, "Copy the selection and quit; one line down otherwise."),
        ],
    ),
]

"""
    _help_string(use_color::Bool, display_config::DisplayConfig = DisplayConfig()) -> String

Assemble the pager help screen from `_HELP_SECTIONS` and the current key bindings.

The screen is a cheat sheet with one row per action: the keys, the description, and the
action name to use with [`set_keybinding`](@ref). Long key lists and descriptions continue
on the following rows. It has the banner, the section titles, and the marked text of the
extended help, and its introduction points to it if a key is bound to it.

# Arguments

- `use_color::Bool`: Decorate the help screen with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
    (**Default**: `DisplayConfig()`)
"""
function _help_string(use_color::Bool, display_config::DisplayConfig = DisplayConfig())
    style = HelpStyle(use_color, display_config)
    reset = style.reset
    lines = String[]

    _help_banner!(lines, style, "Help")
    push!(lines, "")
    _help_text!(
        lines,
        "The key bindings can be changed with `TerminalPager.set_keybinding`. A section " *
        "or an action marked with a feature is only available when the feature is " *
        "enabled, which depends on how the pager was called.",
        style,
        "",
        "",
    )

    # The cheat sheet points to the manual, which explains what it only lists.
    if !isempty(_action_keys(:extended_help))
        push!(lines, "")
        _help_text!(
            lines,
            "<kbd>:extended_help</kbd> opens the extended help, a manual that explains " *
            "every feature in detail.",
            style,
            "",
            "",
        )
    end

    for section in _HELP_SECTIONS
        push!(lines, "", "", _help_rule(style, _help_section_title(section)), "")

        if !isempty(section.description)
            _help_text!(lines, section.description, style, "", "")
            push!(lines, "")
        end

        for entry in section.actions
            key_rows = _wrap_keys(_action_keys(entry.action), _HELP_KEY_WIDTH)
            description_rows = _wrap_words(entry.description, _HELP_DESCRIPTION_WIDTH)
            num_rows = max(length(key_rows), length(description_rows), 1)

            for i in 1:num_rows
                keys = i <= length(key_rows) ? key_rows[i] : ""
                description = i <= length(description_rows) ? description_rows[i] : ""
                buf = IOBuffer()

                _write_blanks(buf, _HELP_MARGIN + 2)
                write(buf, style.key, keys, reset)

                # A row that only continues the keys has nothing after them.
                if (i == 1) || !isempty(description)
                    _write_blanks(buf, max(_HELP_KEY_WIDTH - textwidth(keys), 0) + 2)
                    write(buf, description)
                end

                if i == 1
                    padding = max(_HELP_DESCRIPTION_WIDTH - textwidth(description), 0)
                    _write_blanks(buf, padding + 2)
                    write(buf, style.action, ":", String(entry.action), reset)
                    isnothing(entry.feature) ||
                        write(buf, style.dim, " [", String(entry.feature), "]", reset)
                end

                push!(lines, String(take!(buf)))
            end
        end
    end

    return join(lines, '\n')
end

"""
    _help_section_title(section::HelpSection) -> String

Return the title of `section` as the help screens show it, followed by the feature the
section requires, if any.

# Arguments

- `section::HelpSection`: Section of the help screen.
"""
function _help_section_title(section::HelpSection)
    isnothing(section.feature) && return section.title
    return string(section.title, " · feature :", section.feature)
end

############################################################################################
#                                          Style                                           #
############################################################################################

"""
    struct HelpStyle

Store the escape sequences that decorate the help screens, which are all empty when the
terminal has no color support.

# Fields

- `title::String`: Title of the screen.
- `section::String`: Section titles, with their marks, and list bullets.
- `strong::String`: Strong text, which is bold.
- `key::String`: Keys of the tables.
- `keycap::String`: Keys in the text, drawn as key caps.
- `keycap_filled::Bool`: Whether the face of the key caps has a background or is reversed,
    in which case a key cap is the key between two blanks with that face. Otherwise, it is
    the key between two brackets drawn as the borders.
- `code::String`: Code, commands, and names.
- `action::String`: Action names of the cheat sheet.
- `dim::String`: Comments, labels, and secondary text.
- `border::String`: Rules and box borders.
- `tip::String`: Label of the tip boxes.
- `note::String`: Label of the note boxes.
- `warning::String`: Label of the warning boxes.
- `reset::String`: Reset of the attributes.
"""
struct HelpStyle
    title::String
    section::String
    strong::String
    key::String
    keycap::String
    keycap_filled::Bool
    code::String
    action::String
    dim::String
    border::String
    tip::String
    note::String
    warning::String
    reset::String
end

"""
    HelpStyle(use_color::Bool, display_config::DisplayConfig) -> HelpStyle

Create the style of the help screens from the faces in `display_config`, or a style without
decorations if `use_color` is `false`.

# Arguments

- `use_color::Bool`: Decorate the help screens with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
"""
function HelpStyle(use_color::Bool, display_config::DisplayConfig)
    use_color ||
        return HelpStyle("", "", "", "", "", false, "", "", "", "", "", "", "", "")

    # A face that paints the cell of a key is drawn as a filled key cap.
    keycap = parse_decoration(display_config.help_keycap)
    keycap_filled =
        !isempty(keycap.background) || (keycap.reversed == StringManipulation.active)

    return HelpStyle(
        display_config.help_title,
        display_config.help_section,
        _SGR_BOLD,
        display_config.help_key,
        display_config.help_keycap,
        keycap_filled,
        display_config.help_code,
        display_config.help_action,
        display_config.help_description,
        display_config.help_border,
        display_config.help_tip,
        display_config.help_note,
        display_config.help_warning,
        _SGR_RESET,
    )
end

############################################################################################
#                                          Layout                                          #
############################################################################################

"""
    _help_banner!(lines::Vector{String}, style::HelpStyle, subtitle::String) -> Nothing

Append to `lines` the banner of a help screen, which is a rounded box with the name and the
version of the package and the `subtitle` that tells which screen it is.

# Arguments

- `lines::Vector{String}`: Lines of the screen, which are appended.
- `style::HelpStyle`: Escape sequences that decorate the screen.
- `subtitle::String`: Name of the screen.
"""
function _help_banner!(lines::Vector{String}, style::HelpStyle, subtitle::String)
    margin = " "^_HELP_MARGIN
    border = style.border
    reset = style.reset
    name = string("TerminalPager.jl ", _pkg_version())
    separator = "  ·  "
    inner = _HELP_WIDTH - 2 * _HELP_MARGIN - 2
    used = 2 + textwidth(name) + textwidth(separator) + textwidth(subtitle)

    buf = IOBuffer()
    write(buf, margin, border, "│", reset, "  ", style.title, name, reset)
    write(buf, style.dim, separator, reset, style.strong, subtitle, reset)
    _write_blanks(buf, inner - used)
    write(buf, border, "│", reset)

    push!(lines, string(margin, border, "╭", "─"^inner, "╮", reset))
    push!(lines, String(take!(buf)))
    push!(lines, string(margin, border, "╰", "─"^inner, "╯", reset))

    return nothing
end

"""
    _help_rule(style::HelpStyle, title::String) -> String

Return the line that begins a section of a help screen: its `title` on a heavy rule that
spans the width of the screen.

# Arguments

- `style::HelpStyle`: Escape sequences that decorate the screen.
- `title::String`: Title of the section.
"""
function _help_rule(style::HelpStyle, title::String)
    border = style.border
    reset = style.reset
    rule = "━"^max(_HELP_WIDTH - 2 * _HELP_MARGIN - textwidth(title) - 4, 0)

    buf = IOBuffer()
    _write_blanks(buf, _HELP_MARGIN)
    write(buf, border, "━━ ", reset, style.section, title, reset)
    write(buf, border, " ", rule, reset)

    return String(take!(buf))
end

############################################################################################
#                                           Text                                           #
############################################################################################

"""
    struct HelpAtom

Represent an unbreakable piece of a text of the help screens.

# Fields

- `text::String`: Text of the piece.
- `style::Symbol`: Style of the piece: `:plain`, `:strong`, `:code`, or `:key`.
- `glued::Bool`: Whether the piece follows the previous one without a blank, in which case
    a line cannot be broken between them.
"""
struct HelpAtom
    text::String
    style::Symbol
    glued::Bool
end

"""
    _help_text!(
        lines::Vector{String},
        text::AbstractString,
        style::HelpStyle,
        first_indent::String,
        indent::String,
        width::Int = _HELP_WIDTH - 2 * _HELP_MARGIN
    ) -> Nothing

Append to `lines` the marked `text` wrapped so that it fits in `width` columns. The first
line starts with `first_indent`, which can be decorated, and the others with `indent`, both
after the margin of the screen and both with the same printable width.

# Arguments

- `lines::Vector{String}`: Lines of the screen, which are appended.
- `text::AbstractString`: Text to lay out, with the marks of [`_help_atoms`](@ref).
- `style::HelpStyle`: Escape sequences that decorate the screen.
- `first_indent::String`: Beginning of the first line.
- `indent::String`: Beginning of the other lines.
- `width::Int`: Number of columns of the text, with the indentation.
    (**Default**: the width of the screen without its margins)
"""
function _help_text!(
    lines::Vector{String},
    text::AbstractString,
    style::HelpStyle,
    first_indent::String,
    indent::String,
    width::Int = _HELP_WIDTH - 2 * _HELP_MARGIN,
)
    rows = _wrap_help_atoms(_help_atoms(text), width - textwidth(indent))

    for (i, row) in enumerate(rows)
        buf = IOBuffer()
        _write_blanks(buf, _HELP_MARGIN)
        write(buf, i == 1 ? first_indent : indent)
        _write_help_atoms!(buf, row, style)
        push!(lines, String(take!(buf)))
    end

    return nothing
end

# Characters that a backslash writes as they are in a marked text, which are the punctuation
# characters of ASCII, as in GitHub Flavored Markdown.
const _HELP_ESCAPABLE = "!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

"""
    _help_atoms(text::AbstractString) -> Vector{HelpAtom}

Split the marked `text` of a help screen into its unbreakable pieces.

The words are separated by blanks, and the marks are those of GitHub Flavored Markdown. A
text between backticks is one piece of code, in which nothing else is marked.
`<kbd>:action</kbd>` is the shortest key bound to the action, or `unbound` if there is none,
and `<kbd>Key</kbd>` is the key with that name, both drawn as key caps. The words between
two pairs of asterisks are strong. A backslash before a punctuation character writes the
character as it is. No other mark is known, so a single asterisk is an asterisk.

# Arguments

- `text::AbstractString`: Marked text.
"""
function _help_atoms(text::AbstractString)
    atoms = HelpAtom[]
    word = IOBuffer()
    strong = false
    glued = false
    i = firstindex(text)
    last_index = lastindex(text)

    while i <= last_index
        c = text[i]
        next = nextind(text, i)

        if (c == '\\') && (next <= last_index) && (text[next] in _HELP_ESCAPABLE)
            write(word, string(text[next]))
            i = nextind(text, next)
            continue
        end

        # Notice that an unbalanced mark is a character of the word.
        kind, first_index, stop = _help_mark(text, i)

        # The word read so far ends at a blank and at a mark.
        if (position(word) > 0) && (isspace(c) || (kind !== :plain))
            push!(atoms, HelpAtom(String(take!(word)), strong ? :strong : :plain, glued))
            glued = true
        end

        if isspace(c)
            glued = false
        elseif kind === :strong
            strong = !strong
        elseif kind === :code
            content = SubString(text, first_index, prevind(text, stop))
            push!(atoms, HelpAtom(String(content), :code, glued))
            glued = true
        elseif kind === :key
            # The mark that ends the key has six characters.
            content = SubString(text, first_index, prevind(text, stop - 5))
            push!(atoms, HelpAtom(_help_key_name(content), :key, glued))
            glued = true
        else
            write(word, string(c))
        end

        i = kind === :plain ? next : nextind(text, stop)
    end

    (position(word) > 0) &&
        push!(atoms, HelpAtom(String(take!(word)), strong ? :strong : :plain, glued))

    return atoms
end

"""
    _help_mark(text::AbstractString, i::Int) -> Symbol, Int, Int

Return the kind of the mark that begins at the index `i` of the marked `text` of a help
screen, the index of the first character of its content, and the index of its last
character. The kind is `:code` for a text between backticks, `:key` for one between `<kbd>`
and `</kbd>`, `:strong` for two asterisks, which have no content, and `:plain` if no mark
begins at `i` or if the mark is not closed.

# Arguments

- `text::AbstractString`: Marked text.
- `i::Int`: Index of a character of `text`.
"""
function _help_mark(text::AbstractString, i::Int)
    c = text[i]
    next = nextind(text, i)

    if c == '`'
        stop = findnext('`', text, next)
        isnothing(stop) || return :code, next, stop
    elseif (c == '<') && startswith(SubString(text, i), "<kbd>")
        closing = findnext("</kbd>", text, i + 5)
        isnothing(closing) || return :key, i + 5, Base.last(closing)
    elseif (c == '*') && (next <= lastindex(text)) && (text[next] == '*')
        return :strong, next, next
    end

    return :plain, i, i
end

"""
    _help_key_name(key::AbstractString) -> String

Return the name of the key marked as `<kbd>key</kbd>` in a text of a help screen: the
shortest key
bound to the action if `key` is written as `:action`, or `unbound` if there is none, and
`key` itself otherwise.

# Arguments

- `key::AbstractString`: Name of a key, or an action written as `:action`.
"""
function _help_key_name(key::AbstractString)
    startswith(key, ':') || return String(key)
    names = _keyboard_keys(Symbol(SubString(key, 2)))
    return isempty(names) ? "unbound" : first(names)
end

"""
    _keyboard_keys(action::Symbol) -> Vector{String}

Return the names of the keys bound to `action` that the texts of the help screens show, from
the shortest to the longest one. The mouse events are left out if a key is also bound to the
action, because the texts explain the actions with the keyboard.

# Arguments

- `action::Symbol`: Pager action.
"""
function _keyboard_keys(action::Symbol)
    names = _action_keys(action)
    keys = String[]

    for name in names
        (occursin("Wheel", name) || occursin("Click", name)) || push!(keys, name)
    end

    return isempty(keys) ? names : keys
end

"""
    _help_atom_width(atom::HelpAtom) -> Int

Return the printable width of `atom`. A key cap has one column at each side of the key.

# Arguments

- `atom::HelpAtom`: Piece of a text.
"""
_help_atom_width(atom::HelpAtom) = textwidth(atom.text) + (atom.style === :key ? 2 : 0)

"""
    _help_atoms_width(atoms::AbstractVector{HelpAtom}) -> Int

Return the printable width of `atoms` written in one line, with one blank before every piece
that is not glued to the previous one.

# Arguments

- `atoms::AbstractVector{HelpAtom}`: Pieces of a text.
"""
function _help_atoms_width(atoms::AbstractVector{HelpAtom})
    width = 0

    for (i, atom) in enumerate(atoms)
        width += _help_atom_width(atom) + (((i > 1) && !atom.glued) ? 1 : 0)
    end

    return width
end

"""
    _wrap_help_atoms(atoms::Vector{HelpAtom}, width::Int) -> Vector{Vector{HelpAtom}}

Wrap `atoms` greedily into rows of at most `width` columns, breaking only before a piece
that is not glued to the previous one. Pieces that do not fit in `width` get a row of their
own. No piece yields no row.

# Arguments

- `atoms::Vector{HelpAtom}`: Pieces of a text.
- `width::Int`: Maximum width of a row.
"""
function _wrap_help_atoms(atoms::Vector{HelpAtom}, width::Int)
    rows = Vector{HelpAtom}[]
    row = HelpAtom[]
    row_width = 0
    num_atoms = length(atoms)
    i = 1

    while i <= num_atoms
        # A word is a piece and the ones glued to it.
        stop = i
        word_width = _help_atom_width(atoms[i])

        while (stop < num_atoms) && atoms[stop + 1].glued
            stop += 1
            word_width += _help_atom_width(atoms[stop])
        end

        if !isempty(row) && (row_width + 1 + word_width > width)
            push!(rows, row)
            row = HelpAtom[]
            row_width = 0
        end

        row_width += word_width + (isempty(row) ? 0 : 1)

        for j in i:stop
            push!(row, atoms[j])
        end

        i = stop + 1
    end

    isempty(row) || push!(rows, row)

    return rows
end

"""
    _write_help_atoms!(io::IO, atoms::Vector{HelpAtom}, style::HelpStyle) -> Int

Write `atoms` to `io` in one line, decorated with `style`, and return the printable width
that was written. A piece that is not glued to the previous one is preceded by a blank, but
for the first one.

A key is drawn as a key cap with the same width in every case: the key between two blanks,
all with the face of the key caps, if the face fills its cells, the key between two brackets
drawn as the borders otherwise, and the key between plain brackets without colors.

# Arguments

- `io::IO`: Output stream to update.
- `atoms::Vector{HelpAtom}`: Pieces of a text.
- `style::HelpStyle`: Escape sequences that decorate the screen.
"""
function _write_help_atoms!(io::IO, atoms::Vector{HelpAtom}, style::HelpStyle)
    width = 0
    reset = style.reset

    for (i, atom) in enumerate(atoms)
        if (i > 1) && !atom.glued
            write(io, " ")
            width += 1
        end

        text = atom.text
        kind = atom.style

        if kind === :plain
            write(io, text)
        elseif kind === :code
            write(io, style.code, text, reset)
        elseif kind === :strong
            write(io, style.strong, text, reset)
        elseif isempty(style.keycap)
            write(io, "[", text, "]")
        elseif style.keycap_filled
            write(io, style.keycap, " ", text, " ", reset)
        else
            write(io, style.border, "[", reset, style.keycap, text, reset)
            write(io, style.border, "]", reset)
        end

        width += _help_atom_width(atom)
    end

    return width
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
