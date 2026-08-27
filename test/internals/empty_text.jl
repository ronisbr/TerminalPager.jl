## Description #############################################################################
#
# Tests for pager sessions without any line.
#
############################################################################################

@testset "Ruler Width" begin
    # This must match how `StringManipulation.textview` sizes the ruler.
    @test TerminalPager._ruler_width(1) == 4
    @test TerminalPager._ruler_width(9) == 4
    @test TerminalPager._ruler_width(10) == 5
    @test TerminalPager._ruler_width(99) == 5
    @test TerminalPager._ruler_width(100) == 6

    # `floor(Int, log10(abs(0)))` threw an `InexactError`.
    @test TerminalPager._ruler_width(0) == 4
end

@testset "Empty Text" begin
    pagerd = _create_modal_pagerd(String[], "")
    pagerd.display_size = (10, 40)

    @test pagerd.num_lines == 0

    # `round(Int, 100 * (1 - 0 / 0))` threw an `InexactError` because `0 / 0` is `NaN`.
    TerminalPager._redraw_status_bar!(pagerd)
    output = String(take!(pagerd.term.out_stream))
    @test occursin("All", output)

    # Toggling the ruler used to compute the ruler width with `log10`.
    pagerd.show_ruler = true
    pagerd.event = :toggle_ruler
    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.show_ruler == false
    @test pagerd.start_column >= 1

    # Moving the view to a match on an empty text must be a no-op.
    pagerd.show_ruler = true
    @test isnothing(TerminalPager._move_view_to_match!(pagerd))

    # Rendering must also work.
    TerminalPager._view!(pagerd)
    TerminalPager._redraw!(pagerd)
end

@testset "Degenerate Display Sizes" begin
    # With one terminal row, only the command line fits. Rendering must be skipped:
    # passing a nonpositive maximum number of lines to `textview` means unbounded, which
    # would render the whole document into the frame buffer.
    pagerd = _create_modal_pagerd(["line $i" for i in 1:5], "")
    pagerd.display_size = (1, 40)

    TerminalPager._view!(pagerd)

    @test pagerd.buf.io.size == 0
    @test pagerd.cropped_lines == 0
    @test pagerd.cropped_columns == 0

    TerminalPager._redraw!(pagerd)

    @test pagerd.redraw == false
    @test pagerd.frame_cache.num_rows == 0

    # The frame row scanner must never report rows for a screen that cannot show any.
    frame_cache = pagerd.frame_cache
    @test TerminalPager._scan_frame_rows!(frame_cache, UInt8['a', '\n', 'b'], 3, 0) == 0
end
