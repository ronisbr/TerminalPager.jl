## Description #############################################################################
#
# Tests for the visual mode state.
#
############################################################################################

@testset "Visual Line Clamping" begin
    # The absolute line under the visual cursor is derived from `start_row`. Clamping it against
    # `min_row` let the cursor sit past the last line whenever the view was scrolled, and the
    # yank then indexed the layout out of bounds.
    lines = ["line $i" for i in 1:12]

    for action in ("j", "G", "\e[B")
        pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
        pagerd.features = [:visual_mode, :change_freeze]
        pagerd.visual_mode = true
        pagerd.frozen_rows = 2
        pagerd.start_row = 10
        pagerd.visual_mode_line = 8
        pagerd.cropped_lines = 0

        TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = action))

        absolute_line = pagerd.visual_mode_line + pagerd.start_row - 1
        @test 1 <= absolute_line <= pagerd.num_lines

        # The yank must not index the layout out of bounds.
        pagerd.event = :yank
        text, count = TerminalPager._assemble_yank_text(pagerd.text_layout, [absolute_line])
        @test count == 1
    end
end

@testset "Visual Mode Disabled State" begin
    # When every line is frozen, the movement handling disables visual mode. The flag must be
    # written back, otherwise `_view!` keeps drawing the overlay and `:yank` still fires.
    pagerd = _create_redraw_pagerd(["a", "b"]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.frozen_rows = 5

    TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = "j"))
    @test pagerd.visual_mode == false

    # A normal session must keep visual mode enabled.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:20]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.cropped_lines = 12

    TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = "j"))
    @test pagerd.visual_mode == true
end

@testset "Visual Mode With a Single Selectable Line" begin
    # With exactly one selectable line, the visual mode must stay enabled so that the line
    # can be yanked. The forced disable used to fire one line too early.
    pagerd = _create_redraw_pagerd(["only line"]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true

    TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = "j"))

    @test pagerd.visual_mode == true
    @test pagerd.visual_mode_line == 1

    # The forced disable must clear stale selections, exactly as `:toggle_visual_mode` does.
    pagerd = _create_redraw_pagerd(["a", "b"]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    push!(pagerd.visual_mode_selected_lines, 1)
    pagerd.frozen_rows = 5

    TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = "j"))

    @test pagerd.visual_mode == false
    @test isempty(pagerd.visual_mode_selected_lines)
end

@testset "Visual Line Marking" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:8]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.visual_mode_line = 3

    # Marking a line must request a redraw, otherwise there is no feedback until the user
    # presses another key.
    pagerd.redraw = false
    pagerd.event = :select_visual_mode_line
    TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_selected_lines == [3]
    @test pagerd.redraw == true

    # Marking it again deselects it.
    pagerd.redraw = false
    pagerd.event = :select_visual_mode_line
    TerminalPager._pager_event_process!(pagerd)
    @test isempty(pagerd.visual_mode_selected_lines)
    @test pagerd.redraw == true

    # Outside visual mode nothing happens.
    pagerd.visual_mode = false
    pagerd.redraw = false
    pagerd.event = :select_visual_mode_line
    TerminalPager._pager_event_process!(pagerd)
    @test isempty(pagerd.visual_mode_selected_lines)
    @test pagerd.redraw == false
end

@testset "Active Visual Line Highlight" begin
    # The active line is listed first, and `StringManipulation` keeps the first background it
    # sees for a line. Hence, marking the active line must not hide its own highlight.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5]; display_size = (8, 20))
    pagerd.buf = IOContext(IOBuffer(), :color => true)
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.visual_mode_line = 2
    push!(pagerd.visual_mode_selected_lines, 2)

    TerminalPager._view!(pagerd)
    frame = split(String(take!(pagerd.buf.io)), '\n')

    active = pagerd.display_config.visual_active_line
    selected = pagerd.display_config.visual_line

    @test occursin("\e[$(active)m", frame[2])
    @test !occursin("\e[$(selected)m", frame[2])
end

@testset "Sanitized Viewport Is Written Back" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5]; display_size = (10, 20))
    pagerd.start_row = 0
    pagerd.start_column = -3

    TerminalPager._view!(pagerd)

    @test pagerd.start_row == 1
    @test pagerd.start_column == 1
end

@testset "Visual Mode Backward Moves Scroll the Overflow" begin
    # The view has nine rows. A backward move that crosses the top row must scroll the view
    # by the overflow, mirroring the forward moves.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:40]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.start_row = 10
    pagerd.cropped_lines = 22
    pagerd.visual_mode_line = 3

    fastup = TerminalPager.Keystroke(; value = "<up>", shift = true)
    TerminalPager._pager_key_process!(pagerd, fastup)
    @test pagerd.visual_mode_line == 1
    @test pagerd.start_row == 7

    halfpageup = TerminalPager.Keystroke(; value = "u")
    TerminalPager._pager_key_process!(pagerd, halfpageup)
    @test pagerd.visual_mode_line == 1
    @test pagerd.start_row == 3

    # The view never scrolls above the first line.
    TerminalPager._pager_key_process!(pagerd, halfpageup)
    @test pagerd.visual_mode_line == 1
    @test pagerd.start_row == 1

    # The forward twin scrolls by the overflow past the last row.
    pagerd.visual_mode_line = 7
    pagerd.cropped_lines = 31
    fastdown = TerminalPager.Keystroke(; value = "<down>", shift = true)
    TerminalPager._pager_key_process!(pagerd, fastdown)
    @test pagerd.visual_mode_line == 9
    @test pagerd.start_row == 4

    # Page moves pin the cursor to the edge instead.
    pageup = TerminalPager.Keystroke(; value = "<pageup>")
    pagerd.visual_mode_line = 5
    TerminalPager._pager_key_process!(pagerd, pageup)
    @test pagerd.visual_mode_line == 1
    @test pagerd.start_row == 1
end

@testset "Mouse Wheel and Click" begin
    lines = ["line $i" for i in 1:40]
    wheel_down = TerminalPager.Keystroke(; value = "<wheel_down>", x = 1, y = 1)
    wheel_up = TerminalPager.Keystroke(; value = "<wheel_up>", x = 1, y = 1)
    shift_wheel_down = TerminalPager.Keystroke(; value = "<wheel_down>", shift = true)

    # The wheel scrolls three lines and is coalesced like the other vertical moves.
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
    pagerd.cropped_lines = 31
    pagerd.cropped_columns = 20
    @test TerminalPager._pager_key_process!(pagerd, wheel_down) === :wheel_down
    @test pagerd.start_row == 4
    @test TerminalPager._navigation_group(:wheel_down) === :vertical_forward
    @test TerminalPager._navigation_group(:wheel_up) === :vertical_backward
    pagerd.cropped_lines = 28
    TerminalPager._pager_key_process!(pagerd, wheel_up)
    @test pagerd.start_row == 1

    # SHIFT and the wheel scroll horizontally.
    @test TerminalPager._pager_key_process!(pagerd, shift_wheel_down) === :fastright
    @test pagerd.start_column == 11

    # In the visual mode, the wheel scrolls the view and keeps the cursor row.
    pagerd.start_column = 1
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.visual_mode_line = 4
    pagerd.cropped_lines = 31
    TerminalPager._pager_key_process!(pagerd, wheel_down)
    @test pagerd.start_row == 4
    @test pagerd.visual_mode_line == 4

    # A click moves the visual line to the clicked row, and a second click marks it. The
    # frozen rows are not selectable.
    pagerd.frozen_rows = 2
    pagerd.start_row = 3
    pagerd.visual_mode_line = 2
    click = TerminalPager.Keystroke(; value = "<mouse_press>", x = 5, y = 6)
    @test TerminalPager._pager_key_process!(pagerd, click) === :mouse_select
    @test pagerd.event === :mouse_select
    @test (pagerd.mouse_column, pagerd.mouse_row) == (5, 6)
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_line == 4
    @test isempty(pagerd.visual_mode_selected_lines)

    pagerd.event = :mouse_select
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_selected_lines == [6]

    pagerd.mouse_row = 1
    pagerd.event = :mouse_select
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_line == 4

    # Outside the visual mode, and without the feature, a click does nothing.
    pagerd.visual_mode = false
    pagerd.mouse_row = 5
    pagerd.event = :mouse_select
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_line == 4
    pagerd.features = Symbol[]
    @test TerminalPager._pager_key_process!(pagerd, click) === :mouse_select
    @test isnothing(pagerd.event)
end
