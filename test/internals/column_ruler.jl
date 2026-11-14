## Description #############################################################################
#
# Tests for the column ruler.
#
############################################################################################

"""
    _column_ruler_rows(lines::Vector{String}; display_size = (6, 40), kwargs...) ->
        Tuple{String, String}

Render `lines` with the column ruler and return its two rows, setting the fields in `kwargs`
on the pager first.
"""
function _column_ruler_rows(
    lines::Vector{String};
    display_size::NTuple{2, Int} = (6, 40),
    color::Bool = false,
    kwargs...,
)
    pagerd = _create_redraw_pagerd(lines; display_size = display_size, color = color)
    pagerd.show_column_ruler = true

    for (field, value) in kwargs
        setfield!(pagerd, field, value)
    end

    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    return String(rows[1]), String(rows[2])
end

@testset "Column Ruler Key Binding and Toggle" begin
    k = TerminalPager.Keystroke(; value = "R")
    @test TerminalPager._pager_action(k) === :toggle_column_ruler

    lines = ["line $i" for i in 1:40]
    pagerd = _create_redraw_pagerd(lines)
    @test TerminalPager._get_pager_display_size(pagerd) == (9, 20)
    @test TerminalPager._view_rows(pagerd) == 9
    @test TerminalPager._frame_rows(pagerd) == 9

    # The ruler takes two rows of the view, and the screen must be repainted.
    _paint!(pagerd)
    TerminalPager._pager_key_process!(pagerd, k)
    @test pagerd.event === :toggle_column_ruler
    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.show_column_ruler
    @test TerminalPager._get_pager_display_size(pagerd) == (7, 20)
    @test TerminalPager._view_rows(pagerd) == 7
    @test TerminalPager._frame_rows(pagerd) == 9
    @test !pagerd.frame_cache.valid
    @test pagerd.redraw

    # Hiding the ruler reveals two rows, so a view at the end of the text is pulled back.
    pagerd.start_row = 34
    pagerd.event = :toggle_column_ruler
    @test TerminalPager._pager_event_process!(pagerd) != false
    @test !pagerd.show_column_ruler
    @test pagerd.start_row == 32
end

@testset "Column Ruler Rows" begin
    wide = [repeat("x", 12500) for _ in 1:3]
    ticks = "────┬────┴────┬────┴────┬────┴────┬────┴"

    # Every tenth column has a tick with its number above, and every fifth one a half tick.
    @test _column_ruler_rows(wide) == ("        10        20        30        40", ticks)

    # The ruler is the first two rows of the frame, before the text.
    pagerd = _create_redraw_pagerd(wide; display_size = (6, 40))
    pagerd.show_column_ruler = true
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test length(rows) == 5
    @test rows[3] == repeat("x", 40)

    # The ruler stops at the widest line.
    @test _column_ruler_rows([repeat("x", 25)]) ==
        ("        10        20", "────┬────┴────┬────┴────┬")

    # The columns of the line-number ruler are left blank.
    @test _column_ruler_rows([repeat("x", 25)]; show_ruler = true) ==
        ("    " * "        10        20", "    " * "────┬────┴────┬────┴────┬")
    @test _column_ruler_rows(wide; show_ruler = true) == (
        "    " * "        10        20        30",
        "    " * "────┬────┴────┬────┴────┬────┴────┬─",
    )

    # Far from the start, the whole numbers are printed above their ticks.
    @test _column_ruler_rows(wide; start_column = 12341) ==
        ("     12350     12360     12370     12380", ticks)

    # A number that does not fit is skipped, and its tick stays.
    @test _column_ruler_rows(wide; start_column = 12348) == (
        "        12360     12370     12380",
        "──┴────┬────┴────┬────┴────┬────┴────┬──",
    )

    # The frozen columns come first, and a break mark shows where the numbering jumps.
    @test _column_ruler_rows(wide; frozen_columns = 5, start_column = 12341) == (
        "          12350     12360     12370",
        "────┬" * "┆───┬────┴────┬────┴────┬────┴────┬",
    )
    @test _column_ruler_rows(wide; frozen_columns = 5, start_column = 6) ==
        ("        10        20        30        40", ticks)

    # The ruler uses the face of the line-number ruler.
    @test _column_ruler_rows([repeat("x", 12)]; color = true) == (
        "\e[0;90m" * "        10" * "\e[0m",
        "\e[0;90m" * "────┬────┴──" * "\e[0m",
    )
end

@testset "Column Ruler Shifts the Screen Rows" begin
    lines = ["line $i" for i in 1:40]
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
    pagerd.show_column_ruler = true
    screen = fill("", 10)
    _emulate!(screen, _paint!(pagerd))
    @test screen[1] == ""
    @test screen[2] == "────┬──"
    @test screen[3:9] == lines[1:7]

    # The scroll region starts below the ruler, which stays in place.
    pagerd.start_row = 2
    output = _paint!(pagerd)
    @test occursin("\e[3;9r\e[1S\e[r", output)
    @test count("\e[0K", output) == 1
    _emulate!(screen, output)
    @test screen[2] == "────┬──"
    @test screen[3:9] == lines[2:8]

    # The frozen rows stay in place as well.
    pagerd.frozen_rows = 1
    _emulate!(screen, _paint!(pagerd))
    pagerd.start_row = 3
    output = _paint!(pagerd)
    @test occursin("\e[4;9r\e[1S\e[r", output)
    _emulate!(screen, output)
    @test screen[2] == "────┬──"
    @test screen[3] == lines[1]
    @test screen[4:9] == lines[3:8]
end

@testset "Column Ruler Offsets the Mouse Rows" begin
    lines = ["line $i" for i in 1:40]

    # A click in the visual mode selects the line under the pointer.
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
    pagerd.visual_mode = true
    pagerd.mouse_row = 4
    TerminalPager._mouse_select!(pagerd)
    @test pagerd.visual_mode_line == 4

    pagerd.show_column_ruler = true
    pagerd.mouse_row = 4
    TerminalPager._mouse_select!(pagerd)
    @test pagerd.visual_mode_line == 2

    # The freeze selection puts the guides on the pointer, below the ruler.
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
    pagerd.mode = :freeze_selection
    pagerd.features = [:change_freeze, :change_frozen_columns, :change_frozen_rows]
    press(x, y) = TerminalPager._move_freeze_selection!(
        pagerd, nothing, TerminalPager.Keystroke(; value = "<mouse_press>", x = x, y = y)
    )

    press(5, 4)
    @test pagerd.freeze_selection_rows == 3
    @test pagerd.freeze_selection_columns == 4

    pagerd.show_column_ruler = true
    press(5, 4)
    @test pagerd.freeze_selection_rows == 1
    @test pagerd.freeze_selection_columns == 4

    # A press on the ruler rows is ignored.
    press(5, 2)
    @test pagerd.freeze_selection_rows == 1
    @test pagerd.freeze_selection_columns == 4
end

@testset "Column Ruler Preference and Keyword" begin
    @test TerminalPager._AVAILABLE_PREFERENCES["show_column_ruler"] === false

    text = "abcdefghijkl\nb"
    ticks = "────┬────┴──"
    out = IOBuffer()

    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, out, out)
    TerminalPager._pager!(term, text; input = TerminalPager.PagerInput(input))
    @test !occursin(ticks, String(take!(out)))

    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, out, out)
    TerminalPager._pager!(
        term, text; show_column_ruler = true, input = TerminalPager.PagerInput(input)
    )
    @test occursin(ticks, String(take!(out)))

    try
        TerminalPager.set_preference!("show_column_ruler", true)
        input = IOBuffer("q")
        term = REPL.Terminals.TTYTerminal("", input, out, out)
        TerminalPager._pager!(term, text; input = TerminalPager.PagerInput(input))
        @test occursin(ticks, String(take!(out)))
    finally
        TerminalPager.drop_preference!("show_column_ruler")
    end
end
