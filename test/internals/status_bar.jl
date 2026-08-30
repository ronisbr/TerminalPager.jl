## Description #############################################################################
#
# Tests for the status bar.
#
############################################################################################

"""
    _create_status_pagerd(lines::Vector{String}; kwargs...) -> Tuple{TerminalPager.Pager,
        IOBuffer}

Create a pager whose terminal output is an in-memory buffer, returning both.

# Arguments

- `lines::Vector{String}`: Pager text, one entry per line.

# Keywords

- `color::Bool`: Whether the terminal output supports color.
    (**Default**: `false`)
- `display_size::NTuple{2, Int}`: Terminal rows and columns.
    (**Default**: `(10, 60)`)
"""
function _create_status_pagerd(
    lines::Vector{String}; color::Bool = false, display_size::NTuple{2, Int} = (10, 60)
)
    output = IOBuffer()
    input = IOBuffer()
    out_stream = IOContext(output, :color => color)
    term = REPL.Terminals.TTYTerminal("", input, out_stream, out_stream)
    text_layout = TerminalPager.TextViewLayout(lines)

    pagerd = TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => color),
        display_size = display_size,
        input = TerminalPager.PagerInput(input),
        num_lines = length(lines),
        term = term,
        text_layout = text_layout,
    )

    return pagerd, output
end

"""
    _status_bar_text(pagerd::TerminalPager.Pager, output::IOBuffer) -> String

Redraw the status bar of `pagerd` and return it without the escape sequences.

# Arguments

- `pagerd::TerminalPager.Pager`: Pager state to redraw.
- `output::IOBuffer`: Buffer receiving the terminal output.
"""
function _status_bar_text(pagerd::TerminalPager.Pager, output::IOBuffer)
    TerminalPager._redraw_status_bar!(pagerd)
    return replace(String(take!(output)), r"\e\[[0-9;?]*[A-Za-z]" => "")
end

@testset "Status Bar Segments" begin
    lines = ["line $i" for i in 1:20]
    pagerd, output = _create_status_pagerd(lines)
    pagerd.features = [:help]
    pagerd.start_row = 5
    pagerd.cropped_lines = 11

    # In the normal mode, the row holds the prompt glyph, the key hints, and the position.
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^39 * "?:help  q:quit   45%"
    @test textwidth(text) == 60

    # Without the help feature, only the quit hint is shown.
    pagerd.features = Symbol[]
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^47 * "q:quit   45%"
    @test textwidth(text) == 60

    # Searching shows the mode name, the active match, and the hints of the search mode.
    pagerd.mode = :searching
    pagerd.ordered_search_matches = [TerminalPager.SearchMatch(i, 1, 1, 1) for i in 1:5]
    pagerd.active_search_match_id = 2
    text = _status_bar_text(pagerd, output)
    @test text == "SEARCH  match 2/5" * " "^12 * "n:next  N:prev  Esc:clear   45%"
    @test textwidth(text) == 60

    empty!(pagerd.ordered_search_matches)
    pagerd.active_search_match_id = 0
    @test startswith(_status_bar_text(pagerd, output), "SEARCH  no match ")
    pagerd.mode = :view

    # The visual mode shows the number of selected lines and its own hints.
    pagerd.visual_mode = true
    push!(pagerd.visual_mode_selected_lines, 3)
    text = _status_bar_text(pagerd, output)
    @test text == "VISUAL  1 selected" * " "^13 * "m:mark  y:yank  v:leave   45%"
    pagerd.visual_mode = false
    empty!(pagerd.visual_mode_selected_lines)

    # The enabled features are tagged before the key hints.
    pagerd.frozen_rows = 2
    pagerd.frozen_columns = 3
    pagerd.title_rows = 1
    pagerd.show_ruler = true
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^17 * "frozen 2×3  titles 1  ruler   q:quit   45%"
    @test textwidth(text) == 60

    # The key hints are dropped before the tags when the display is too narrow.
    pagerd.display_size = (10, 44)
    text = _status_bar_text(pagerd, output)
    @test text == "❯ frozen 2×3  titles 1  ruler   q:quit   45%"

    pagerd.display_size = (10, 43)
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^9 * "frozen 2×3  titles 1  ruler   45%"
    @test textwidth(text) == 43
end

@testset "Status Bar Position" begin
    lines = ["line $i" for i in 1:20]
    pagerd, output = _create_status_pagerd(lines; display_size = (10, 30))

    # The whole text is visible, the top, the bottom, or a percentage in between. The
    # percentage never reaches 100, because the bottom has its own token.
    pagerd.cropped_lines = 11
    @test endswith(_status_bar_text(pagerd, output), "q:quit   Top")
    pagerd.start_row = 12
    pagerd.cropped_lines = 0
    @test endswith(_status_bar_text(pagerd, output), "q:quit   Bot")
    pagerd.start_row = 2
    pagerd.cropped_lines = 10
    @test endswith(_status_bar_text(pagerd, output), "q:quit   50%")
    pagerd.cropped_lines = 1
    @test endswith(_status_bar_text(pagerd, output), "q:quit   95%")
    pagerd.cropped_lines = 19
    @test endswith(_status_bar_text(pagerd, output), "q:quit    5%")

    # With frozen rows, the top is the first scrollable row.
    pagerd.frozen_rows = 2
    pagerd.start_row = 3
    pagerd.cropped_lines = 11
    @test endswith(_status_bar_text(pagerd, output), "   Top")
    pagerd.start_row = 4
    @test endswith(_status_bar_text(pagerd, output), "   45%")

    pagerd, output = _create_status_pagerd(["a", "b"]; display_size = (10, 30))
    @test endswith(_status_bar_text(pagerd, output), "q:quit   All")

    pagerd, output = _create_status_pagerd(String[]; display_size = (10, 30))
    @test _status_bar_text(pagerd, output) == "❯" * " "^17 * "q:quit   All"
end

@testset "Status Bar Hidden Text Hints" begin
    # The hints tell that the text continues beyond the left or the right edge of the view.
    # They keep a slot of two columns, so that the key hints do not move while scrolling.
    pagerd, output = _create_status_pagerd(["x"^100, "y"^50]; display_size = (10, 50))
    TerminalPager._view!(pagerd)
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^33 * "q:quit    ›  All"
    @test textwidth(text) == 50

    pagerd.start_column = 30
    TerminalPager._view!(pagerd)
    @test endswith(_status_bar_text(pagerd, output), "q:quit   ‹›  All")

    pagerd.start_column = 51
    TerminalPager._view!(pagerd)
    @test endswith(_status_bar_text(pagerd, output), "q:quit   ‹   All")

    # The frozen columns are never hidden.
    pagerd.frozen_columns = 5
    pagerd.start_column = 6
    TerminalPager._view!(pagerd)
    @test endswith(_status_bar_text(pagerd, output), "q:quit    ›  All")

    pagerd, output = _create_status_pagerd(["short"]; display_size = (10, 40))
    TerminalPager._view!(pagerd)
    text = _status_bar_text(pagerd, output)
    @test !occursin("‹", text)
    @test !occursin("›", text)
end

@testset "Status Bar Fits Narrow Displays" begin
    lines = ["line $i" for i in 1:20]
    pagerd, output = _create_status_pagerd(lines; display_size = (10, 30))
    pagerd.features = [:help]
    pagerd.start_row = 5
    pagerd.cropped_lines = 11

    # The hints are dropped first, then the position.
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^9 * "?:help  q:quit   45%"
    @test textwidth(text) == 30

    pagerd.display_size = (10, 19)
    text = _status_bar_text(pagerd, output)
    @test text == "❯" * " "^15 * "45%"
    @test textwidth(text) == 19

    pagerd.display_size = (10, 5)
    @test _status_bar_text(pagerd, output) == "❯ 45%"

    pagerd.display_size = (10, 2)
    @test _status_bar_text(pagerd, output) == "❯ "

    # The mode name is the last segment to go: first the details, then the position.
    pagerd.mode = :searching
    pagerd.ordered_search_matches = [TerminalPager.SearchMatch(i, 1, 1, 1) for i in 1:5]
    pagerd.active_search_match_id = 2
    pagerd.display_size = (10, 24)
    @test _status_bar_text(pagerd, output) == "SEARCH  match 2/5    45%"
    pagerd.display_size = (10, 20)
    @test _status_bar_text(pagerd, output) == "SEARCH" * " "^11 * "45%"
    pagerd.display_size = (10, 9)
    @test _status_bar_text(pagerd, output) == "SEARCH" * " "^3
    pagerd.display_size = (10, 5)
    @test _status_bar_text(pagerd, output) == "SEARC"

    pagerd.display_size = (10, 0)
    @test _status_bar_text(pagerd, output) == ""
end

@testset "Status Bar Messages and Colors" begin
    pagerd, output = _create_status_pagerd(["line"]; display_size = (10, 30))

    # A message replaces the left side, carries an icon telling its kind, keeps the position,
    # and is cut at the display width.
    TerminalPager._set_message!(pagerd, "Invalid regex"; kind = :error)
    text = _status_bar_text(pagerd, output)
    @test text == "✗ Invalid regex" * " "^12 * "All"
    @test textwidth(text) == 30

    TerminalPager._set_message!(pagerd, "A very long message that does not fit the row")
    text = _status_bar_text(pagerd, output)
    @test text == "✓ A very long message that All"
    @test textwidth(text) == 30

    # A message hides the mode name.
    pagerd.mode = :searching
    @test startswith(_status_bar_text(pagerd, output), "✓ A very long")
    pagerd.mode = :view
    TerminalPager._clear_message!(pagerd)

    # With color, the row starts with the base face, the mode name and the hints have their
    # own faces and return to the base, and the row ends with a reset before the cursor is
    # parked.
    pagerd, output = _create_status_pagerd(["line"]; color = true, display_size = (10, 30))
    config = pagerd.display_config
    @test config.status_bar == "\e[0m"
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    @test occursin("\e[0K" * config.status_bar * "❯", colored)
    @test occursin(config.status_hint * "q:quit" * config.status_bar, colored)
    @test endswith(colored, "All\e[0m\e[10;1H")

    TerminalPager._set_message!(pagerd, "Invalid regex"; kind = :error)
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    @test occursin(config.message_error * "✗ Invalid regex" * config.status_bar, colored)

    TerminalPager._set_message!(pagerd, "3 lines copied")
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    @test occursin(config.message_info * "✓ 3 lines copied", colored)

    pagerd.mode = :searching
    TerminalPager._clear_message!(pagerd)
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(config.mode_search * "SEARCH" * config.status_bar, String(take!(output)))

    pagerd.mode = :view
    pagerd.visual_mode = true
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(config.mode_visual * "VISUAL" * config.status_bar, String(take!(output)))
end

@testset "Status Bar Key Hints" begin
    @test TerminalPager._pretty_key(("<up>", true, false, false)) == "Alt-↑"
    @test TerminalPager._pretty_key(("<F1>", false, false, true)) == "Shift-F1"
    @test TerminalPager._pretty_key((" ", false, false, false)) == "Space"
    @test TerminalPager._pretty_key(("<eot>", false, false, false)) == "Ctrl-D"
    @test TerminalPager._pretty_key(("a", false, true, false)) == "Ctrl-A"
    @test TerminalPager._pretty_key(("j", true, false, false)) == "Alt-j"
    @test TerminalPager._pretty_key(("<", false, false, false)) == "<"

    # The hints follow the key bindings and the mode, and pick the shortest name.
    try
        @test TerminalPager._primary_key(:quit) == "q"
        @test TerminalPager._primary_key(:home) == "<"
        @test TerminalPager._status_hint(:normal, true) == "?:help  q:quit"
        @test TerminalPager._status_hint(:normal, false) == "q:quit"
        @test TerminalPager._status_hint(:search, true) == "n:next  N:prev  Esc:clear"
        @test TerminalPager._status_hint(:visual, true) == "m:mark  y:yank  v:leave"

        TerminalPager.delete_keybinding("q")
        @test isnothing(TerminalPager._primary_key(:quit))
        @test TerminalPager._status_hint(:normal, true) == "?:help"
        @test TerminalPager._status_hint(:normal, false) == ""

        TerminalPager.set_keybinding("<F10>", :quit)
        @test TerminalPager._status_hint(:normal, false) == "F10:quit"

        # An unbound action is skipped without leaving a gap.
        TerminalPager.delete_keybinding("N")
        @test TerminalPager._status_hint(:search, false) == "n:next  Esc:clear"
    finally
        TerminalPager.reset_keybindings()
    end

    @test TerminalPager._status_hint(:normal, true) == "?:help  q:quit"
end

@testset "Session Cursor and Exit" begin
    # The cursor is hidden for the whole session and shown again at the end, when the status
    # bar row is cleared so that the scrollback ends with the last page of the text.
    input = IOBuffer("q")
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    TerminalPager._pager!(
        term,
        "a\nb\nc";
        input = TerminalPager.PagerInput(input),
        use_alternate_screen_buffer = false,
    )
    session = String(take!(output))
    rows = displaysize(output)[1]

    @test occursin("\e[?25l", session)
    @test endswith(session, "\e[$(rows);1H\e[0m\e[0K\e[?25h\e[?1l")

    # With the alternate screen buffer, which is the default, the terminal restores the
    # previous content, so the status bar row is not cleared.
    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    TerminalPager._pager!(term, "a\nb\nc"; input = TerminalPager.PagerInput(input))
    session = String(take!(output))
    @test occursin("\e[?1049h", session)
    @test endswith(session, "\e[?25h\e[?1049l\e[?1l")

    # A nested session leaves the cursor alone.
    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    TerminalPager._pager!(
        term, "a\nb\nc"; input = TerminalPager.PagerInput(input), manage_cursor = false,
        manage_cursor_key_mode = false,
    )
    session = String(take!(output))
    @test !occursin("\e[?25", session)

    # The command editor shows the cursor while a command is typed and hides it afterwards.
    pagerd = _create_modal_pagerd(["x"], "ab\n")
    @test TerminalPager._read_cmd!(pagerd) == "ab"
    edited = String(take!(pagerd.term.out_stream))
    @test occursin("\e[?25h", edited)
    @test endswith(edited, "\e[?25l")
end

@testset "Session Mouse Reporting" begin
    # The mouse is reported during the session and released at the end, unless the
    # preference disables it. A nested session leaves it alone.
    input = IOBuffer("q")
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    TerminalPager._pager!(term, "a\nb"; input = TerminalPager.PagerInput(input))
    session = String(take!(output))
    @test occursin("\e[?1000h\e[?1006h", session)
    @test occursin("\e[?1006l\e[?1000l", session)
    @test findfirst("\e[?1006l", session).start < findfirst("\e[?25h", session).start

    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    TerminalPager._pager!(
        term, "a\nb"; input = TerminalPager.PagerInput(input), manage_mouse = false
    )
    @test !occursin("\e[?1000", String(take!(output)))

    try
        TerminalPager.set_preference!("mouse", false)
        input = IOBuffer("q")
        term = REPL.Terminals.TTYTerminal("", input, output, output)
        TerminalPager._pager!(term, "a\nb"; input = TerminalPager.PagerInput(input))
        @test !occursin("\e[?1000", String(take!(output)))
    finally
        TerminalPager.drop_preference!("mouse")
    end

    @test TerminalPager._get_preference("mouse") == true
end

@testset "Status Bar With the Scrollbar" begin
    # The text cut by the scrollbar column is reported as hidden.
    pagerd, output = _create_status_pagerd(["x"^50]; display_size = (10, 50))
    TerminalPager._view!(pagerd)
    @test !occursin("›", _status_bar_text(pagerd, output))
    pagerd.show_scrollbar = true
    TerminalPager._view!(pagerd)
    @test occursin(" ›  ", _status_bar_text(pagerd, output))

    # The keyword and the preference select the initial state.
    input = IOBuffer("q")
    out = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, out, out)
    TerminalPager._pager!(
        term, "a\nb"; input = TerminalPager.PagerInput(input), show_scrollbar = true
    )
    @test occursin(TerminalPager._SCROLLBAR_THUMB, String(take!(out)))

    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, out, out)
    TerminalPager._pager!(term, "a\nb"; input = TerminalPager.PagerInput(input))
    @test !occursin(TerminalPager._SCROLLBAR_THUMB, String(take!(out)))

    try
        TerminalPager.set_preference!("show_scrollbar", true)
        input = IOBuffer("q")
        term = REPL.Terminals.TTYTerminal("", input, out, out)
        TerminalPager._pager!(term, "a\nb"; input = TerminalPager.PagerInput(input))
        @test occursin(TerminalPager._SCROLLBAR_THUMB, String(take!(out)))
    finally
        TerminalPager.drop_preference!("show_scrollbar")
    end
end

@testset "Nested Help Keeps the Screen Buffer" begin
    # Opening and closing the help used to toggle the alternate screen buffer a second time,
    # which switched the terminal back to the normal screen while the parent session kept
    # painting as if it were on the alternate one.
    input = IOBuffer("?qq")
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    lines = join(["row $i " * "x"^30 for i in 1:40], '\n')
    TerminalPager._pager!(term, lines; input = TerminalPager.PagerInput(input))
    session = String(take!(output))

    @test count("\e[?1049h", session) == 1
    @test count("\e[?1049l", session) == 1
    @test count("\e[2J", session) == 1
    @test endswith(session, "\e[?25h\e[?1049l\e[?1l")
    @test count("\e[?1000h", session) == 1
    @test count("\e[?25l", session) == 1
end
