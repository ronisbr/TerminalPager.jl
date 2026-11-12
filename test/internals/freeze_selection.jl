## Description #############################################################################
#
# Tests for the freeze selection mode.
#
############################################################################################

"""
    _create_freeze_pagerd(lines::Vector{String}, chunks::Vector{String}; kwargs...) ->
        TerminalPager.Pager

Create a pager with the `:change_freeze` feature whose terminal is backed by an in-memory
buffer and whose shared input delivers each entry of `chunks` at once, like a mouse report.

# Arguments

- `lines::Vector{String}`: Pager text, one entry per line.
- `chunks::Vector{String}`: Bytes of each arrival of the input.

# Keywords

- `display_size::NTuple{2, Int}`: Terminal rows and columns.
    (**Default**: `(10, 40)`)
- `kwargs...`: Fields of the pager to set after it is created.
"""
function _create_freeze_pagerd(
    lines::Vector{String},
    chunks::Vector{String};
    display_size::NTuple{2, Int} = (10, 40),
    kwargs...,
)
    input = TypedInput(chunks)
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    text_layout = TerminalPager.TextViewLayout(lines)

    pagerd = TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => false),
        display_size = display_size,
        features = [:change_freeze],
        input = TerminalPager.PagerInput(input),
        num_lines = length(lines),
        term = term,
        text_layout = text_layout,
    )

    for (field, value) in kwargs
        setfield!(pagerd, field, value)
    end

    return pagerd
end

"""
    _create_freeze_pagerd(lines::Vector{String}, keys::AbstractString; kwargs...) ->
        TerminalPager.Pager

Create a pager with the `:change_freeze` feature whose shared input delivers each keystroke
of `keys` on its own, as typed keys.
"""
function _create_freeze_pagerd(lines::Vector{String}, keys::AbstractString; kwargs...)
    return _create_freeze_pagerd(lines, TypedInput(keys).chunks .|> String; kwargs...)
end

"""
    _run_select_freeze!(pagerd::TerminalPager.Pager) -> String

Run the freeze selection event on `pagerd` and return the text sent to the terminal.
"""
function _run_select_freeze!(pagerd::TerminalPager.Pager)
    pagerd.event = :select_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    return String(take!(pagerd.term.out_stream))
end

# Thirty lines wider than the display.
const _FREEZE_LINES = [
    "row $i " * join(("v$(i)_$j" for j in 1:10), " ") for i in 1:30
]

@testset "Freeze Selection Key Binding and Feature Gate" begin
    k = TerminalPager.Keystroke(; value = "F")
    @test TerminalPager._pager_action(k) === :select_freeze

    pagerd = _create_redraw_pagerd(_FREEZE_LINES)
    pagerd.features = [:change_freeze]
    TerminalPager._pager_key_process!(pagerd, k)
    @test pagerd.event === :select_freeze

    # The action requires the feature, like the numeric prompt.
    pagerd.features = Symbol[]
    TerminalPager._pager_key_process!(pagerd, k)
    @test pagerd.event === nothing
end

@testset "Freeze Selection Applies the Selection" begin
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, "jjl\r"; start_row = 12, start_column = 5, cropped_lines = 3
    )
    output = _run_select_freeze!(pagerd)

    @test pagerd.frozen_rows == 2
    @test pagerd.frozen_columns == 1
    @test pagerd.mode === :view
    @test pagerd.message == "Frozen 2 rows × 1 columns"
    @test pagerd.message_kind === :info
    @test pagerd.redraw

    # The viewport is restored, and the crop counters are recomputed by the next frame.
    @test pagerd.start_row == 12
    @test pagerd.start_column == 5
    @test pagerd.cropped_lines == 0
    @test pagerd.cropped_columns == 0

    # The status line showed the mode and the live selection, and the view started at the
    # top-left corner, with the vertical guide over the first column of the first line.
    @test occursin("FREEZE", output)
    @test occursin("2×1", output)
    @test occursin("┃ow 1 v1_1", TerminalPager.remove_decorations(output))

    # The restored viewport is clamped to the frozen region.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, "jjjll\r"; start_row = 2, start_column = 1
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 3
    @test pagerd.frozen_columns == 2
    @test pagerd.start_row == 4
    @test pagerd.start_column == 3

    # The keypad Enter applies the selection as well, and the previous mode is restored.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "j\eOM"; mode = :searching)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 1
    @test pagerd.mode === :searching

    # The visual line is moved back to the top of the view, and the marks are kept.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, "j\r"; visual_mode = true, visual_mode_line = 5
    )
    push!(pagerd.visual_mode_selected_lines, 7)
    _run_select_freeze!(pagerd)
    @test pagerd.visual_mode
    @test pagerd.visual_mode_line == 1
    @test pagerd.visual_mode_selected_lines == [7]
end

@testset "Freeze Selection Cancels" begin
    for keys in ("jjl\e", "jjlq", "jjl\x03", "jjl\x04")
        pagerd = _create_freeze_pagerd(
            _FREEZE_LINES,
            keys;
            start_row = 12,
            start_column = 5,
            frozen_rows = 1,
            frozen_columns = 2,
            mode = :searching,
        )
        _run_select_freeze!(pagerd)

        @test pagerd.frozen_rows == 1
        @test pagerd.frozen_columns == 2
        @test pagerd.start_row == 12
        @test pagerd.start_column == 5
        @test pagerd.mode === :searching
        @test isempty(pagerd.message)
        @test pagerd.redraw
    end
end

@testset "Freeze Selection Starts at the Current Values and Clamps" begin
    # The selection starts at the current values.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "\r"; frozen_rows = 3, frozen_columns = 4)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 3
    @test pagerd.frozen_columns == 4

    # The rows are bounded by the view and by the text, and the columns by the view and by
    # the widest line. The guides are drawn after the selection, so the view bounds leave
    # one row and one column for them.
    pagerd = _create_freeze_pagerd(
        ["abc", "de", "f", "", "ghij"], "\r"; frozen_rows = 50, frozen_columns = 100
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 5
    @test pagerd.frozen_columns == 4

    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "\$G\r")
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 8
    @test pagerd.frozen_columns == 39

    # The ruler and the scrollbar reduce the columns.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "\$\r"; show_ruler = true)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_columns == 39 - TerminalPager._ruler_width(30)

    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "\$\r"; show_scrollbar = true)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_columns == 38

    # The title rows always stay frozen.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "kkkk\r"; title_rows = 2)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 2

    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "g0\r"; title_rows = 2, frozen_rows = 6)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 2
    @test pagerd.frozen_columns == 0
end

@testset "Freeze Selection Fast Moves and Jumps" begin
    pagerd = _create_redraw_pagerd(_FREEZE_LINES; display_size = (10, 40))
    pagerd.mode = :freeze_selection

    move!(action, value; kwargs...) = TerminalPager._move_freeze_selection!(
        pagerd, action, TerminalPager.Keystroke(; value = value, kwargs...)
    )

    move!(:fastdown, "<down>"; shift = true)
    move!(:fastright, "<right>"; shift = true)
    @test pagerd.freeze_selection_rows == 5
    @test pagerd.freeze_selection_columns == 10
    @test pagerd.redraw

    pagerd.redraw = false
    move!(:fastup, "<up>"; shift = true)
    move!(:fastleft, "<left>"; shift = true)
    @test pagerd.freeze_selection_rows == 0
    @test pagerd.freeze_selection_columns == 0
    @test pagerd.redraw

    move!(:end, "G")
    move!(:eol, "\$")
    @test pagerd.freeze_selection_rows == 8
    @test pagerd.freeze_selection_columns == 39

    move!(:home, "g")
    move!(:bol, "0")
    @test pagerd.freeze_selection_rows == 0
    @test pagerd.freeze_selection_columns == 0

    # A keystroke that is not a movement does not request a redraw.
    pagerd.redraw = false
    move!(:toggle_ruler, "r")
    move!(:wheel_down, "<wheel_down>")
    move!(nothing, "x")
    @test pagerd.freeze_selection_rows == 0
    @test pagerd.freeze_selection_columns == 0
    @test !pagerd.redraw
end

@testset "Freeze Selection Refuses Without Room" begin
    # The title rows must leave at least one row for the text.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "q"; title_rows = 9, start_row = 10)
    _run_select_freeze!(pagerd)
    @test pagerd.message == "Not enough rows to show the 9 title rows"
    @test pagerd.message_kind === :error
    @test pagerd.frozen_rows == 0
    @test pagerd.start_row == 10
    @test pagerd.mode === :view

    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "\r"; title_rows = 8)
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 8

    # An empty text has nothing to freeze.
    pagerd = _create_freeze_pagerd(String[], "q")
    _run_select_freeze!(pagerd)
    @test pagerd.message == "Nothing to freeze"
    @test pagerd.message_kind === :error
end

@testset "Freeze Selection Mouse Press and Drag" begin
    # A press puts the guides on the pointer, selecting the rows above it and the columns at
    # its left, and a drag follows it.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, ["\e[<0;5;3M", "\e[<32;7;4M", "\r"])
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 3
    @test pagerd.frozen_columns == 6

    # The ruler is not part of the columns, and a press on it selects none.
    ruler_width = TerminalPager._ruler_width(30)
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, ["\e[<0;$(ruler_width + 3);3M", "\r"]; show_ruler = true
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_columns == 2

    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, ["\e[<0;2;3M", "\r"]; show_ruler = true, frozen_columns = 5
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 2
    @test pagerd.frozen_columns == 0

    # A press on the status line is ignored, and one on the scrollbar column selects every
    # column.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, ["\e[<0;5;10M", "\r"]; frozen_rows = 2, frozen_columns = 2
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 2
    @test pagerd.frozen_columns == 2

    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, ["\e[<0;40;2M", "\r"]; show_scrollbar = true
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 1
    @test pagerd.frozen_columns == 38

    # The wheel and the release are ignored.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, ["\e[<64;5;3M", "\e[<65;5;3M", "\e[<0;5;3m", "\r"]
    )
    _run_select_freeze!(pagerd)
    @test pagerd.frozen_rows == 0
    @test pagerd.frozen_columns == 0
end

@testset "Freeze Guide Rendering" begin
    face = "\e[0;36;1m"
    lines = ["\e[1mabc\e[0mdef", "gh\e[1mijkl\e[0m", "x"]

    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_rows = 1
    pagerd.freeze_selection_columns = 2
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')

    @test length(rows) == 4

    # The vertical guide replaces the column after the selected ones, and the rest of the
    # row keeps its decorations.
    @test rows[1] == "\e[1mab" * face * "┃" * "\e[0m" * "\e[1m" * "\e[0mdef"

    # The horizontal guide replaces the row after the selected ones, edge to edge, with a
    # crossing on the vertical guide.
    @test rows[2] == face * "━━╋━━━━━━━━━" * "\e[0m"

    # A short row and a row past the end of the text are padded up to the vertical guide.
    @test rows[3] == "x " * face * "┃" * "\e[0m"
    @test rows[4] == "  " * face * "┃" * "\e[0m"

    for row in rows
        @test TerminalPager.printable_textwidth(row) <= 12
    end

    # The decoration state of the text under the guide is restored before the rest of the
    # row.
    pagerd = _create_redraw_pagerd(["ab", "\e[1mcdef\e[0m"]; display_size = (3, 12), color = true)
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_columns = 2
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test rows[1] == face * "━━╋━━━━━━━━━" * "\e[0m"
    @test rows[2] == "\e[1mcd" * face * "┃" * "\e[0m" * "\e[1m" * "f\e[0m"

    # Without selected rows and columns, the guides sit on the first row and column. The
    # escape sequences before the first character stay in front of the vertical guide.
    pagerd.freeze_selection_columns = 0
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test rows[1] == face * "╋━━━━━━━━━━━" * "\e[0m"
    @test rows[2] == "\e[1m" * face * "┃" * "\e[0m" * "\e[1m" * "def\e[0m"

    # A wide character under the vertical guide is replaced by blanks on both sides.
    pagerd = _create_redraw_pagerd(["a漢b"]; display_size = (3, 12), color = true)
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_rows = 1
    pagerd.freeze_selection_columns = 1
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test rows[1] == "a" * face * "┃" * "\e[0m" * " b"

    # The ruler is kept on every row, and both guides start after it. The rows past the end
    # of the text leave its columns blank.
    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    pagerd.mode = :freeze_selection
    pagerd.show_ruler = true
    pagerd.freeze_selection_rows = 1
    pagerd.freeze_selection_columns = 2
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test startswith(rows[1], "\e[0;90m 1 │\e[0m" * "\e[1mab" * face * "┃\e[0m")
    @test rows[2] == "\e[0;90m 2 │\e[0m" * face * "━━╋━━━━━" * "\e[0m"
    @test rows[4] == "      " * face * "┃" * "\e[0m"
    @test TerminalPager.printable_textwidth(rows[1]) == 10
    @test TerminalPager.printable_textwidth(rows[2]) == 12

    pagerd.freeze_selection_rows = 3
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test rows[4] == "    " * face * "━━╋━━━━━" * "\e[0m"
    pagerd.freeze_selection_rows = 1

    # The scrollbar is appended after the frame with the guides.
    pagerd.show_scrollbar = true
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test startswith(rows[2], "\e[0;90m 2 │\e[0m" * face * "━━╋━━━━" * "\e[0m" * "\e[12G")
    @test occursin("\e[12G", rows[4])

    # The visual backgrounds are not drawn, and the search matches outside the guides are.
    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    pagerd.visual_mode = true
    pagerd.visual_mode_line = 2
    TerminalPager._apply_search!(pagerd, r"kl")
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_rows = 2
    pagerd.freeze_selection_columns = 2
    TerminalPager._view!(pagerd)
    frame = String(take!(copy(pagerd.buf.io)))
    @test !occursin(pagerd.display_config.visual_active_line * "m", frame)
    @test occursin(pagerd.display_config.search_active_match, frame)

    # The incremental redraw repaints only the rows that changed: moving the horizontal
    # guide down by one changes the row it leaves and the row it enters, which are adjacent
    # and painted as a single run.
    pagerd = _create_redraw_pagerd(_FREEZE_LINES; display_size = (10, 40), color = true)
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_rows = 1
    pagerd.freeze_selection_columns = 2
    _paint!(pagerd)
    @test isempty(_paint!(pagerd))

    pagerd.freeze_selection_rows = 2
    output = _paint!(pagerd)
    @test occursin("\e[2;1H", output)
    @test !occursin("\e[1;1H", output)
    @test !occursin("\e[3;1H", output)
    @test !occursin("\e[4;1H", output)
    @test count("\r\n", output) == 1
end

@testset "Status Line in the Freeze Mode" begin
    pagerd, output = _create_status_pagerd(_FREEZE_LINES; display_size = (10, 60))
    pagerd.frozen_rows = 2
    pagerd.frozen_columns = 3
    pagerd.mode = :freeze_selection
    pagerd.freeze_selection_rows = 3
    pagerd.freeze_selection_columns = 4

    text = _status_bar_text(pagerd, output)
    @test startswith(text, "FREEZE  3×4")
    @test occursin("Enter:apply  Esc:cancel", text)
    @test !occursin("frozen", text)
    @test textwidth(text) == 60

    # The selection wins over the visual mode.
    pagerd.visual_mode = true
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "FREEZE  3×4")
    @test !occursin("selected", text)

    # The frozen tag is back once the selection is over.
    pagerd.mode = :view
    pagerd.visual_mode = false
    text = _status_bar_text(pagerd, output)
    @test startswith(text, "❯")
    @test occursin("frozen 2×3", text)

    # The mode name has its own face.
    pagerd, output = _create_status_pagerd(_FREEZE_LINES; color = true, display_size = (10, 60))
    pagerd.mode = :freeze_selection
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(pagerd.display_config.mode_freeze * "FREEZE", String(take!(output)))

    # The hints follow the key bindings.
    TerminalPager.set_keybinding("x", :quit_search)
    try
        @test occursin("Enter:apply  x:cancel", TerminalPager._status_hint(:freeze, true))
    finally
        TerminalPager.reset_keybindings()
    end
end
