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

    active = pagerd.display_config.visual_mode_active_line_background
    selected = pagerd.display_config.visual_mode_line_background

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
