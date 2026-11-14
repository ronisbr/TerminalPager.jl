## Description #############################################################################
#
# Extended help: a manual of the pager, shown inside the pager itself. This file contains
# the blocks the manual is written with, the renderer that lays them out for the width of
# the display, and the session that shows the result. The text of the manual is in
# `extended_help_content.jl`.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The manual is laid out for the width of the view when it is opened, between these bounds.
# Lines much longer than the upper bound are tiring to read.
const _MANUAL_MIN_WIDTH = 60
const _MANUAL_MAX_WIDTH = 96

# Blank columns at the left and at the right of the manual.
const _MANUAL_MARGIN = 2

# Largest width of the key column of a key table and of the term column of a definition
# list that has the descriptions at the side of the terms.
const _MANUAL_KEY_WIDTH = 16
const _MANUAL_TERM_WIDTH = 24

# Number of keys of an action shown in a key table.
const _MANUAL_MAX_KEYS = 3

############################################################################################
#                                          Types                                           #
############################################################################################

"""
    struct ManualBlock

Describe one block of a chapter of the extended help.

The kinds are a paragraph (`:paragraph`), a section title (`:heading`), a table of keys
(`:keys`), a list of terms and their descriptions (`:definitions`), a bulleted or a numbered
list (`:list` and `:steps`), a boxed remark (`:tip`, `:note`, and `:warning`), lines of code
with comments (`:example`), and preformatted lines with labels (`:figure`).

The texts, except the code and the preformatted lines, can mark `` `code` ``, `*strong*`
text, the key bound to an action as `{:action}`, and any other key as `{Key}`.

# Fields

- `kind::Symbol`: Kind of the block.
- `title::String`: Title of the block, for the kinds that have one.
- `text::String`: Text of the block, for the kinds that have one.
- `items::Vector{Pair{String, String}}`: Rows of the block, for the kinds that have them: a
    key and its description, a term and its description, a line of code and its comment, or
    a preformatted line and its label. The key of a key table is an action, written as
    `":action"`, or the name of a key.
"""
struct ManualBlock
    kind::Symbol
    title::String
    text::String
    items::Vector{Pair{String, String}}
end

"""
    struct ManualChapter

Describe one chapter of the extended help.

# Fields

- `title::String`: Title of the chapter.
- `blocks::Vector{ManualBlock}`: Blocks of the chapter.
"""
struct ManualChapter
    title::String
    blocks::Vector{ManualBlock}
end

"""
    struct ManualAtom

Represent an unbreakable piece of a text of the extended help.

# Fields

- `text::String`: Text of the piece.
- `style::Symbol`: Style of the piece: `:plain`, `:strong`, `:code`, `:key`, or `:dim`.
- `glued::Bool`: Whether the piece follows the previous one without a blank, in which case
    a line cannot be broken between them.
"""
struct ManualAtom
    text::String
    style::Symbol
    glued::Bool
end

"""
    struct ManualStyle

Store the escape sequences that decorate the extended help, which are all empty when the
terminal has no color support.

# Fields

- `title::String`: Title of the manual.
- `chapter::String`: Titles of the chapters.
- `strong::String`: Section titles and strong text.
- `key::String`: Keys of the key tables.
- `keycap::String`: Keys in the text, drawn as key caps.
- `code::String`: Code, commands, and names.
- `dim::String`: Comments, labels, and secondary text.
- `border::String`: Rules and box borders.
- `tip::String`: Tip boxes.
- `note::String`: Note boxes.
- `warning::String`: Warning boxes.
- `reset::String`: Reset of the attributes.
"""
struct ManualStyle
    title::String
    chapter::String
    strong::String
    key::String
    keycap::String
    code::String
    dim::String
    border::String
    tip::String
    note::String
    warning::String
    reset::String
end

"""
    ManualStyle(use_color::Bool, display_config::DisplayConfig) -> ManualStyle

Create the style of the extended help from the faces in `display_config`, or a style without
decorations if `use_color` is `false`.

# Arguments

- `use_color::Bool`: Decorate the manual with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
"""
function ManualStyle(use_color::Bool, display_config::DisplayConfig)
    use_color || return ManualStyle("", "", "", "", "", "", "", "", "", "", "", "")

    return ManualStyle(
        display_config.help_title,
        display_config.help_chapter,
        display_config.help_section,
        display_config.help_key,
        display_config.help_keycap,
        display_config.help_code,
        display_config.help_description,
        display_config.help_border,
        display_config.help_tip,
        display_config.help_note,
        display_config.help_warning,
        _SGR_RESET,
    )
end

"""
    struct ManualCache

Store the last rendered extended help and what it was rendered for.

# Fields

- `generation::Int`: Generation of the key bindings.
- `display_config::DisplayConfig`: Display configuration with the help faces.
- `use_color::Bool`: Whether the manual was decorated.
- `width::Int`: Width the manual was laid out for.
- `text::String`: Text of the manual.
- `layout::ViewLayout`: Prepared layout of the text.
- `bookmarks::Dict{Char, Tuple{Int, Int}}`: Line and column of each chapter, keyed by its
    letter.
"""
struct ManualCache
    generation::Int
    display_config::DisplayConfig
    use_color::Bool
    width::Int
    text::String
    layout::ViewLayout
    bookmarks::Dict{Char, Tuple{Int, Int}}
end

# The manual only depends on the key bindings, on the faces, and on the width. Hence, the
# last one that was rendered is kept.
const _MANUAL_CACHE = Ref{Union{Nothing, ManualCache}}(nothing)

############################################################################################
#                                         Session                                          #
############################################################################################

"""
    _extended_help!(pagerd::Pager) -> Nothing

Open a new pager with the extended help, laid out for the width of the display of `pagerd`,
and request a full repaint of `pagerd` after it is closed.

The session starts with one bookmark per chapter, which are the letters of the table of
contents, so that the keys bound to `:goto_bookmark` and a letter jump to a chapter. The
visual mode is available in it, so that the examples can be copied.

# Arguments

- `pagerd::Pager`: Parent pager state whose terminal and input are reused.
"""
function _extended_help!(pagerd::Pager)
    # The nested session must not toggle the alternate screen buffer, as explained in
    # `_help!`. A column ruler would only add noise to a text that is not a table.
    options = SessionOptions(;
        display_config = pagerd.display_config,
        has_help = false,
        input = pagerd.input,
        show_column_ruler = false,
        use_alternate_screen_buffer = false,
        manage_cursor_key_mode = false,
        manage_cursor = false,
        manage_mouse = false,
    )

    # The scrollbar of the nested session takes one column of the display.
    cols = pagerd.display_size[2] - (options.show_scrollbar ? 1 : 0)

    # The color flag must come from the session view buffer, as explained in `_help!`.
    manual = _manual(
        get(pagerd.buf, :color, true)::Bool, pagerd.display_config, _manual_width(cols)
    )

    options.text_layout = manual.layout
    options._bookmarks = manual.bookmarks

    _pager!(pagerd.term, manual.text, options)

    # The nested pager repainted the whole screen.
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)

    return nothing
end

"""
    _manual_width(cols::Int) -> Int

Return the width the extended help is laid out for in a view with `cols` columns.

# Arguments

- `cols::Int`: Number of columns of the view.
"""
_manual_width(cols::Int) = clamp(cols, _MANUAL_MIN_WIDTH, _MANUAL_MAX_WIDTH)

"""
    _manual(use_color::Bool, display_config::DisplayConfig, width::Int) -> ManualCache

Return the extended help laid out for `width` columns, with its prepared layout and the
bookmarks of its chapters, rendering it only when the key bindings, the faces, the color
support, or the width changed since the last call.

# Arguments

- `use_color::Bool`: Decorate the manual with ANSI escape sequences.
- `display_config::DisplayConfig`: Session display configuration with the help faces.
- `width::Int`: Number of columns of the manual.
"""
function _manual(use_color::Bool, display_config::DisplayConfig, width::Int)
    generation = _KEYBINDINGS_GENERATION[]
    cached = _MANUAL_CACHE[]

    if !isnothing(cached) &&
        (cached.generation == generation) &&
        (cached.display_config == display_config) &&
        (cached.use_color == use_color) &&
        (cached.width == width)
        return cached
    end

    lines, bookmarks = _manual_lines(
        _manual_chapters(), ManualStyle(use_color, display_config), width
    )

    manual = ManualCache(
        generation,
        display_config,
        use_color,
        width,
        join(lines, '\n'),
        ViewLayout(lines),
        bookmarks,
    )
    _MANUAL_CACHE[] = manual

    return manual
end

############################################################################################
#                                         Document                                         #
############################################################################################

"""
    _manual_lines(chapters::Vector{ManualChapter}, style::ManualStyle, width::Int) ->
        Vector{String}, Dict{Char, Tuple{Int, Int}}

Lay out the `chapters` of the extended help for `width` columns, decorated with `style`, and
return its lines together with the line and the column of the title of each chapter, keyed
by the letter the table of contents gives to it.

The manual begins with a banner, how to read it, and the table of contents. Each chapter
follows with its title on a rule and its blocks separated by blank lines. No line is wider
than `width`, unless a word or a line of code does not fit in it.

# Arguments

- `chapters::Vector{ManualChapter}`: Chapters of the manual, at most 26.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the manual.
"""
function _manual_lines(chapters::Vector{ManualChapter}, style::ManualStyle, width::Int)
    lines = String[]
    bookmarks = Dict{Char, Tuple{Int, Int}}()
    content_width = width - 2 * _MANUAL_MARGIN
    margin = " "^_MANUAL_MARGIN

    _manual_banner!(lines, style, content_width)
    push!(lines, "")

    intro = ManualBlock(
        :paragraph,
        "",
        "This is the manual of the pager, and it is shown by the pager itself, so every " *
            "key described here already works: scroll with {:down} and {:up}, search " *
            "with {:search}, and leave with {:quit}. Each chapter has a letter, which is " *
            "a bookmark: press {:goto_bookmark} and the letter to jump to the chapter, " *
            "and {:goto_bookmark} twice to return to where you were.",
        Pair{String, String}[],
    )
    _manual_block!(lines, intro, style, content_width)
    push!(lines, "")

    _manual_contents!(lines, chapters, style, content_width)

    for (i, chapter) in enumerate(chapters)
        letter = _manual_letter(i)
        title = string(letter, " · ", chapter.title)
        rule = "━"^max(content_width - textwidth(title) - 4, 0)

        push!(lines, "", "")
        push!(
            lines,
            string(
                margin,
                style.border,
                "━━ ",
                style.reset,
                style.chapter,
                title,
                style.reset,
                style.border,
                " ",
                rule,
                style.reset,
            ),
        )
        bookmarks[letter] = (length(lines), 1)

        for block in chapter.blocks
            push!(lines, "")
            _manual_block!(lines, block, style, content_width)
        end
    end

    ending = "· · ·"
    push!(lines, "", "")
    push!(
        lines,
        string(
            margin,
            " "^max((content_width - textwidth(ending)) ÷ 2, 0),
            style.dim,
            ending,
            style.reset,
        ),
    )

    return lines, bookmarks
end

"""
    _manual_letter(i::Int) -> Char

Return the letter of the `i`-th chapter of the extended help, which is its bookmark.

# Arguments

- `i::Int`: One-based index of the chapter.
"""
_manual_letter(i::Int) = Char(Int('a') + i - 1)

"""
    _manual_banner!(lines::Vector{String}, style::ManualStyle, width::Int) -> Nothing

Append to `lines` the banner of the extended help, which is a rounded box `width` columns
wide with the name and the version of the package and what the document is.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_banner!(lines::Vector{String}, style::ManualStyle, width::Int)
    margin = " "^_MANUAL_MARGIN
    name = string("TerminalPager.jl ", _pkg_version())
    subtitle = "Extended help"
    separator = "  ·  "
    inner = width - 2
    used = 2 + textwidth(name) + textwidth(separator) + textwidth(subtitle)

    push!(lines, string(margin, style.border, "╭", "─"^inner, "╮", style.reset))
    push!(
        lines,
        string(
            margin,
            style.border,
            "│",
            style.reset,
            "  ",
            style.title,
            name,
            style.reset,
            style.dim,
            separator,
            style.reset,
            style.strong,
            subtitle,
            style.reset,
            " "^max(inner - used, 0),
            style.border,
            "│",
            style.reset,
        ),
    )
    push!(lines, string(margin, style.border, "╰", "─"^inner, "╯", style.reset))

    return nothing
end

"""
    _manual_contents!(
        lines::Vector{String},
        chapters::Vector{ManualChapter},
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` the table of contents of the extended help: the letter of each chapter,
drawn as a key cap, and its title, in two columns that are read downwards, or in one column
if the titles do not fit in half the `width`.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `chapters::Vector{ManualChapter}`: Chapters of the manual.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_contents!(
    lines::Vector{String}, chapters::Vector{ManualChapter}, style::ManualStyle, width::Int
)
    margin = " "^_MANUAL_MARGIN
    num_chapters = length(chapters)

    # An entry is a blank, the key cap of the letter, a blank, and the title.
    entry_width(i) = 5 + textwidth(chapters[i].title)

    # The two columns are used only if every entry fits in its half of the width.
    column_width = width ÷ 2
    num_rows = cld(num_chapters, 2)
    two_columns =
        all(i -> entry_width(i) + 2 <= column_width, 1:num_rows) &&
        all(i -> entry_width(i) <= width - column_width, (num_rows + 1):num_chapters)
    two_columns || (num_rows = num_chapters)

    push!(lines, string(margin, style.strong, "CONTENTS", style.reset), "")

    for row in 1:num_rows
        buf = IOBuffer()
        write(buf, margin)
        used = 0

        for i in (row, row + num_rows)
            i > num_chapters && continue

            # The second column starts at a fixed position.
            (i > row) && _write_blanks(buf, column_width - used)

            atoms = [
                ManualAtom(string(_manual_letter(i)), :key, false),
                ManualAtom(chapters[i].title, :plain, false),
            ]

            write(buf, UInt8(' '))
            used = 1 + _write_manual_atoms!(buf, atoms, style)
        end

        push!(lines, String(take!(buf)))
    end

    return nothing
end

############################################################################################
#                                          Blocks                                          #
############################################################################################

"""
    _manual_block!(
        lines::Vector{String},
        block::ManualBlock,
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` the `block` of the extended help laid out for a content `width` columns
wide and decorated with `style`. Every line starts with the margin of the manual.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::ManualBlock`: Block to lay out.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.

# Extended help

## Throws

- `ArgumentError`: If the kind of `block` is not known.
"""
function _manual_block!(
    lines::Vector{String}, block::ManualBlock, style::ManualStyle, width::Int
)
    kind = block.kind

    if kind === :paragraph
        _manual_text!(lines, block.text, style, width, "", "")
    elseif kind === :heading
        mark = string(style.chapter, "▌", style.reset, " ")
        title = string(style.strong, block.title, style.reset)
        push!(lines, string(" "^_MANUAL_MARGIN, mark, title))
    elseif kind === :keys
        _manual_keys!(lines, block.items, style, width)
    elseif kind === :definitions
        _manual_definitions!(lines, block.items, style, width)
    elseif (kind === :list) || (kind === :steps)
        for (i, item) in enumerate(block.items)
            bullet = kind === :steps ? string(i, ". ") : "• "
            first_indent = string("  ", style.chapter, bullet, style.reset)
            indent = " "^(2 + textwidth(bullet))
            _manual_text!(lines, item.second, style, width, first_indent, indent)
        end
    elseif (kind === :tip) || (kind === :note) || (kind === :warning)
        _manual_box!(lines, block, style, width)
    elseif kind === :example
        _manual_example!(lines, block, style, width)
    elseif kind === :figure
        for (art, label) in block.items
            if isempty(label)
                push!(lines, string(" "^_MANUAL_MARGIN, "  ", rstrip(art)))
            else
                push!(
                    lines,
                    string(
                        " "^_MANUAL_MARGIN, "  ", art, "  ", style.dim, label, style.reset
                    ),
                )
            end
        end
    else
        throw(ArgumentError("The kind `$kind` is not a block of the extended help."))
    end

    return nothing
end

"""
    _manual_text!(
        lines::Vector{String},
        text::String,
        style::ManualStyle,
        width::Int,
        first_indent::String,
        indent::String
    ) -> Nothing

Append to `lines` the marked `text` wrapped so that it fits in `width` columns. The first
line starts with `first_indent`, which can be decorated, and the others with `indent`, both
after the margin of the manual and both with the same printable width.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `text::String`: Text to lay out, with the marks of [`ManualBlock`](@ref).
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
- `first_indent::String`: Beginning of the first line.
- `indent::String`: Beginning of the other lines.
"""
function _manual_text!(
    lines::Vector{String},
    text::String,
    style::ManualStyle,
    width::Int,
    first_indent::String,
    indent::String,
)
    margin = " "^_MANUAL_MARGIN
    rows = _wrap_manual_atoms(_manual_atoms(text), width - textwidth(indent))

    for (i, row) in enumerate(rows)
        buf = IOBuffer()
        write(buf, margin, i == 1 ? first_indent : indent)
        _write_manual_atoms!(buf, row, style)
        push!(lines, String(take!(buf)))
    end

    return nothing
end

"""
    _manual_key_names(key::String) -> String

Return the names shown in a key table for `key`, which is the name of a key or an action
written as `":action"`. An action shows its shortest keys, at most `_MANUAL_MAX_KEYS` and as
many as fit in the key column, or a dash if no key is bound to it.

# Arguments

- `key::String`: Name of a key, or an action written as `":action"`.
"""
function _manual_key_names(key::String)
    startswith(key, ':') || return key

    names = _manual_action_keys(Symbol(SubString(key, 2)))
    isempty(names) && return "—"

    shown = names[1]

    for name in names[2:min(end, _MANUAL_MAX_KEYS)]
        (textwidth(shown) + 2 + textwidth(name) > _MANUAL_KEY_WIDTH) && break
        shown = string(shown, ", ", name)
    end

    return shown
end

"""
    _manual_keys!(
        lines::Vector{String},
        items::Vector{Pair{String, String}},
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` a table with the keys of `items` and their descriptions. The table has two
columns of keys, read from the left to the right, if every description fits in one line of
half the `width`. Otherwise, it has one key per row and the descriptions are wrapped.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `items::Vector{Pair{String, String}}`: Keys, as described in [`ManualBlock`](@ref), and
    their descriptions.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_keys!(
    lines::Vector{String},
    items::Vector{Pair{String, String}},
    style::ManualStyle,
    width::Int,
)
    margin = " "^_MANUAL_MARGIN
    names = String[_manual_key_names(item.first) for item in items]
    descriptions = [_manual_atoms(item.second) for item in items]
    key_width = maximum(textwidth, names; init = 0)
    indent = 2
    gap = 2

    # Width of a column of the table with two of them, which are separated by three blanks.
    column_width = (width - indent - 3) ÷ 2
    description_width = column_width - key_width - gap
    two_columns =
        (length(items) > 1) &&
        all(atoms -> _manual_atoms_width(atoms) <= description_width, descriptions)

    if two_columns
        for first_item in 1:2:length(items)
            buf = IOBuffer()
            write(buf, margin)
            _write_blanks(buf, indent)

            for i in first_item:min(first_item + 1, length(items))
                write(buf, style.key, names[i], style.reset)
                _write_blanks(buf, key_width - textwidth(names[i]) + gap)
                used = _write_manual_atoms!(buf, descriptions[i], style)

                # The second column starts at a fixed position.
                isodd(i) && (i < length(items)) &&
                    _write_blanks(buf, description_width - used + 3)
            end

            push!(lines, String(take!(buf)))
        end

        return nothing
    end

    description_indent = " "^(indent + key_width + gap)

    for i in eachindex(items)
        first_indent = string(
            " "^indent,
            style.key,
            names[i],
            style.reset,
            " "^(key_width - textwidth(names[i]) + gap),
        )

        _manual_text!(
            lines, items[i].second, style, width, first_indent, description_indent
        )
    end

    return nothing
end

"""
    _manual_definitions!(
        lines::Vector{String},
        items::Vector{Pair{String, String}},
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` the terms of `items`, written as code, and their descriptions. The
descriptions are at the side of the terms if no term is wider than `_MANUAL_TERM_WIDTH`.
Otherwise, each description is below its term, and the items are separated by blank lines.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `items::Vector{Pair{String, String}}`: Terms and their descriptions.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_definitions!(
    lines::Vector{String},
    items::Vector{Pair{String, String}},
    style::ManualStyle,
    width::Int,
)
    margin = " "^_MANUAL_MARGIN
    term_width = maximum(item -> textwidth(item.first), items; init = 0)
    indent = 2
    gap = 2

    if term_width <= _MANUAL_TERM_WIDTH
        description_indent = " "^(indent + term_width + gap)

        for (term, description) in items
            first_indent = string(
                " "^indent,
                style.code,
                term,
                style.reset,
                " "^(term_width - textwidth(term) + gap),
            )

            _manual_text!(
                lines, description, style, width, first_indent, description_indent
            )
        end

        return nothing
    end

    description_indent = " "^(indent + 4)

    for (i, (term, description)) in enumerate(items)
        (i > 1) && push!(lines, "")
        push!(lines, string(margin, " "^indent, style.code, term, style.reset))
        _manual_text!(
            lines, description, style, width, description_indent, description_indent
        )
    end

    return nothing
end

"""
    _manual_box!(
        lines::Vector{String},
        block::ManualBlock,
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` the remark `block`, which is a tip, a note, or a warning: a rounded box
`width` columns wide with the name of the kind on its top border, both in the color of the
kind, and the wrapped text inside it.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::ManualBlock`: Remark to lay out.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_box!(
    lines::Vector{String}, block::ManualBlock, style::ManualStyle, width::Int
)
    margin = " "^_MANUAL_MARGIN
    kind = block.kind
    color = kind === :tip ? style.tip : (kind === :note ? style.note : style.warning)
    title = kind === :tip ? "Tip" : (kind === :note ? "Note" : "Warning")

    # The text has one blank between it and each border.
    text_width = width - 4
    top_rule = "─"^max(width - textwidth(title) - 5, 0)

    push!(lines, string(margin, color, "╭─ ", title, " ", top_rule, "╮", style.reset))

    for row in _wrap_manual_atoms(_manual_atoms(block.text), text_width)
        buf = IOBuffer()
        write(buf, margin, color, "│", style.reset, " ")
        used = _write_manual_atoms!(buf, row, style)
        _write_blanks(buf, text_width - used + 1)
        write(buf, color, "│", style.reset)
        push!(lines, String(take!(buf)))
    end

    push!(lines, string(margin, color, "╰", "─"^max(width - 2, 0), "╯", style.reset))

    return nothing
end

"""
    _manual_example!(
        lines::Vector{String},
        block::ManualBlock,
        style::ManualStyle,
        width::Int
    ) -> Nothing

Append to `lines` the example `block`: its title, and its lines of code at the right of a
border, each one followed by its comment. The comments are aligned in a column if they fit
in `width` columns at the side of the widest line of code. Otherwise, each comment is
written above its line of code, after a `#`.

# Arguments

- `lines::Vector{String}`: Lines of the manual, which are appended.
- `block::ManualBlock`: Example to lay out.
- `style::ManualStyle`: Escape sequences that decorate the manual.
- `width::Int`: Number of columns of the content of the manual.
"""
function _manual_example!(
    lines::Vector{String}, block::ManualBlock, style::ManualStyle, width::Int
)
    margin = " "^_MANUAL_MARGIN
    border = string(margin, style.border, "│", style.reset)
    items = block.items
    title = isempty(block.title) ? "Example" : block.title
    gap = 3

    code_width = maximum(item -> textwidth(item.first), items; init = 0)
    comment_width = maximum(item -> textwidth(item.second), items; init = 0)
    aside = (comment_width == 0) || (2 + code_width + gap + comment_width <= width)

    push!(
        lines,
        string(margin, style.border, "┌ ", style.reset, style.strong, title, style.reset),
    )

    for (code, comment) in items
        if isempty(code) && isempty(comment)
            push!(lines, border)
        elseif isempty(comment)
            push!(lines, string(border, " ", style.code, code, style.reset))
        elseif aside
            padding = " "^(code_width - textwidth(code) + gap)
            push!(
                lines,
                string(
                    border,
                    " ",
                    style.code,
                    code,
                    style.reset,
                    padding,
                    style.dim,
                    comment,
                    style.reset,
                ),
            )
        else
            push!(lines, string(border, " ", style.dim, "# ", comment, style.reset))
            isempty(code) ||
                push!(lines, string(border, " ", style.code, code, style.reset))
        end
    end

    push!(lines, string(margin, style.border, "└", style.reset))

    return nothing
end

############################################################################################
#                                           Text                                           #
############################################################################################

"""
    _manual_atoms(text::String) -> Vector{ManualAtom}

Split the marked `text` of the extended help into its unbreakable pieces.

The words are separated by blanks. A text between backticks is one piece of code, in which
nothing else is marked. `{:action}` is the shortest key bound to the action, or `unbound` if
there is none, and `{Key}` is the key with that name, both drawn as key caps. The words
between asterisks are strong.

# Arguments

- `text::String`: Text with the marks of [`ManualBlock`](@ref).
"""
function _manual_atoms(text::String)
    atoms = ManualAtom[]
    word = IOBuffer()
    strong = false
    glued = false

    # Add the word read so far, if any, as a piece.
    function flush_word!()
        position(word) == 0 && return nothing
        push!(atoms, ManualAtom(String(take!(word)), strong ? :strong : :plain, glued))
        glued = true
        return nothing
    end

    i = firstindex(text)
    last_index = lastindex(text)

    while i <= last_index
        c = text[i]

        if isspace(c)
            flush_word!()
            glued = false
        elseif (c == '`') || (c == '{')
            flush_word!()
            stop = findnext(c == '`' ? '`' : '}', text, nextind(text, i))

            # An unbalanced mark is written as it is.
            if isnothing(stop)
                write(word, c)
            else
                content = String(SubString(text, nextind(text, i), prevind(text, stop)))

                if c == '`'
                    push!(atoms, ManualAtom(content, :code, glued))
                else
                    push!(atoms, ManualAtom(_manual_key_name(content), :key, glued))
                end

                glued = true
                i = stop
            end
        elseif c == '*'
            flush_word!()
            strong = !strong
        else
            write(word, c)
        end

        i = nextind(text, i)
    end

    flush_word!()

    return atoms
end

"""
    _manual_key_name(key::String) -> String

Return the name of the key marked as `{key}` in a text of the extended help: the shortest
key bound to the action if `key` is written as `:action`, or `unbound` if there is none, and
`key` itself otherwise.

# Arguments

- `key::String`: Name of a key, or an action written as `:action`.
"""
function _manual_key_name(key::String)
    startswith(key, ':') || return key
    names = _manual_action_keys(Symbol(SubString(key, 2)))
    return isempty(names) ? "unbound" : first(names)
end

"""
    _manual_action_keys(action::Symbol) -> Vector{String}

Return the names of the keys bound to `action` that the extended help shows, from the
shortest to the longest one. The mouse events are left out if a key is also bound to the
action, because the manual explains the actions with the keyboard.

# Arguments

- `action::Symbol`: Pager action.
"""
function _manual_action_keys(action::Symbol)
    names = _action_keys(action)
    keys = filter(name -> !occursin("Wheel", name) && !occursin("Click", name), names)
    return isempty(keys) ? names : keys
end

"""
    _manual_atom_width(atom::ManualAtom) -> Int

Return the printable width of `atom`. A key cap has one blank at each side of the key.

# Arguments

- `atom::ManualAtom`: Piece of a text.
"""
function _manual_atom_width(atom::ManualAtom)
    return textwidth(atom.text) + (atom.style === :key ? 2 : 0)
end

"""
    _manual_atoms_width(atoms::Vector{ManualAtom}) -> Int

Return the printable width of `atoms` written in one line, with one blank before every piece
that is not glued to the previous one.

# Arguments

- `atoms::Vector{ManualAtom}`: Pieces of a text.
"""
function _manual_atoms_width(atoms::Vector{ManualAtom})
    width = 0

    for (i, atom) in enumerate(atoms)
        width += _manual_atom_width(atom) + (((i > 1) && !atom.glued) ? 1 : 0)
    end

    return width
end

"""
    _wrap_manual_atoms(atoms::Vector{ManualAtom}, width::Int) -> Vector{Vector{ManualAtom}}

Wrap `atoms` greedily into rows of at most `width` columns, breaking only before a piece
that is not glued to the previous one. Pieces that do not fit in `width` get a row of their
own. No piece yields no row.

# Arguments

- `atoms::Vector{ManualAtom}`: Pieces of a text.
- `width::Int`: Maximum width of a row.
"""
function _wrap_manual_atoms(atoms::Vector{ManualAtom}, width::Int)
    rows = Vector{ManualAtom}[]
    row = ManualAtom[]
    row_width = 0
    num_atoms = length(atoms)
    i = 1

    while i <= num_atoms
        # A word is a piece and the ones glued to it.
        stop = i

        while (stop < num_atoms) && atoms[stop + 1].glued
            stop += 1
        end

        word_width = sum(_manual_atom_width, view(atoms, i:stop))

        if !isempty(row) && (row_width + 1 + word_width > width)
            push!(rows, row)
            row = ManualAtom[]
            row_width = 0
        end

        row_width += word_width + (isempty(row) ? 0 : 1)
        append!(row, view(atoms, i:stop))
        i = stop + 1
    end

    isempty(row) || push!(rows, row)

    return rows
end

"""
    _write_manual_atoms!(io::IO, atoms::Vector{ManualAtom}, style::ManualStyle) -> Int

Write `atoms` to `io` in one line, decorated with `style`, and return the printable width
that was written. A piece that is not glued to the previous one is preceded by a blank, but
for the first one.

A key is drawn as a key cap, which is the key between two blanks with the background of the
face. Without colors, it is written between brackets instead, with the same width.

# Arguments

- `io::IO`: Output stream to update.
- `atoms::Vector{ManualAtom}`: Pieces of a text.
- `style::ManualStyle`: Escape sequences that decorate the manual.
"""
function _write_manual_atoms!(io::IO, atoms::Vector{ManualAtom}, style::ManualStyle)
    width = 0

    for (i, atom) in enumerate(atoms)
        if (i > 1) && !atom.glued
            write(io, UInt8(' '))
            width += 1
        end

        text = atom.text
        kind = atom.style

        if kind === :key
            if isempty(style.keycap)
                write(io, UInt8('['), text, UInt8(']'))
            else
                write(io, style.keycap, UInt8(' '), text, UInt8(' '), style.reset)
            end
        elseif kind === :plain
            write(io, text)
        else
            decoration = if kind === :code
                style.code
            elseif kind === :strong
                style.strong
            else
                style.dim
            end

            write(io, decoration, text, style.reset)
        end

        width += _manual_atom_width(atom)
    end

    return width
end
