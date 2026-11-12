## Description #############################################################################
#
# Tests for the line-number ruler.
#
############################################################################################

@testset "Hiding the Ruler Keeps the Right Edge" begin
    lines = [repeat("x", 100)]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.display_size = (10, 40)

    # At the right edge, hiding the ruler must scroll left by the full ruler width, which
    # is four columns for a one-line text.
    pagerd.show_ruler = true
    pagerd.cropped_columns = 0
    pagerd.start_column = 65
    pagerd.event = :toggle_ruler

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.show_ruler == false
    @test pagerd.start_column == 61

    # With text still cropped at the right edge, only the difference may be reclaimed.
    # Scrolling by the full ruler width cropped that text again.
    pagerd.show_ruler = true
    pagerd.cropped_columns = 2
    pagerd.start_column = 63
    pagerd.event = :toggle_ruler

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.start_column == 61

    # The shift must not push the view into the frozen columns.
    pagerd.show_ruler = true
    pagerd.frozen_columns = 8
    pagerd.cropped_columns = 0
    pagerd.start_column = 10
    pagerd.event = :toggle_ruler

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.start_column == 9
end

@testset "Ruler Ends With a Foot on the Last Frozen Row" begin
    lines = ["line $i" for i in 1:6]

    function ruler_rows(; display_size = (8, 20), kwargs...)
        pagerd = _create_redraw_pagerd(lines; display_size = display_size, color = true)
        pagerd.show_ruler = true

        for (field, value) in kwargs
            setfield!(pagerd, field, value)
        end

        TerminalPager._view!(pagerd)
        return split(String(take!(copy(pagerd.buf.io))), '\n')
    end

    # Without frozen rows, every row has a bar.
    rows = ruler_rows()
    @test all(occursin("│", row) for row in rows)
    @test !any(occursin("┴", row) for row in rows)

    # The last frozen row has the foot, and the others keep the bar.
    rows = ruler_rows(; frozen_rows = 2, start_row = 3)
    @test startswith(rows[1], "\e[0;90m 1 │\e[0m")
    @test startswith(rows[2], "\e[0;90m 2 ┴\e[0m")
    @test startswith(rows[3], "\e[0;90m 3 │\e[0m")
    @test count(row -> occursin("┴", row), rows) == 1

    # The foot follows the column ruler, and the scrollbar is not confused with the ruler.
    rows = ruler_rows(; frozen_rows = 2, start_row = 3, show_column_ruler = true)
    @test startswith(rows[4], "\e[0;90m 2 ┴\e[0m")

    rows = ruler_rows(; frozen_rows = 2, start_row = 3, show_scrollbar = true)
    @test startswith(rows[2], "\e[0;90m 2 ┴\e[0m")
    @test occursin("\e[20G", rows[2])
    @test endswith(rows[2], TerminalPager._SCROLLBAR_TRACK * "\e[0m") ||
        endswith(rows[2], TerminalPager._SCROLLBAR_THUMB * "\e[0m")

    # More frozen rows than the text or the view has put the foot on the last row shown.
    rows = ruler_rows(; frozen_rows = 10)
    @test startswith(rows[6], "\e[0;90m 6 ┴\e[0m")

    rows = ruler_rows(; frozen_rows = 10, display_size = (4, 20))
    @test startswith(rows[3], "\e[0;90m 3 ┴\e[0m")

    # Without the ruler, nothing is patched.
    pagerd = _create_redraw_pagerd(lines; display_size = (8, 20), color = true)
    pagerd.frozen_rows = 2
    TerminalPager._view!(pagerd)
    @test !occursin("┴", String(take!(copy(pagerd.buf.io))))
end
