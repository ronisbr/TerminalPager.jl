## Description #############################################################################
#
# Tests for the extended help, which is the manual shown inside the pager.
#
############################################################################################

"""
    _manual_plain(width::Int) -> Vector{String}

Return the lines of the extended help laid out for `width` columns without decorations.
"""
function _manual_plain(width::Int)
    manual = TerminalPager._manual(false, TerminalPager.DisplayConfig(), width)
    return String.(split(manual.text, '\n'))
end

"""
    _manual_block_lines(block::TerminalPager.ManualBlock, width::Int) -> Vector{String}

Return the lines of `block` laid out for a content `width` columns wide without decorations.
"""
function _manual_block_lines(block::TerminalPager.ManualBlock, width::Int)
    lines = String[]
    style = TerminalPager.ManualStyle(false, TerminalPager.DisplayConfig())
    TerminalPager._manual_block!(lines, block, style, width)
    return lines
end

@testset "Extended Help Key Binding and Feature Gate" begin
    key = ("H", false, false, false)
    @test TerminalPager._DEFAULT_KEYBINDINGS[key] == :extended_help
    @test :extended_help in TerminalPager._ACTIONS

    # The manual needs the same feature as the cheat sheet.
    @test TerminalPager._action_event(:extended_help, [:help]) == :extended_help
    @test isnothing(TerminalPager._action_event(:extended_help, Symbol[]))
end

@testset "Extended Help Text Marks" begin
    atoms = TerminalPager._manual_atoms("Press {:quit}, `a b` or *very strong* {Enter}.")
    @test [atom.text for atom in atoms] ==
        ["Press", "q", ",", "a b", "or", "very", "strong", "Enter", "."]
    @test [atom.style for atom in atoms] ==
        [:plain, :key, :plain, :code, :plain, :strong, :strong, :key, :plain]
    @test [atom.glued for atom in atoms] ==
        [false, false, true, false, false, false, false, false, true]

    # Nothing is marked inside code, and an unbalanced mark is written as it is.
    atoms = TerminalPager._manual_atoms("`{:quit} *x*` and `open")
    @test [(atom.text, atom.style) for atom in atoms] ==
        [("{:quit} *x*", :code), ("and", :plain), ("`open", :plain)]

    # An action without a key is named as such.
    @test TerminalPager._manual_key_name(":not_an_action") == "unbound"
    @test TerminalPager._manual_key_name("Enter") == "Enter"
    @test TerminalPager._manual_key_names(":not_an_action") == "—"
    @test TerminalPager._manual_key_names("Alt-l") == "Alt-l"

    # The keys are preferred to the mouse events, and the tables show the shortest ones.
    @test TerminalPager._manual_key_name(":fastleft") == "Shift-←"
    @test TerminalPager._manual_key_names(":up") == "k, ↑"
    @test TerminalPager._manual_key_names(":wheel_up") == "Wheel↑"

    # A key cap has a blank at each side, and brackets without colors.
    plain = TerminalPager.ManualStyle(false, TerminalPager.DisplayConfig())
    colored = TerminalPager.ManualStyle(true, TerminalPager.DisplayConfig())
    atoms = TerminalPager._manual_atoms("Press {:quit}, `a b`.")

    buf = IOBuffer()
    @test TerminalPager._write_manual_atoms!(buf, atoms, plain) == 15
    @test String(take!(buf)) == "Press [q], a b."

    @test TerminalPager._write_manual_atoms!(buf, atoms, colored) == 15
    text = String(take!(buf))
    @test occursin(colored.keycap * " q " * colored.reset, text)
    @test occursin(colored.code * "a b" * colored.reset, text)
    @test TerminalPager.remove_decorations(text) == "Press  q , a b."
    @test TerminalPager._manual_atoms_width(atoms) == 15

    # A face that does not fill its cells writes the key between brackets drawn as the
    # borders, with the same width.
    bracketed = TerminalPager.ManualStyle(
        true,
        TerminalPager._display_config() do name
            if name === :help_keycap
                TerminalPager.Face(; weight = :bold, foreground = :yellow)
            else
                TerminalPager._default_face(name)
            end
        end,
    )
    @test colored.keycap_filled
    @test !bracketed.keycap_filled
    @test !plain.keycap_filled

    @test TerminalPager._write_manual_atoms!(buf, atoms, bracketed) == 15
    text = String(take!(buf))
    border = bracketed.border
    reset = bracketed.reset
    @test occursin(
        border * "[" * reset * bracketed.keycap * "q" * reset * border * "]" * reset, text
    )
    @test TerminalPager.remove_decorations(text) == "Press [q], a b."

    # A reversed face fills its cells too.
    reversed = TerminalPager.ManualStyle(
        true,
        TerminalPager._display_config() do name
            if name === :help_keycap
                TerminalPager.Face(; inverse = true)
            else
                TerminalPager._default_face(name)
            end
        end,
    )
    @test reversed.keycap_filled
end

@testset "Extended Help Text Wrapping" begin
    atoms = TerminalPager._manual_atoms("one two (`three four`), five {Esc}. six")
    plain = TerminalPager.ManualStyle(false, TerminalPager.DisplayConfig())

    function rows(width)
        return map(TerminalPager._wrap_manual_atoms(atoms, width)) do row
            buf = IOBuffer()
            TerminalPager._write_manual_atoms!(buf, row, plain)
            return String(take!(buf))
        end
    end

    @test rows(80) == ["one two (three four), five [Esc]. six"]

    # The pieces glued to each other are never separated.
    @test rows(20) == ["one two", "(three four), five", "[Esc]. six"]
    @test rows(12) == ["one two", "(three four),", "five [Esc].", "six"]

    # A word wider than the width gets a row of its own.
    @test rows(3) == ["one", "two", "(three four),", "five", "[Esc].", "six"]
    @test isempty(TerminalPager._wrap_manual_atoms(TerminalPager.ManualAtom[], 10))
end

@testset "Extended Help Blocks" begin
    # A paragraph is wrapped after the margin.
    block = TerminalPager._manual_paragraph("aaa bbb ccc ddd")
    @test _manual_block_lines(block, 7) == ["  aaa bbb", "  ccc ddd"]

    @test _manual_block_lines(TerminalPager._manual_heading("Title"), 20) == ["  ▌ Title"]

    # A key table has two columns when every description fits in half the width.
    items = ["Enter" => "Apply.", ":quit" => "Quit.", "Esc" => "Cancel it."]
    block = TerminalPager._manual_keys(items)
    @test _manual_block_lines(block, 60) ==
        ["    Enter  Apply.                 q      Quit.", "    Esc    Cancel it."]
    @test _manual_block_lines(block, 30) ==
        ["    Enter  Apply.", "    q      Quit.", "    Esc    Cancel it."]

    # Otherwise, the descriptions are wrapped at the side of the keys.
    block = TerminalPager._manual_keys(["Esc" => "aaa bbb ccc ddd", "x" => "eee"])
    @test _manual_block_lines(block, 16) ==
        ["    Esc  aaa bbb", "         ccc ddd", "    x    eee"]

    # The descriptions are at the side of short terms and below long ones.
    block = TerminalPager._manual_definitions(["ab" => "aaa bbb ccc", "c" => "ddd"])
    @test _manual_block_lines(block, 14) ==
        ["    ab  aaa bbb", "        ccc", "    c   ddd"]

    long = "x"^30
    block = TerminalPager._manual_definitions([long => "aaa bbb", "c" => "ddd"])
    @test _manual_block_lines(block, 40) ==
        ["    " * long, "        aaa bbb", "", "    c", "        ddd"]

    # The lists hang their items after the bullet or the number.
    block = TerminalPager._manual_list(["aaa bbb ccc", "ddd"])
    @test _manual_block_lines(block, 11) == ["    • aaa bbb", "      ccc", "    • ddd"]
    block = TerminalPager._manual_list(["aaa bbb ccc", "ddd"]; numbered = true)
    @test _manual_block_lines(block, 12) == ["    1. aaa bbb", "       ccc", "    2. ddd"]

    # A remark is a box with the width of the content.
    block = TerminalPager._manual_remark(:tip, "aaa bbb ccc ddd eee")
    @test _manual_block_lines(block, 16) == [
        "  ╭─ Tip ────────╮",
        "  │ aaa bbb ccc  │",
        "  │ ddd eee      │",
        "  ╰──────────────╯",
    ]
    @test startswith(
        _manual_block_lines(TerminalPager._manual_remark(:note, "a"), 16)[1], "  ╭─ Note ─"
    )
    @test startswith(
        _manual_block_lines(TerminalPager._manual_remark(:warning, "a"), 16)[1],
        "  ╭─ Warning ─",
    )

    # The comments of an example are at the side of the code, or above it if they do not
    # fit.
    items = ["f(x)" => "call", "" => "", "long_name(x)" => ""]
    block = TerminalPager._manual_example("Calls", items)
    @test _manual_block_lines(block, 40) ==
        ["  ┌ Calls", "  │ f(x)           call", "  │", "  │ long_name(x)", "  └"]
    @test _manual_block_lines(block, 12) ==
        ["  ┌ Calls", "  │ # call", "  │ f(x)", "  │", "  │ long_name(x)", "  └"]
    @test _manual_block_lines(TerminalPager._manual_example("", ["x" => ""]), 12)[1] ==
        "  ┌ Example"

    # A figure is written as it is, with its labels.
    block = TerminalPager._manual_figure(["ab  " => "label", "c   " => ""])
    @test _manual_block_lines(block, 40) == ["    ab    label", "    c"]

    # The box of a remark is drawn as the borders, and only its label has the color of
    # its kind.
    style = TerminalPager.ManualStyle(true, TerminalPager.DisplayConfig())
    lines = String[]
    remark = TerminalPager._manual_remark(:warning, "a")
    TerminalPager._manual_block!(lines, remark, style, 16)
    border = style.border
    reset = style.reset
    @test lines[1] ==
        "  " * border * "╭─ " * reset * style.warning * "Warning" * reset * border *
          " ────╮" * reset
    @test lines[2] == "  " * border * "│" * reset * " a" * " "^12 * border * "│" * reset
    @test lines[3] == "  " * border * "╰" * "─"^14 * "╯" * reset
    @test !occursin(style.warning, lines[2] * lines[3])

    unknown = TerminalPager.ManualBlock(:unknown, "", "", Pair{String, String}[])
    @test_throws ArgumentError _manual_block_lines(unknown, 40)
end

@testset "Extended Help Document" begin
    chapters = TerminalPager._manual_chapters()
    @test length(chapters) <= 26

    for width in (60, 72, 80, 96)
        manual = TerminalPager._manual(false, TerminalPager.DisplayConfig(), width)
        lines = String.(split(manual.text, '\n'))

        # The manual fits in the width it was laid out for, and it has no decorations.
        @test all(line -> textwidth(line) <= width, lines)
        @test !occursin('\e', manual.text)
        @test length(manual.layout) == length(lines)

        # It begins with the banner, and it has the table of contents.
        @test startswith(lines[1], "  ╭─")
        @test occursin("TerminalPager.jl $(TerminalPager._pkg_version())", lines[2])
        @test occursin("Extended help", lines[2])
        @test "  CONTENTS" in lines

        # Each chapter has a bookmark on its title, which is on a rule.
        letters = TerminalPager._manual_letter.(eachindex(chapters))
        @test sort!(collect(keys(manual.bookmarks))) == letters

        for (i, chapter) in enumerate(chapters)
            letter = TerminalPager._manual_letter(i)
            line, column = manual.bookmarks[letter]
            @test column == 1
            @test startswith(lines[line], "  ━━ $letter · $(chapter.title) ━")
            @test any(l -> occursin("[$letter] $(chapter.title)", l), lines)
        end

        # The boxes are closed at the same column on every row.
        box_width = width - 2
        for line in lines
            startswith(line, "  │ ") && endswith(line, "│") &&
                @test textwidth(line) == box_width
        end
    end

    # The decorated manual has the same text, but for the key caps.
    plain = _manual_plain(72)
    colored = TerminalPager._manual(true, TerminalPager.DisplayConfig(), 72)
    colored_lines = split(TerminalPager.remove_decorations(colored.text), '\n')
    @test occursin('\e', colored.text)
    @test length(colored_lines) == length(plain)
    @test textwidth.(colored_lines) == textwidth.(plain)
    @test replace.(colored_lines, r"[\[\]]" => " ") == replace.(plain, r"[\[\]]" => " ")

    # The width follows the view between its bounds.
    @test TerminalPager._manual_width(20) == 60
    @test TerminalPager._manual_width(75) == 75
    @test TerminalPager._manual_width(200) == 96
end

@testset "Extended Help Content" begin
    actions = TerminalPager._ACTIONS
    chapters = TerminalPager._manual_chapters()
    kinds = (
        :paragraph,
        :heading,
        :keys,
        :definitions,
        :list,
        :steps,
        :tip,
        :note,
        :warning,
        :example,
        :figure,
    )

    # Every action named in the manual exists, so that a renamed action cannot leave a key
    # shown as unbound. The empty action is the example of an unbound one.
    for chapter in chapters, block in chapter.blocks
        @test block.kind in kinds

        texts = String[block.text]
        block.kind in (:example, :figure) || append!(texts, last.(block.items))

        for text in texts, m in eachmatch(r"\{:(\w+)\}", text)
            @test Symbol(m[1]) in actions
        end

        block.kind === :keys || continue

        for (key, _) in block.items
            startswith(key, ':') && @test Symbol(key[2:end]) in actions
        end
    end

    # The last chapter lists every action of the cheat sheet with its name.
    reference_lines = String[]

    for block in chapters[end].blocks
        append!(reference_lines, _manual_block_lines(block, 200))
    end

    reference = join(reference_lines, '\n')

    for section in TerminalPager._HELP_SECTIONS, entry in section.actions
        @test occursin(":$(entry.action)", reference)
    end

    # Every preference and every face is described.
    text = join(_manual_plain(96), '\n')

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
    manual = TerminalPager._manual(false, config, 72)

    # The manual is rendered once for the same key bindings, faces, colors, and width.
    @test TerminalPager._manual(false, config, 72) === manual
    @test TerminalPager._manual(false, config, 80) !== manual
    @test TerminalPager._manual(true, config, 72) !== manual

    try
        TerminalPager.set_keybinding("X", :search)
        TerminalPager.delete_keybinding("/")
        rebound = TerminalPager._manual(false, config, 72)
        @test rebound !== manual
        @test occursin(r"search with\s+\[X\]", rebound.text)
        @test TerminalPager._manual_key_name(":search") == "X"
    finally
        TerminalPager.reset_keybindings()
    end

    @test TerminalPager._manual_key_name(":search") == "/"
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

    # Without the feature, the key does nothing.
    @test isnothing(TerminalPager._action_event(:extended_help, [:visual_mode]))
end
