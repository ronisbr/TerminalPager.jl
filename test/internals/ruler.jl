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
