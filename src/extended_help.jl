## Description #############################################################################
#
# Extended help: a manual of the pager, shown inside the pager itself. This file contains
# the renderer that lays out the text of the manual, which is the Markdown file
# `extended_help.md`, and the session that shows the result. The style, the banner, the
# section titles, and the marked text are shared with the help screen in `help.jl`.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# Largest width of the key column of a key table and of the term column of a definition
# list that has the descriptions at the side of the terms.
const _MANUAL_KEY_WIDTH = 16
const _MANUAL_TERM_WIDTH = 24

# Number of keys of an action shown in a key table.
const _MANUAL_MAX_KEYS = 3

# Text of the manual, which is written in GitHub Flavored Markdown as described in
# `_manual_lines`. The last chapter, with the reference of the actions, is generated from
# the table of the help screen.
#
# NOTE: The file is read when the package is precompiled. Hence, the manual adds one string
# to the image of the package, nothing but the renderer must be compiled to show it, and the
# file is not needed afterwards. The line endings are normalized because Git can check the
# file out with the ones of Windows.
const _MANUAL_SOURCE = let file = joinpath(@__DIR__, "extended_help.md")
    # The content of the file is tracked, when possible, so that a package image moved with
    # its depot stays valid.
    @static if VERSION >= v"1.11"
        include_dependency(file; track_content = true)
    else
        include_dependency(file)
    end

    replace(read(file, String), "\r\n" => "\n")
end

"""
    struct ManualCache

Store the last rendered extended help and what it was rendered for.

# Fields

- `generation::Int`: Generation of the key bindings.
- `display_config::DisplayConfig`: Display configuration with the help faces.
- `use_color::Bool`: Whether the manual was decorated.
- `text::String`: Text of the manual.
- `layout::ViewLayout`: Prepared layout of the text.
- `bookmarks::Dict{Char, Tuple{Int, Int}}`: Line and column of each chapter, keyed by its
    letter.
"""
struct ManualCache
    generation::Int
    display_config::DisplayConfig
    use_color::Bool
    text::String
    layout::ViewLayout
    bookmarks::Dict{Char, Tuple{Int, Int}}
end

# The manual only depends on the key bindings and on the faces. Hence, the last one that was
# rendered is kept.
const _MANUAL_CACHE = Ref{Union{Nothing, ManualCache}}(nothing)

############################################################################################
#                                         Session                                          #
############################################################################################

"""
    _extended_help!(pagerd::Pager) -> Nothing

Open a new pager with the extended help and request a full repaint of `pagerd` after it is
closed.

The manual has the fixed width of the help screens, so a narrower display scrolls it
horizontally. The session starts with one bookmark per chapter, which are the letters of the
table of contents, so that the keys bound to `:goto_bookmark` and a letter jump to a
chapter. The visual mode is available in it, so that the examples can be copied. The line
filter and the freeze of columns are not, but the rows can be frozen.

# Arguments

- `pagerd::Pager`: Parent pager state whose terminal and input are reused.
"""
function _extended_help!(pagerd::Pager)
    # The color flag must come from the session view buffer, as explained in `_help!`.
    manual = _manual(get(pagerd.buf, :color, true)::Bool, pagerd.display_config)

    # The nested session must not toggle the alternate screen buffer, as explained in
    # `_help!`. A column ruler would only add noise to a text that is not a table, which
    # also has nothing to filter and no leading columns to freeze.
    options = SessionOptions(;
        change_frozen_columns = false,
        display_config = pagerd.display_config,
        has_filter = false,
        has_help = false,
        input = pagerd.input,
        show_column_ruler = false,
        text_layout = manual.layout,
        use_alternate_screen_buffer = false,
        manage_cursor_key_mode = false,
        manage_cursor = false,
        manage_mouse = false,
        _bookmarks = manual.bookmarks,
    )

    _pager!(pagerd.term, manual.text, options)

    # The nested pager repainted the whole screen.
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _manual(use_color::Bool, display_config::DisplayConfig) -> ManualCache

Return the extended help with its prepared layout and the bookmarks of its chapters,
rendering it only when the key bindings, the faces, or the color support changed since the
last call.

# Arguments

- `use_color::Bool`: Decorate the manual with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
"""
function _manual(use_color::Bool, display_config::DisplayConfig)
    generation = _KEYBINDINGS_GENERATION[]
    cached = _MANUAL_CACHE[]

    if !isnothing(cached) &&
        (cached.generation == generation) &&
        (cached.display_config == display_config) &&
        (cached.use_color == use_color)
        return cached
    end

    lines, bookmarks = _manual_lines(_manual_source(), HelpStyle(use_color, display_config))

    manual = ManualCache(
        generation,
        display_config,
        use_color,
        join(lines, '\n'),
        ViewLayout(lines),
        bookmarks,
    )
    _MANUAL_CACHE[] = manual

    return manual
end

"""
    _manual_source() -> String

Return the source of the extended help, which is its text followed by a chapter that lists
every action with its keys. That chapter is generated from the sections of the help screen,
which is the single place where the actions are described.
"""
function _manual_source()
    buf = IOBuffer()

    write(buf, _MANUAL_SOURCE)
    write(
        buf,
        "\n# Action Reference\n\n",
        "Every action of the pager, with the keys bound to it, what it does, and its ",
        "name, which is what `TerminalPager.set_keybinding` receives. A section marked ",
        "with a feature is available only when the feature is enabled.\n",
    )

    for section in _HELP_SECTIONS
        write(buf, "\n## ", _help_section_title(section), "\n\n")
        write(buf, "| Key | Action |\n|:--|:--|\n")

        for entry in section.actions
            action = String(entry.action)

            # A bar in a cell of a table must be escaped.
            description = replace(entry.description, "|" => "\\|")
            write(buf, "| <kbd>:", action, "</kbd> | ", description, " `:", action, "` |\n")
        end
    end

    return String(take!(buf))
end

############################################################################################
#                                         Document                                         #
############################################################################################

"""
    _manual_lines(source::AbstractString, style::HelpStyle) ->
        Vector{String}, Dict{Char, Tuple{Int, Int}}

Lay out the `source` of the extended help, decorated with `style`, and return its lines
together with the line and the column of the title of each chapter, keyed by the letter the
table of contents gives to it.

The source is written in GitHub Flavored Markdown, but only the following blocks are laid
out. They must be separated by blank lines, and the first line of a block tells what it is:

- `# Title` begins a chapter, and `## Title` is a section title.
- A line that begins with `|` begins a table with two columns. Its first two rows, which are
    the header and the delimiter, are not shown. If the first column has keys, written as
    `<kbd>Key</kbd>` or as `<kbd>:action</kbd>`, it is a key table. Otherwise, it is a list
    of terms, which are written as code. A bar inside a cell is written as `\\|`.
- `- text` is an item of a bulleted list, and `1. text` is an item of a numbered one. A line
    that begins with a blank continues the previous item.
- A line that begins with `>` begins a boxed remark, in which every line begins with `>`.
    Its first line can be an alert, `[!TIP]`, `[!NOTE]`, `[!IMPORTANT]`, `[!WARNING]`, or
    `[!CAUTION]`, which names the box and selects its color.
- A line that begins with three backticks begins an example, which ends at a line with only
    three backticks. A title written as `title="..."` after the language is shown on the
    box. Each line between them is code, which can be followed by two blanks and `# ` with
    a comment.
- A line that begins with three tildes begins a figure, which ends at a line with only three
    tildes. Each line between them is written as it is, and it can be followed by two
    blanks and `# ` with a label.
- A line that begins with `<!--` begins a comment, which ends at a line that ends with
    `-->` and is not shown.
- Anything else is a paragraph.

The texts, except the code and the figures, have the marks of [`_help_atoms`](@ref).

The manual begins with a banner and the blocks before the first chapter, which are followed
by the table of contents. No line is wider than `_HELP_WIDTH`, unless a word, a line of
code, or a line of a figure does not fit in it.

# Arguments

- `source::AbstractString`: Source of the manual, with at most 26 chapters.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_lines(source::AbstractString, style::HelpStyle)
    lines = String[]
    bookmarks = Dict{Char, Tuple{Int, Int}}()
    blocks = _manual_blocks(source)
    titles = String[]

    for block in blocks
        head = first(block)
        startswith(head, "# ") && push!(titles, String(SubString(head, 3)))
    end

    _help_banner!(lines, style, "Extended Help")

    num_chapters = 0

    for block in blocks
        if !startswith(first(block), "# ")
            push!(lines, "")
            _manual_block!(lines, block, style)
            continue
        end

        # The table of contents follows the introduction.
        if num_chapters == 0
            push!(lines, "")
            _manual_contents!(lines, titles, style)
        end

        num_chapters += 1
        letter = _manual_letter(num_chapters)

        push!(lines, "", "", _help_rule(style, string(letter, " · ", titles[num_chapters])))
        bookmarks[letter] = (length(lines), 1)
    end

    return lines, bookmarks
end

"""
    _manual_blocks(source::AbstractString) -> Vector{Vector{String}}

Split the `source` of the extended help into its blocks, each one with its lines. The blocks
are separated by blank lines, but an example, a figure, and a comment go from the line that
begins them to the line that ends them, with the blank lines between. The comments are not
returned.

# Arguments

- `source::AbstractString`: Source of the manual.
"""
function _manual_blocks(source::AbstractString)
    blocks = Vector{String}[]
    block = String[]

    # Text that ends the example, the figure, or the comment being read.
    closing = ""

    for line in eachsplit(source, '\n')
        if isempty(closing) && isempty(block)
            if startswith(line, "```") || startswith(line, "~~~")
                closing = String(first(line, 3))
                push!(block, String(line))
                continue
            elseif startswith(line, "<!--")
                closing = "-->"
            end
        end

        if !isempty(closing)
            # An example and a figure end at the line with only the fence, and a comment
            # ends at the line that ends with its closing mark.
            push!(block, String(line))
            ended = closing == "-->" ? endswith(rstrip(line), closing) : line == closing
            ended || continue
            closing = ""
        elseif !isempty(line)
            push!(block, String(line))
            continue
        end

        if !isempty(block)
            startswith(first(block), "<!--") || push!(blocks, block)
            block = String[]
        end
    end

    isempty(block) || startswith(first(block), "<!--") || push!(blocks, block)

    return blocks
end

"""
    _manual_letter(i::Int) -> Char

Return the letter of the `i`-th chapter of the extended help, which is its bookmark.

# Arguments

- `i::Int`: One-based index of the chapter.
"""
_manual_letter(i::Int) = Char(Int('a') + i - 1)

"""
    _manual_contents!(lines::Vector{String}, titles::Vector{String}, style::HelpStyle) ->
        Nothing

Append to `lines` the table of contents of the extended help: the letter of each chapter,
drawn as a key cap, and its title, in two columns that are read downwards.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `titles::Vector{String}`: Titles of the chapters.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_contents!(lines::Vector{String}, titles::Vector{String}, style::HelpStyle)
    num_chapters = length(titles)
    num_rows = cld(num_chapters, 2)
    column_width = (_HELP_WIDTH - 2 * _HELP_MARGIN) ÷ 2

    push!(lines, string(" "^_HELP_MARGIN, style.section, "CONTENTS", style.reset), "")

    for row in 1:num_rows
        buf = IOBuffer()
        _write_blanks(buf, _HELP_MARGIN + 1)
        used = _write_manual_contents_entry!(buf, titles, row, style)

        # The second column starts at a fixed position.
        if row + num_rows <= num_chapters
            _write_blanks(buf, column_width - used)
            _write_manual_contents_entry!(buf, titles, row + num_rows, style)
        end

        push!(lines, String(take!(buf)))
    end

    return nothing
end

"""
    _write_manual_contents_entry!(
        io::IO,
        titles::Vector{String},
        i::Int,
        style::HelpStyle
    ) -> Int

Write to `io` the entry of the `i`-th chapter in the table of contents of the extended
help, which is its letter drawn as a key cap and its title, and return the printable width
that was written.

# Arguments

- `io::IO`: Output stream to update.
- `titles::Vector{String}`: Titles of the chapters.
- `i::Int`: One-based index of the chapter.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _write_manual_contents_entry!(
    io::IO, titles::Vector{String}, i::Int, style::HelpStyle
)
    atoms = HelpAtom[
        HelpAtom(string(_manual_letter(i)), :key, false),
        HelpAtom(titles[i], :plain, false),
    ]

    return _write_help_atoms!(io, atoms, style)
end

############################################################################################
#                                          Blocks                                          #
############################################################################################

"""
    _manual_block!(lines::Vector{String}, block::Vector{String}, style::HelpStyle) ->
        Nothing

Append to `lines` the `block` of the source of the extended help, laid out as its first line
tells and decorated with `style`. See [`_manual_lines`](@ref) for the kinds of blocks.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::Vector{String}`: Lines of the block in the source, which is not a chapter.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_block!(lines::Vector{String}, block::Vector{String}, style::HelpStyle)
    head = first(block)
    section = style.section
    reset = style.reset

    if startswith(head, "## ")
        title = SubString(head, 4)
        push!(lines, string(" "^_HELP_MARGIN, section, "▌ ", title, reset))
    elseif startswith(head, '|')
        rows = _manual_table(block)

        if !isempty(rows) && startswith(first(rows)[1], "<kbd>")
            _manual_keys!(lines, rows, style)
        else
            _manual_definitions!(lines, rows, style)
        end
    elseif startswith(head, "- ")
        for item in _manual_rows(block, 2)
            _help_text!(lines, item, style, string("  ", section, "• ", reset), "    ")
        end
    elseif occursin(r"^\d+\. ", head)
        for (i, item) in enumerate(_manual_rows(block, 3))
            _help_text!(lines, item, style, string("  ", section, i, ". ", reset), "     ")
        end
    elseif startswith(head, '>')
        _manual_box!(lines, block, style)
    elseif startswith(head, "```")
        _manual_example!(lines, block, style)
    elseif startswith(head, "~~~")
        for i in 2:(length(block) - 1)
            art, label = _manual_split(block[i], "  # ")
            buf = IOBuffer()
            _write_blanks(buf, _HELP_MARGIN + 2)
            write(buf, art)
            isempty(label) || write(buf, "  ", style.dim, label, reset)
            push!(lines, String(take!(buf)))
        end
    else
        _help_text!(lines, join(block, ' '), style, "", "")
    end

    return nothing
end

"""
    _manual_split(line::AbstractString, separator::String) -> Tuple{String, String}

Split `line` at the first `separator` and return what is before it and what is after it,
without its leading blanks. Without a separator, return `line` without its trailing blanks
and an empty string.

# Arguments

- `line::AbstractString`: Line of the source of the manual.
- `separator::String`: Text that separates the two parts.
"""
function _manual_split(line::AbstractString, separator::String)
    range = findfirst(separator, line)
    isnothing(range) && return String(rstrip(line)), ""

    before = SubString(line, firstindex(line), prevind(line, first(range)))
    after = SubString(line, nextind(line, Base.last(range)))

    return String(before), String(lstrip(after))
end

"""
    _manual_rows(block::Vector{String}, prefix::Int) -> Vector{String}

Return the items of `block`, which is a list in the source of the extended help. An item
begins at a line that does not begin with a blank, without its first `prefix` characters,
and it continues on the following lines that do.

# Arguments

- `block::Vector{String}`: Lines of the block in the source.
- `prefix::Int`: Number of characters of the mark that begins each row.
"""
function _manual_rows(block::Vector{String}, prefix::Int)
    rows = String[]

    for line in block
        if startswith(line, ' ') && !isempty(rows)
            rows[end] = string(rows[end], ' ', lstrip(line))
        else
            push!(rows, String(chop(line; head = prefix, tail = 0)))
        end
    end

    return rows
end

"""
    _manual_table(block::Vector{String}) -> Vector{Tuple{String, String}}

Return the rows of `block`, which is a table in the source of the extended help, each one
with its first two cells. The first two lines, which are the header and the delimiter of
the table, are skipped. A term written as code, in the first cell, loses its backticks.

# Arguments

- `block::Vector{String}`: Lines of the block in the source.
"""
function _manual_table(block::Vector{String})
    rows = Tuple{String, String}[]

    for i in 3:length(block)
        cells = _manual_cells(block[i])
        isempty(cells) && continue

        head = first(cells)
        description = length(cells) > 1 ? cells[2] : ""

        if (ncodeunits(head) > 1) && startswith(head, '`') && endswith(head, '`')
            head = String(chop(head; head = 1, tail = 1))
        end

        push!(rows, (head, description))
    end

    return rows
end

"""
    _manual_cells(row::AbstractString) -> Vector{String}

Return the cells of `row`, which is a line of a table in the source of the extended help,
without the blanks around them. The cells are separated by bars, the bars that begin and
end the row are optional, and `\\|` is a bar inside a cell.

# Arguments

- `row::AbstractString`: Line of the table.
"""
function _manual_cells(row::AbstractString)
    cells = String[]
    cell = IOBuffer()
    line = strip(row)
    escaped = false

    for c in line
        if escaped
            # The backslash is kept unless it escapes a bar.
            (c == '|') || write(cell, "\\")
            write(cell, string(c))
            escaped = false
        elseif c == '\\'
            escaped = true
        elseif c == '|'
            push!(cells, String(strip(String(take!(cell)))))
        else
            write(cell, string(c))
        end
    end

    escaped && write(cell, "\\")
    rest = String(strip(String(take!(cell))))
    isempty(rest) || push!(cells, rest)

    # The bar that begins the row has nothing before it.
    startswith(line, '|') && !isempty(cells) && popfirst!(cells)

    return cells
end

"""
    _manual_key_names(cell::String) -> String

Return the names shown in a key table for `cell`, which has keys written as `<kbd>Key</kbd>`
and actions written as `<kbd>:action</kbd>`, separated by commas. A text without those marks
is returned as it is.

# Arguments

- `cell::String`: First cell of a row of a key table.
"""
function _manual_key_names(cell::String)
    buf = IOBuffer()
    i = firstindex(cell)

    while true
        opening = findnext("<kbd>", cell, i)
        isnothing(opening) && break
        closing = findnext("</kbd>", cell, Base.last(opening) + 1)
        isnothing(closing) && break

        key = SubString(cell, Base.last(opening) + 1, prevind(cell, first(closing)))
        (position(buf) > 0) && write(buf, ", ")
        write(buf, startswith(key, ':') ? _manual_action_keys(key) : String(key))
        i = Base.last(closing) + 1
    end

    return position(buf) > 0 ? String(take!(buf)) : cell
end

"""
    _manual_action_keys(action::AbstractString) -> String

Return the keys shown in a key table for `action`, which is written as `:action`: its
shortest keys, at most `_MANUAL_MAX_KEYS` and as many as fit in the key column, or a dash
if no key is bound to it.

# Arguments

- `action::AbstractString`: Action written as `:action`.
"""
function _manual_action_keys(action::AbstractString)
    names = _keyboard_keys(Symbol(SubString(action, 2)))
    isempty(names) && return "—"

    shown = names[1]

    for i in 2:min(length(names), _MANUAL_MAX_KEYS)
        (textwidth(shown) + 2 + textwidth(names[i]) > _MANUAL_KEY_WIDTH) && break
        shown = string(shown, ", ", names[i])
    end

    return shown
end

"""
    _manual_keys!(
        lines::Vector{String},
        rows::Vector{Tuple{String, String}},
        style::HelpStyle
    ) -> Nothing

Append to `lines` a table with the keys of `rows` and their descriptions. The table has two
columns of keys, read from the left to the right, if every description fits in one line of
half the width. Otherwise, it has one key per row and the descriptions are wrapped.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `rows::Vector{Tuple{String, String}}`: Cells with the keys, as
    [`_manual_key_names`](@ref) receives them, and their descriptions.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_keys!(
    lines::Vector{String}, rows::Vector{Tuple{String, String}}, style::HelpStyle
)
    num_rows = length(rows)
    names = String[_manual_key_names(row[1]) for row in rows]
    descriptions = Vector{HelpAtom}[_help_atoms(row[2]) for row in rows]
    key_width = 0
    description_width = 0

    for i in 1:num_rows
        key_width = max(key_width, textwidth(names[i]))
        description_width = max(description_width, _help_atoms_width(descriptions[i]))
    end

    # A column of the table with two of them has the key, two blanks, and the description,
    # and the columns are separated by three blanks. The table is indented by two columns.
    column_width = (_HELP_WIDTH - 2 * _HELP_MARGIN - 2 - 3) ÷ 2
    two_columns = (num_rows > 1) && (key_width + 2 + description_width <= column_width)
    reset = style.reset

    if !two_columns
        indent = " "^(2 + key_width + 2)

        for i in 1:num_rows
            padding = " "^(key_width - textwidth(names[i]) + 2)
            first_indent = string("  ", style.key, names[i], reset, padding)
            _help_text!(lines, rows[i][2], style, first_indent, indent)
        end

        return nothing
    end

    for first_row in 1:2:num_rows
        buf = IOBuffer()
        _write_blanks(buf, _HELP_MARGIN + 2)

        for i in first_row:min(first_row + 1, num_rows)
            write(buf, style.key, names[i], reset)
            _write_blanks(buf, key_width - textwidth(names[i]) + 2)
            used = _write_help_atoms!(buf, descriptions[i], style)

            # The second column starts at a fixed position.
            (i == first_row) &&
                (i < num_rows) &&
                _write_blanks(buf, column_width - key_width - 2 - used + 3)
        end

        push!(lines, String(take!(buf)))
    end

    return nothing
end

"""
    _manual_definitions!(
        lines::Vector{String},
        rows::Vector{Tuple{String, String}},
        style::HelpStyle
    ) -> Nothing

Append to `lines` the terms of `rows`, written as code, and their descriptions. The
descriptions are at the side of the terms if no term is wider than `_MANUAL_TERM_WIDTH`.
Otherwise, each description is below its term, and the items are separated by blank lines.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `rows::Vector{Tuple{String, String}}`: Terms and their descriptions.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_definitions!(
    lines::Vector{String}, rows::Vector{Tuple{String, String}}, style::HelpStyle
)
    term_width = 0

    for (term, _) in rows
        term_width = max(term_width, textwidth(term))
    end

    aside = term_width <= _MANUAL_TERM_WIDTH
    indent = aside ? " "^(2 + term_width + 2) : " "^6

    for (i, (term, description)) in enumerate(rows)
        code = string("  ", style.code, term, style.reset)

        if aside
            padding = " "^(term_width - textwidth(term) + 2)
            _help_text!(lines, description, style, string(code, padding), indent)
        else
            (i > 1) && push!(lines, "")
            push!(lines, string(" "^_HELP_MARGIN, code))
            _help_text!(lines, description, style, indent, indent)
        end
    end

    return nothing
end

"""
    _manual_box!(lines::Vector{String}, block::Vector{String}, style::HelpStyle) -> Nothing

Append to `lines` the remark in `block`, whose lines begin with `>`: a rounded box with the
wrapped text inside it. If the first line is an alert, like `[!TIP]`, the top border has its
name in the color of its kind: `TIP` is a tip, `WARNING` and `CAUTION` are warnings, and
every other one is a note.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::Vector{String}`: Lines of the remark in the source.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_box!(lines::Vector{String}, block::Vector{String}, style::HelpStyle)
    kind = ""
    text = ""

    for (i, line) in enumerate(block)
        quoted = startswith(line, '>') ? chop(line; head = 1, tail = 0) : line
        content = String(strip(quoted))

        if (i == 1) && startswith(content, "[!") && endswith(content, ']')
            kind = String(chop(content; head = 2, tail = 1))
        elseif !isempty(content)
            text = isempty(text) ? content : string(text, ' ', content)
        end
    end

    color = if kind == "TIP"
        style.tip
    elseif (kind == "WARNING") || (kind == "CAUTION")
        style.warning
    else
        style.note
    end

    title = uppercasefirst(lowercase(kind))

    # The text has one blank between it and each border.
    width = _HELP_WIDTH - 2 * _HELP_MARGIN
    text_width = width - 4
    border = style.border
    reset = style.reset

    buf = IOBuffer()
    _write_blanks(buf, _HELP_MARGIN)

    if isempty(title)
        write(buf, border, "╭", "─"^(width - 2), "╮", reset)
    else
        write(buf, border, "╭─ ", reset, color, title, reset, border, " ")
        write(buf, "─"^(width - textwidth(title) - 5), "╮", reset)
    end

    push!(lines, String(take!(buf)))

    for row in _wrap_help_atoms(_help_atoms(text), text_width)
        _write_blanks(buf, _HELP_MARGIN)
        write(buf, border, "│", reset, " ")
        used = _write_help_atoms!(buf, row, style)
        _write_blanks(buf, text_width - used + 1)
        write(buf, border, "│", reset)
        push!(lines, String(take!(buf)))
    end

    push!(lines, string(" "^_HELP_MARGIN, border, "╰", "─"^(width - 2), "╯", reset))

    return nothing
end

"""
    _manual_example!(lines::Vector{String}, block::Vector{String}, style::HelpStyle) ->
        Nothing

Append to `lines` the example in `block`: its title, which is written as `title="..."` in
the line that begins it, and its lines of code at the right of a border, each one followed
by its comment. The comments are aligned in a column.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::Vector{String}`: Lines of the example in the source, with the lines that begin
    and end it.
- `style::HelpStyle`: Escape sequences that decorate the manual.
"""
function _manual_example!(lines::Vector{String}, block::Vector{String}, style::HelpStyle)
    margin = " "^_HELP_MARGIN
    border = style.border
    reset = style.reset
    title = _manual_example_title(first(block))
    code_width = 0

    for i in 2:(length(block) - 1)
        code = rstrip(_manual_split(block[i], "  # ")[1])
        code_width = max(code_width, textwidth(code))
    end

    if isempty(title)
        push!(lines, string(margin, border, "┌", reset))
    else
        push!(lines, string(margin, border, "┌ ", reset, style.strong, title, reset))
    end

    for i in 2:(length(block) - 1)
        padded_code, comment = _manual_split(block[i], "  # ")
        code = String(rstrip(padded_code))
        buf = IOBuffer()
        write(buf, margin, border, "│", reset)

        if !isempty(code)
            write(buf, " ", style.code, code, reset)

            if !isempty(comment)
                _write_blanks(buf, code_width - textwidth(code) + 3)
                write(buf, style.dim, comment, reset)
            end
        end

        push!(lines, String(take!(buf)))
    end

    push!(lines, string(margin, border, "└", reset))

    return nothing
end

"""
    _manual_example_title(head::AbstractString) -> String

Return the title of the example that begins at the line `head` of the source of the extended
help, which is written as `title="..."` after the language, or an empty string if it has
none.

# Arguments

- `head::AbstractString`: Line that begins the example.
"""
function _manual_example_title(head::AbstractString)
    opening = findfirst("title=\"", head)
    isnothing(opening) && return ""

    start = Base.last(opening) + 1
    stop = findnext('"', head, start)
    isnothing(stop) && return ""

    return String(SubString(head, start, prevind(head, stop)))
end
