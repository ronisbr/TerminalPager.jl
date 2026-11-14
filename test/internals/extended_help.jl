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
    atoms = TerminalPager._help_atoms("Press {:quit}, `a b` or *very strong* {Enter}.")
    @test [atom.text for atom in atoms] ==
        ["Press", "q", ",", "a b", "or", "very", "strong", "Enter", "."]
    @test [atom.style for atom in atoms] ==
        [:plain, :key, :plain, :code, :plain, :strong, :strong, :key, :plain]
    @test [atom.glued for atom in atoms] ==
        [false, false, true, false, false, false, false, false, true]

    # Nothing is marked inside code, and an unbalanced mark is written as it is.
    atoms = TerminalPager._help_atoms("`{:quit} *x*` and `open {x")
    @test [(atom.text, atom.style) for atom in atoms] ==
        [("{:quit} *x*", :code), ("and", :plain), ("`open", :plain), ("{x", :plain)]

    # An action without a key is named as such.
    @test TerminalPager._help_key_name(":not_an_action") == "unbound"
    @test TerminalPager._help_key_name("Enter") == "Enter"
    @test TerminalPager._manual_key_names(":not_an_action") == "—"
    @test TerminalPager._manual_key_names("Alt-l") == "Alt-l"

    # The keys are preferred to the mouse events, and the tables show the shortest ones.
    @test TerminalPager._help_key_name(":fastleft") == "Shift-←"
    @test TerminalPager._manual_key_names(":up") == "k, ↑"
    @test TerminalPager._manual_key_names(":wheel_up") == "Wheel↑"

    # A key cap has one column at each side of the key: brackets without colors, and
    # blanks with the face of the key caps if the face fills its cells.
    plain = TerminalPager.HelpStyle(false, TerminalPager.DisplayConfig())
    filled = _keycap_style(TerminalPager.Face(; background = :bright_black))
    atoms = TerminalPager._help_atoms("Press {:quit}, `a b`.")
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
    atoms = TerminalPager._help_atoms("one two (`three four`), five {Esc}. six")
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
    intro one
    intro two

    # First

    + a  b
      c
    + d  e

    ```Title
    code

    more  ## comment
    ```

    ~~~
    art

    ~~~
    """

    # The blocks are separated by blank lines, but for the examples and the figures.
    @test TerminalPager._manual_blocks(source) == [
        ["intro one", "intro two"],
        ["# First"],
        ["+ a  b", "  c", "+ d  e"],
        ["```Title", "code", "", "more  ## comment", "```"],
        ["~~~", "art", "", "~~~"],
    ]
    @test isempty(TerminalPager._manual_blocks("\n\n"))

    # A row continues on the lines that begin with a blank, and it is split at its first
    # two blanks.
    block = ["+ a  b", "  c  d", "+ e"]
    @test TerminalPager._manual_rows(block, 2) == ["a  b c  d", "e"]
    @test TerminalPager._manual_pairs(block) == [("a", "b c  d"), ("e", "")]
    @test TerminalPager._manual_split("code  ## note", "  ## ") == ("code", "note")
    @test TerminalPager._manual_split("code   ", "  ## ") == ("code", "")
end

@testset "Extended Help Blocks" begin
    width = TerminalPager._HELP_WIDTH

    # A paragraph is wrapped after the margin, with its lines joined.
    lines = _manual_block_lines("aaa bbb\nccc " * "x"^85 * " ddd")
    @test lines == ["  aaa bbb ccc", "  " * "x"^85, "  ddd"]

    @test _manual_block_lines("## Title") == ["  ▌ Title"]

    # A key table has two columns when every description fits in half the width.
    @test _manual_block_lines("+ Enter  Apply.\n+ :quit  Quit.\n+ Esc  Cancel it.") ==
        ["    Enter  Apply." * " "^31 * "q      Quit.", "    Esc    Cancel it."]
    @test _manual_block_lines("+ Enter  Apply.") == ["    Enter  Apply."]

    # Otherwise, the descriptions are wrapped at the side of the keys.
    long = join(fill("word", 20), ' ')
    lines = _manual_block_lines("+ Esc  " * long * "\n+ x  short")
    @test lines == [
        "    Esc  " * join(fill("word", 16), ' '),
        "         " * join(fill("word", 4), ' '),
        "    x    short",
    ]

    # The descriptions are at the side of short terms and below long ones.
    @test _manual_block_lines(": ab  aaa bbb\n: c  ddd") ==
        ["    ab  aaa bbb", "    c   ddd"]

    term = "x"^30
    @test _manual_block_lines(": " * term * "  aaa bbb\n: c  ddd") ==
        ["    " * term, "        aaa bbb", "", "    c", "        ddd"]

    # The lists hang their items after the bullet or the number, and an item can have two
    # blanks in it.
    @test _manual_block_lines("- aaa  bbb\n  ccc\n- ddd") ==
        ["    • aaa bbb ccc", "    • ddd"]
    @test _manual_block_lines("- " * "x"^50 * " " * "y"^50) ==
        ["    • " * "x"^50, "      " * "y"^50]
    @test _manual_block_lines("1. aaa\n2. bbb") == ["    1. aaa", "    2. bbb"]

    # A remark is a box with the width of the content.
    lines = _manual_block_lines("!tip aaa bbb\n  ccc")
    @test lines == [
        "  ╭─ Tip " * "─"^(width - 12) * "╮",
        "  │ aaa bbb ccc" * " "^(width - 18) * "│",
        "  ╰" * "─"^(width - 6) * "╯",
    ]
    @test all(line -> textwidth(line) == width - 2, lines)
    @test startswith(_manual_block_lines("!note a")[1], "  ╭─ Note ─")
    @test startswith(_manual_block_lines("!warning a")[1], "  ╭─ Warning ─")

    # The box is drawn as the borders, and only its label has the color of its kind.
    style = TerminalPager.HelpStyle(true, TerminalPager.DisplayConfig())
    lines = String[]
    TerminalPager._manual_block!(lines, ["!warning a"], style)
    border = style.border
    reset = style.reset
    @test startswith(
        lines[1], "  " * border * "╭─ " * reset * style.warning * "Warning" * reset * border
    )
    @test lines[2] ==
        "  " * border * "│" * reset * " a" * " "^(width - 8) * border * "│" * reset
    @test !occursin(style.warning, lines[2] * lines[3])

    # The comments of an example are aligned at the side of the code.
    @test _manual_block_lines("```Calls\nf(x)          ## call\n\nlong_name(x)\n```") ==
        ["  ┌ Calls", "  │ f(x)           call", "  │", "  │ long_name(x)", "  └"]

    # A figure is written as it is, with its labels.
    @test _manual_block_lines("~~~\nab    ## label\n c\n~~~") ==
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
    @test occursin("Extended help", lines[2])
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
    @test titles[end] == "Action reference"
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
    for m in eachmatch(r"\{:(\w+)\}", source)
        @test Symbol(m[1]) in actions
    end

    for m in eachmatch(r"^\+ :(\w+)  "m, source)
        @test Symbol(m[1]) in actions
    end

    # The last chapter lists every action of the cheat sheet with its name.
    reference = source[last(findfirst("# Action reference", source)):end]

    for section in TerminalPager._HELP_SECTIONS, entry in section.actions
        @test occursin("+ :$(entry.action)  ", reference)
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
    @test occursin("Extended help", text)
    @test occursin("━━ e · Searching ━", text)
    @test !occursin("━━ f · ", text)
    @test pagerd.text_layout === parent_layout
    @test !pagerd.frame_cache.valid
    @test pagerd.redraw
end
