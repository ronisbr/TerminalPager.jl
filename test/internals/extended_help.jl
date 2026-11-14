## Description #############################################################################
#
# Tests for the extended help, which is the manual shown inside the pager, and for the text
# marks it shares with the help screen.
#
############################################################################################

"""
    _manual_plain(source::AbstractString) -> Vector{String}

Return the lines of the `source` of a manual laid out without decorations.
"""
function _manual_plain(source::AbstractString)
    style = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())
    return TerminalPager._manual_lines(source, style)[1]
end

"""
    _manual_block_lines(source::AbstractString) -> Vector{String}

Return the lines of the block in `source` laid out without decorations.
"""
function _manual_block_lines(source::AbstractString)
    lines = String[]
    style = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())
    block = only(TerminalPager._manual_blocks(source))
    TerminalPager._manual_block!(lines, block, style)
    return lines
end

"""
    _keycap_style(face::TerminalPager.Face) -> TerminalPager.HelpStyle

Return the decorated style of the help screens with `face` as the face of the key caps.
"""
function _keycap_style(face::TerminalPager.Face)
    config = TerminalPager._display_config() do name
        name === :help_keycap ? face : TerminalPager._default_face(name)
    end

    return TerminalPager.HelpStyle(true, config)
end

@testset "Extended Help Key Binding and Feature Gate" begin
    key = ("H", false, false, false)
    @test TerminalPager._DEFAULT_KEYBINDINGS[key] == :extended_help
    @test :extended_help in TerminalPager._ACTIONS

    # The manual needs the same feature as the cheat sheet.
    @test TerminalPager._action_event(:extended_help, [:help]) == :extended_help
    @test isnothing(TerminalPager._action_event(:extended_help, Symbol[]))
end

@testset "Help Text Marks" begin
    atoms = TerminalPager._help_atoms(
        "Press <kbd>:quit</kbd>, `a b` or **very strong** <kbd>Enter</kbd>."
    )
    @test [atom.text for atom in atoms] ==
        ["Press", "q", ",", "a b", "or", "very", "strong", "Enter", "."]
    @test [atom.style for atom in atoms] ==
        [:plain, :key, :plain, :code, :plain, :strong, :strong, :key, :plain]
    @test [atom.glued for atom in atoms] ==
        [false, false, true, false, false, false, false, false, true]

    # Nothing is marked inside code, and an unbalanced mark is written as it is.
    atoms = TerminalPager._help_atoms("`<kbd>:quit</kbd> **x**` and `open <kbd>x")
    @test [(atom.text, atom.style) for atom in atoms] == [
        ("<kbd>:quit</kbd> **x**", :code),
        ("and", :plain),
        ("`open", :plain),
        ("<kbd>x", :plain),
    ]

    # A single asterisk is not a mark, a backslash writes the punctuation character after
    # it as it is, and the name of a key can have blanks and wide characters.
    atoms = TerminalPager._help_atoms(
        "a * b \\*\\*c\\*\\* \\<kbd> <kbd>↑</kbd><kbd>a b</kbd> c:\\d **`e`**"
    )
    @test [(atom.text, atom.style) for atom in atoms] == [
        ("a", :plain),
        ("*", :plain),
        ("b", :plain),
        ("**c**", :plain),
        ("<kbd>", :plain),
        ("↑", :key),
        ("a b", :key),
        ("c:\\d", :plain),
        ("e", :code),
    ]

    # An action without a key is named as such.
    @test TerminalPager._help_key_name(":not_an_action") == "unbound"
    @test TerminalPager._help_key_name("Enter") == "Enter"
    @test TerminalPager._manual_key_names("<kbd>:not_an_action</kbd>") == "—"
    @test TerminalPager._manual_key_names("<kbd>Alt-l</kbd>") == "Alt-l"

    # The keys are preferred to the mouse events, and the tables show the shortest ones.
    @test TerminalPager._help_key_name(":fastleft") == "Shift-←"
    @test TerminalPager._manual_key_names("<kbd>:up</kbd>") == "k, ↑"
    @test TerminalPager._manual_key_names("<kbd>:wheel_up</kbd>") == "Wheel↑"

    # A cell of a key table can have several keys, and one without them is kept.
    @test TerminalPager._manual_key_names("<kbd>Home</kbd>, <kbd>Ctrl-A</kbd>") ==
        "Home, Ctrl-A"
    @test TerminalPager._manual_key_names("<kbd>←</kbd> or <kbd>:quit</kbd>") == "←, q"
    @test TerminalPager._manual_key_names("plain") == "plain"
    @test TerminalPager._manual_key_names("<kbd>open") == "<kbd>open"

    # A key cap has one column at each side of the key: brackets without colors, and
    # blanks with the face of the key caps if the face fills its cells.
    plain = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())
    filled = _keycap_style(TerminalPager.Face(; background = :bright_black))
    atoms = TerminalPager._help_atoms("Press <kbd>:quit</kbd>, `a b`.")
    @test TerminalPager._help_atoms_width(atoms) == 15
    @test filled.keycap_filled
    @test !plain.keycap_filled

    buf = IOBuffer()
    @test TerminalPager._write_help_atoms!(buf, atoms, plain) == 15
    @test String(take!(buf)) == "Press [q], a b."

    @test TerminalPager._write_help_atoms!(buf, atoms, filled) == 15
    text = String(take!(buf))
    @test occursin(filled.keycap * " q " * filled.reset, text)
    @test occursin(filled.code * "a b" * filled.reset, text)
    @test TerminalPager.remove_decorations(text) == "Press  q , a b."

    # A reversed face fills its cells too.
    @test _keycap_style(TerminalPager.Face(; inverse = true)).keycap_filled

    # A face that does not fill its cells writes the key between brackets drawn as the
    # borders.
    bracketed = _keycap_style(TerminalPager.Face(; foreground = :yellow))
    @test !bracketed.keycap_filled
    @test TerminalPager._write_help_atoms!(buf, atoms, bracketed) == 15
    text = String(take!(buf))
    border = bracketed.border
    reset = bracketed.reset
    @test occursin(
        border * "[" * reset * bracketed.keycap * "q" * reset * border * "]" * reset, text
    )
    @test TerminalPager.remove_decorations(text) == "Press [q], a b."
end

@testset "Help Text Wrapping" begin
    atoms = TerminalPager._help_atoms("one two (`three four`), five <kbd>Esc</kbd>. six")
    plain = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())

    function rows(width)
        return map(TerminalPager._wrap_help_atoms(atoms, width)) do row
            buf = IOBuffer()
            TerminalPager._write_help_atoms!(buf, row, plain)
            return String(take!(buf))
        end
    end

    @test rows(80) == ["one two (three four), five [Esc]. six"]

    # The pieces glued to each other are never separated.
    @test rows(20) == ["one two", "(three four), five", "[Esc]. six"]
    @test rows(12) == ["one two", "(three four),", "five [Esc].", "six"]

    # A word wider than the width gets a row of its own.
    @test rows(3) == ["one", "two", "(three four),", "five", "[Esc].", "six"]
    @test isempty(TerminalPager._wrap_help_atoms(TerminalPager.HelpAtom[], 10))

    # A text is wrapped after the margin and the indentation.
    lines = String[]
    TerminalPager._help_text!(lines, "aaa bbb ccc ddd", plain, "> ", "  ", 9)
    @test lines == ["  > aaa bbb", "    ccc ddd"]
end

@testset "Extended Help Source" begin
    source = """
    <!-- A comment
    with

    a blank line. -->

    intro one
    intro two

    <!-- A comment in one line. -->
    # First

    | Key | Action |
    |:--|:--|
    | <kbd>a</kbd> | b |

    > [!TIP]
    > text

    ```julia title="Title"
    code

    more  # comment
    ```

    ~~~text
    art

    ~~~
    """

    # The blocks are separated by blank lines, but for the examples, the figures, and the
    # comments, which are not returned.
    @test TerminalPager._manual_blocks(source) == [
        ["intro one", "intro two"],
        ["# First"],
        ["| Key | Action |", "|:--|:--|", "| <kbd>a</kbd> | b |"],
        ["> [!TIP]", "> text"],
        ["```julia title=\"Title\"", "code", "", "more  # comment", "```"],
        ["~~~text", "art", "", "~~~"],
    ]
    @test isempty(TerminalPager._manual_blocks("\n\n"))
    @test TerminalPager._manual_blocks("text\n\n<!-- open\n\nhidden") == [["text"]]

    # The cells of a row are separated by bars, and an escaped bar belongs to the cell.
    @test TerminalPager._manual_cells("| a | b c |") == ["a", "b c"]
    @test TerminalPager._manual_cells("a|b") == ["a", "b"]
    @test TerminalPager._manual_cells("|  | b |") == ["", "b"]
    @test TerminalPager._manual_cells("| `a \\| b` | c\\d \\\\ |") ==
        ["`a | b`", "c\\d \\\\"]
    @test isempty(TerminalPager._manual_cells("|"))

    # The header and the delimiter of a table are skipped, and a term loses its backticks.
    block = [
        "| Term | Meaning |",
        "|:--|:--|",
        "| `a b` | c  d |",
        "| e |",
        "| <kbd>x</kbd> | `y` |",
    ]
    @test TerminalPager._manual_table(block) ==
        [("a b", "c  d"), ("e", ""), ("<kbd>x</kbd>", "`y`")]
    @test isempty(TerminalPager._manual_table(["| a | b |", "|--|--|"]))

    # An item of a list continues on the lines that begin with a blank.
    @test TerminalPager._manual_rows(["- a  b", "  c  d", "- e"], 2) == ["a  b c  d", "e"]

    # A comment follows two blanks, and the title of an example follows its language.
    @test TerminalPager._manual_split("code  # note", "  # ") == ("code", "note")
    @test TerminalPager._manual_split("code   ", "  # ") == ("code", "")
    @test TerminalPager._manual_example_title("```julia title=\"A b\"") == "A b"
    @test TerminalPager._manual_example_title("```julia") == ""
    @test TerminalPager._manual_example_title("```julia title=\"open") == ""
end

@testset "Extended Help File" begin
    # The manual is the Markdown file of the package, embedded when it is precompiled.
    file = joinpath(pkgdir(TerminalPager), "src", "extended_help.md")
    @test TerminalPager._MANUAL_SOURCE == replace(read(file, String), "\r\n" => "\n")
    @test startswith(TerminalPager._MANUAL_SOURCE, "<!--")

    # Every block is written as GitHub and the renderer understand it.
    blocks = TerminalPager._manual_blocks(TerminalPager._manual_source())
    kinds = Set{Char}()

    for block in blocks
        head = first(block)
        push!(kinds, first(head))

        if startswith(head, '|')
            # A table has a header, a delimiter, and rows with two cells.
            @test length(block) > 2
            @test occursin(r"^\|(:?-+:?\|){2}$", block[2])
            @test all(row -> length(TerminalPager._manual_cells(row)) == 2, block)
        elseif startswith(head, '>')
            @test occursin(r"^> \[!(TIP|NOTE|IMPORTANT|WARNING|CAUTION)\]$", head)
            @test all(line -> startswith(line, "> "), block)
        elseif startswith(head, "```")
            @test occursin(r"^```\w+ title=\"[^\"]+\"$", head)
            @test last(block) == "```"
        elseif startswith(head, "~~~")
            @test occursin(r"^~~~\w+$", head)
            @test last(block) == "~~~"
        elseif startswith(head, '#')
            @test occursin(r"^##? \S", head)
            @test length(block) == 1
        end
    end

    # The manual has every kind of block.
    @test issubset(['|', '>', '`', '~', '#', '-', '1'], kinds)
end

@testset "Extended Help Blocks" begin
    width = TerminalPager._HELP_WIDTH
    table(rows...) = "| A | B |\n|:--|:--|\n" * join(rows, '\n')

    # A paragraph is wrapped after the margin, with its lines joined.
    lines = _manual_block_lines("aaa bbb\nccc " * "x"^85 * " ddd")
    @test lines == ["  aaa bbb ccc", "  " * "x"^85, "  ddd"]

    @test _manual_block_lines("## Title") == ["  ▌ Title"]

    # A key table has two columns when every description fits in half the width.
    lines = _manual_block_lines(
        table(
            "| <kbd>Enter</kbd> | Apply. |",
            "| <kbd>:quit</kbd> | Quit. |",
            "| <kbd>Esc</kbd> | Cancel it. |",
        ),
    )
    @test lines ==
        ["    Enter  Apply." * " "^31 * "q      Quit.", "    Esc    Cancel it."]
    @test _manual_block_lines(table("| <kbd>Enter</kbd> | Apply. |")) ==
        ["    Enter  Apply."]

    # Otherwise, the descriptions are wrapped at the side of the keys.
    long = join(fill("word", 20), ' ')
    lines = _manual_block_lines(
        table("| <kbd>Esc</kbd> | " * long * " |", "| <kbd>x</kbd> | short |")
    )
    @test lines == [
        "    Esc  " * join(fill("word", 16), ' '),
        "         " * join(fill("word", 4), ' '),
        "    x    short",
    ]

    # A table without keys is a list of terms, whose descriptions are at the side of short
    # terms and below long ones.
    @test _manual_block_lines(table("| `ab` | aaa bbb |", "| `c` | ddd |")) ==
        ["    ab  aaa bbb", "    c   ddd"]

    term = "x"^30
    @test _manual_block_lines(table("| `" * term * "` | aaa bbb |", "| `c` | ddd |")) ==
        ["    " * term, "        aaa bbb", "", "    c", "        ddd"]

    # A bar is written in a cell with a backslash.
    @test _manual_block_lines(table("| `a \\| b` | c `\\|> d` |")) == ["    a | b  c |> d"]

    # The lists hang their items after the bullet or the number, and an item can have two
    # blanks in it.
    @test _manual_block_lines("- aaa  bbb\n  ccc\n- ddd") ==
        ["    • aaa bbb ccc", "    • ddd"]
    @test _manual_block_lines("- " * "x"^50 * " " * "y"^50) ==
        ["    • " * "x"^50, "      " * "y"^50]
    @test _manual_block_lines("1. aaa\n2. bbb") == ["    1. aaa", "    2. bbb"]

    # A remark is a box with the width of the content, named by its alert.
    lines = _manual_block_lines("> [!TIP]\n> aaa bbb\n> ccc")
    @test lines == [
        "  ╭─ Tip " * "─"^(width - 12) * "╮",
        "  │ aaa bbb ccc" * " "^(width - 18) * "│",
        "  ╰" * "─"^(width - 6) * "╯",
    ]
    @test all(line -> textwidth(line) == width - 2, lines)
    @test startswith(_manual_block_lines("> [!NOTE]\n> a")[1], "  ╭─ Note ─")
    @test startswith(
        _manual_block_lines("> [!IMPORTANT]\n> a")[1], "  ╭─ Important ─"
    )
    @test startswith(_manual_block_lines("> [!WARNING]\n> a")[1], "  ╭─ Warning ─")
    @test startswith(_manual_block_lines("> [!CAUTION]\n> a")[1], "  ╭─ Caution ─")

    # A quote without an alert is a box without a name.
    @test _manual_block_lines("> aaa\n>\n> bbb") == [
        "  ╭" * "─"^(width - 6) * "╮",
        "  │ aaa bbb" * " "^(width - 14) * "│",
        "  ╰" * "─"^(width - 6) * "╯",
    ]

    # The box is drawn as the borders, and only its label has the color of its kind.
    style = TerminalPager.HelpStyle(true, TerminalPager.DisplayConfig())
    lines = String[]
    TerminalPager._manual_block!(lines, ["> [!WARNING]", "> a"], style)
    border = style.border
    reset = style.reset
    @test startswith(
        lines[1], "  " * border * "╭─ " * reset * style.warning * "Warning" * reset * border
    )
    @test lines[2] ==
        "  " * border * "│" * reset * " a" * " "^(width - 8) * border * "│" * reset
    @test !occursin(style.warning, lines[2] * lines[3])

    for (alert, color) in (
        ("TIP", style.tip),
        ("NOTE", style.note),
        ("IMPORTANT", style.note),
        ("CAUTION", style.warning),
    )
        lines = String[]
        TerminalPager._manual_block!(lines, ["> [!$alert]", "> a"], style)
        @test occursin(color * uppercasefirst(lowercase(alert)) * reset, lines[1])
    end

    # The comments of an example are aligned at the side of the code, and its title is
    # optional.
    lines = _manual_block_lines(
        "```julia title=\"Calls\"\nf(x)          # call\n\nlong_name(x)\n```"
    )
    @test lines ==
        ["  ┌ Calls", "  │ f(x)           call", "  │", "  │ long_name(x)", "  └"]
    @test _manual_block_lines("```julia\nf(x)\n```") == ["  ┌", "  │ f(x)", "  └"]

    # A figure is written as it is, with its labels.
    @test _manual_block_lines("~~~text\nab    # label\n c\n~~~") ==
        ["    ab    label", "     c"]
end

@testset "Extended Help Document" begin
    lines = _manual_plain("intro\n\n# One\n\ntext\n\n# Two\n\n## Section\n")
    style = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())
    width = TerminalPager._HELP_WIDTH

    # The manual begins with the banner and the introduction, which are followed by the
    # table of contents and by the chapters, each one with its title on a rule.
    @test lines[1] == "  ╭" * "─"^(width - 6) * "╮"
    @test startswith(lines[2], "  │  TerminalPager.jl $(TerminalPager._pkg_version())  ·  ")
    @test occursin("Extended Help", lines[2])
    @test lines[3:end] == [
        "  ╰" * "─"^(width - 6) * "╯",
        "",
        "  intro",
        "",
        "  CONTENTS",
        "",
        "   [a] One" * " "^37 * "[b] Two",
        "",
        "",
        "  ━━ a · One " * "━"^(width - 15),
        "",
        "  text",
        "",
        "",
        "  ━━ b · Two " * "━"^(width - 15),
        "",
        "  ▌ Section",
    ]

    _, bookmarks = TerminalPager._manual_lines("intro\n\n# One\n\ntext\n\n# Two\n", style)
    @test bookmarks == Dict('a' => (12, 1), 'b' => (17, 1))

    # The whole manual fits in its width, and it has no decorations without colors.
    config = TerminalPager.DisplayConfig()
    manual = TerminalPager._manual(false, config)
    lines = String.(split(manual.text, '\n'))
    @test all(line -> textwidth(line) <= width, lines)
    @test !occursin('\e', manual.text)
    @test length(manual.layout) == length(lines)

    # Each chapter is in the table of contents and has a bookmark on its title.
    titles = [
        String(SubString(first(block), 3)) for
        block in TerminalPager._manual_blocks(TerminalPager._manual_source()) if
        startswith(first(block), "# ")
    ]
    @test 10 < length(titles) <= 26
    @test titles[end] == "Action Reference"
    @test sort!(collect(keys(manual.bookmarks))) ==
        TerminalPager._manual_letter.(eachindex(titles))

    for (i, title) in enumerate(titles)
        letter = TerminalPager._manual_letter(i)
        line, column = manual.bookmarks[letter]
        @test column == 1
        @test startswith(lines[line], "  ━━ $letter · $title ━")
        @test any(l -> occursin("[$letter] $title", l), lines)
    end

    # The boxes are closed at the same column on every row.
    for line in lines
        startswith(line, "  │ ") && endswith(line, "│") &&
            @test textwidth(line) == width - 2
    end

    # The decorated manual has the same text, but for the key caps.
    colored = TerminalPager._manual(true, config)
    colored_lines = split(TerminalPager.remove_decorations(colored.text), '\n')
    @test occursin('\e', colored.text)
    @test textwidth.(colored_lines) == textwidth.(lines)
    @test replace.(colored_lines, r"[\[\]]" => " ") == replace.(lines, r"[\[\]]" => " ")
end

@testset "Extended Help Content" begin
    actions = TerminalPager._ACTIONS
    source = TerminalPager._manual_source()

    # Every action named in the manual exists, so that a renamed action cannot leave a key
    # shown as unbound. The empty action is the example of an unbound one.
    for m in eachmatch(r"<kbd>:(\w+)</kbd>", source)
        @test Symbol(m[1]) in actions
    end

    # The marks of the previous language of the manual are not used.
    @test !occursin(r"\{:?[\w-]*\}(?![^`\n]*`)", source)
    @test !occursin(r"^(\+ |: |!\w)"m, source)

    # The last chapter lists every action of the cheat sheet with its name.
    reference = source[last(findfirst("# Action Reference", source)):end]

    for section in TerminalPager._HELP_SECTIONS, entry in section.actions
        @test occursin("| <kbd>:$(entry.action)</kbd> | ", reference)
        @test occursin("`:$(entry.action)`", reference)
    end

    # Every preference and every face is described.
    text = TerminalPager._manual(false, TerminalPager.DisplayConfig()).text

    for preference in keys(TerminalPager._AVAILABLE_PREFERENCES)
        preference == "always_use_alternate_screen_buffer_in_repl_mode" && continue
        @test occursin("\"$preference\"", text)
    end

    for (name, _) in TerminalPager._FACES
        @test occursin(string(name), text)
    end
end

@testset "Extended Help Follows the Key Bindings" begin
    config = TerminalPager.DisplayConfig()
    manual = TerminalPager._manual(false, config)

    # The manual is rendered once for the same key bindings, faces, and colors.
    @test TerminalPager._manual(false, config) === manual
    @test TerminalPager._manual(true, config) !== manual

    try
        TerminalPager.set_keybinding("X", :search)
        TerminalPager.delete_keybinding("/")
        rebound = TerminalPager._manual(false, config)
        @test rebound !== manual
        @test occursin(r"search with\s+\[X\]", rebound.text)
        @test TerminalPager._help_key_name(":search") == "X"
    finally
        TerminalPager.reset_keybindings()
    end

    @test TerminalPager._help_key_name(":search") == "/"
end

@testset "Extended Help Session" begin
    # The manual opens in a nested pager whose bookmarks are its chapters, and the parent
    # is repainted when it is closed.
    input = TypedInput(["'", "e", "q"])
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    pagerd = TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => false),
        display_size = (24, 80),
        features = [:help],
        input = TerminalPager.PagerInput(input),
        num_lines = 2,
        term = term,
        text_layout = TerminalPager.ViewLayout(["x", "y"]),
    )
    parent_layout = pagerd.text_layout
    pagerd.frame_cache.valid = true
    pagerd.event = :extended_help
    @test TerminalPager._pager_event_process!(pagerd)

    text = replace(String(take!(output)), r"\e\[[0-9;?]*[A-Za-z]" => "")
    @test occursin("Extended Help", text)
    @test occursin("━━ e · Searching ━", text)
    @test !occursin("━━ f · ", text)
    @test pagerd.text_layout === parent_layout
    @test !pagerd.frame_cache.valid
    @test pagerd.redraw
end

@testset "Extended Help Session Features" begin
    # Only the rows can be frozen in the manual, and its lines cannot be filtered.
    text = join(("line $i" for i in 1:20), '\n')

    output = _session_output(text, "H&1\rf2\rFjj\rqq")
    @test !occursin(r"FILTER 1 \d+/\d+", output)
    @test occursin("Frozen rows [0] › ", output)
    @test !occursin("Frozen columns", output)
    @test occursin("Frozen 2 rows × 0 columns", output)
    @test occursin("Frozen 4 rows × 0 columns", output)
    @test occursin("FREEZE", output)
    @test !occursin(TerminalPager._FREEZE_GUIDE_VERTICAL, output)

    # The session that opens the manual is not restricted by it.
    output = _session_output(text, "Hq&1\rf\r\rq")
    @test occursin(r"FILTER 1 11/20", output)
    @test occursin("Frozen columns [0] › ", output)

    # The filter history is shared by the sessions.
    empty!(TerminalPager._FILTER_HISTORY)
end
