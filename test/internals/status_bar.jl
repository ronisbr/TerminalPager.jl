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
    pagerd.cropped_lines = 11

    # The bar fills the whole row. The view has nine rows, so lines 1 to 9 are visible.
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL] lines 1–9/20" * " "^17 * " ?:help  q:quit   45% "
    @test textwidth(text) == 60

    # Without the help feature, only the quit hint is shown.
    pagerd.features = Symbol[]
    text = _status_bar_text(pagerd, output)
    @test endswith(text, " q:quit   45% ")
    @test !occursin("help", text)
    @test textwidth(text) == 60

    # Searching shows the active match.
    pagerd.mode = :searching
    pagerd.ordered_search_matches = [TerminalPager.SearchMatch(i, 1, 1, 1) for i in 1:5]
    pagerd.active_search_match_id = 2
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "[SEARCH] lines 1–9/20  match 2/5 ")

    empty!(pagerd.ordered_search_matches)
    pagerd.active_search_match_id = 0
    @test startswith(_status_bar_text(pagerd, output), "[SEARCH] lines 1–9/20  no match ")
    pagerd.mode = :view

    # The visual mode shows the number of selected lines.
    pagerd.visual_mode = true
    push!(pagerd.visual_mode_selected_lines, 3)
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "[VISUAL] lines 1–9/20  1 selected ")
    pagerd.visual_mode = false
    empty!(pagerd.visual_mode_selected_lines)

    # The enabled features are listed. The key hints only take the space that is left.
    pagerd.frozen_rows = 2
    pagerd.frozen_columns = 3
    pagerd.title_rows = 1
    pagerd.show_ruler = true
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "[NORMAL] lines 1–9/20  frozen 2×3  titles 1  ruler ")
    @test endswith(text, " 45% ")
    @test !occursin("quit", text)
    @test textwidth(text) == 60

    pagerd.display_size = (10, 70)
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "[NORMAL] lines 1–9/20  frozen 2×3  titles 1  ruler ")
    @test endswith(text, " q:quit   45% ")
    @test textwidth(text) == 70
end

@testset "Status Bar Columns" begin
    # The columns are shown only when the text is wider than the view.
    pagerd, output = _create_status_pagerd(["x"^100, "y"^50]; display_size = (10, 50))
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "[NORMAL] lines 1–2/2  cols 1–50/100 ")
    @test textwidth(text) == 50

    pagerd.start_column = 30
    @test occursin(" cols 30–79/100 ", _status_bar_text(pagerd, output))

    # The frozen columns and the ruler reduce the visible columns.
    pagerd.start_column = 1
    pagerd.frozen_columns = 5
    pagerd.show_ruler = true
    ruler_width = TerminalPager._ruler_width(2)
    text = _status_bar_text(pagerd, output)
    @test occursin(" cols 1–$(50 - 5 - ruler_width)/100 ", text)

    pagerd, output = _create_status_pagerd(["short"]; display_size = (10, 40))
    @test !occursin("cols", _status_bar_text(pagerd, output))
end

@testset "Status Bar Fits Narrow Displays" begin
    lines = ["line $i" for i in 1:20]
    pagerd, output = _create_status_pagerd(lines; display_size = (10, 30))
    pagerd.features = [:help]
    pagerd.cropped_lines = 11

    # The hints are dropped first, then the scroll position.
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL] lines 1–9/20" * " "^4 * " 45% "
    @test textwidth(text) == 30

    pagerd.display_size = (10, 22)
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL] lines 1–9/20 "
    @test textwidth(text) == 22

    # The badge is the last segment to go, and it is cut at the display width.
    pagerd.display_size = (10, 12)
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL]" * " "^4

    pagerd.display_size = (10, 5)
    @test _status_bar_text(pagerd, output) == "[NORM"

    pagerd.display_size = (10, 0)
    @test _status_bar_text(pagerd, output) == ""
end

@testset "Status Bar Messages and Colors" begin
    pagerd, output = _create_status_pagerd(["line"]; display_size = (10, 30))

    # A message replaces every segment but the badge, carries an icon telling its kind, and
    # is cut at the display width.
    TerminalPager._set_message!(pagerd, "Invalid regex"; kind = :error)
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL] ✗ Invalid regex" * " "^6
    @test textwidth(text) == 30

    TerminalPager._set_message!(pagerd, "A very long message that does not fit the row")
    text = _status_bar_text(pagerd, output)
    @test text == "[NORMAL] ✓ A very long message"
    @test textwidth(text) == 30

    # An empty text is reported as such.
    pagerd, output = _create_status_pagerd(String[]; display_size = (10, 30))
    @test _status_bar_text(pagerd, output) == "[NORMAL] empty" * " "^2 * " q:quit  100% "

    # With color, the bar is drawn in reverse video with a colored badge, and it ends with a
    # reset before the cursor is parked.
    pagerd, output = _create_status_pagerd(["line"]; color = true, display_size = (10, 30))
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    badge = TerminalPager._CRAYON_BADGE_NORMAL * " NORMAL " * TerminalPager._CRAYON_BAR
    @test occursin(badge, colored)
    @test endswith(colored, "\e[0m\e[10;1H")

    TerminalPager._set_message!(pagerd, "Invalid regex"; kind = :error)
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    @test occursin(TerminalPager._CRAYON_MESSAGE_ERROR * " ✗ Invalid regex", colored)

    TerminalPager._set_message!(pagerd, "3 lines copied")
    TerminalPager._redraw_status_bar!(pagerd)
    colored = String(take!(output))
    @test occursin(TerminalPager._CRAYON_MESSAGE_INFO * " ✓ 3 lines copied", colored)

    pagerd.mode = :searching
    TerminalPager._clear_message!(pagerd)
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(TerminalPager._CRAYON_BADGE_SEARCH * " SEARCH ", String(take!(output)))
end

@testset "Status Bar Key Hints" begin
    @test TerminalPager._pretty_key(("<up>", true, false, false)) == "Alt-↑"
    @test TerminalPager._pretty_key(("<F1>", false, false, true)) == "Shift-F1"
    @test TerminalPager._pretty_key((" ", false, false, false)) == "Space"
    @test TerminalPager._pretty_key(("<eot>", false, false, false)) == "Ctrl-D"
    @test TerminalPager._pretty_key(("a", false, true, false)) == "Ctrl-a"
    @test TerminalPager._pretty_key(("<", false, false, false)) == "<"

    # The hints follow the key bindings and pick the shortest name.
    try
        @test TerminalPager._primary_key(:quit) == "q"
        @test TerminalPager._primary_key(:home) == "<"
        @test TerminalPager._status_hint(true) == "?:help  q:quit"
        @test TerminalPager._status_hint(false) == "q:quit"

        TerminalPager.delete_keybinding("q")
        @test isnothing(TerminalPager._primary_key(:quit))
        @test TerminalPager._status_hint(true) == "?:help"
        @test TerminalPager._status_hint(false) == ""

        TerminalPager.set_keybinding("<F10>", :quit)
        @test TerminalPager._status_hint(false) == "F10:quit"
    finally
        TerminalPager.reset_keybindings()
    end

    @test TerminalPager._status_hint(true) == "?:help  q:quit"
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
    # The visible columns exclude the scrollbar column.
    pagerd, output = _create_status_pagerd(["x"^100]; display_size = (10, 50))
    pagerd.show_scrollbar = true
    @test occursin(" cols 1–49/100 ", _status_bar_text(pagerd, output))

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
