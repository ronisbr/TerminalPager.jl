## Description #############################################################################
#
# Tests for pager sessions without any line.
#
############################################################################################

@testset "Ruler Width" begin
    # This must match how `_textview` sizes the ruler.
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
    # a negative maximum number of rows means unbounded for the renderer, which
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

@testset "Text Ending With a Newline" begin
    # A text that ends with a newline has no line after it.
    drop = TerminalPager._drop_trailing_empty_line!
    @test drop(split("alpha\nbeta\n", '\n')) == ["alpha", "beta"]
    @test drop(split("alpha\nbeta", '\n')) == ["alpha", "beta"]
    @test drop(split("alpha\n\n", '\n')) == ["alpha", ""]
    @test drop(split("\n", '\n')) == [""]
    @test drop(split("", '\n')) == [""]

    # The session shows and counts only the lines of the text.
    for (text, num_lines) in (("alpha\nbeta\n", 2), ("alpha\nbeta", 2), ("alpha\n\n", 2))
        input = TypedInput("=q")
        output = IOContext(IOBuffer(), :displaysize => (10, 60), :color => false)
        term = REPL.Terminals.TTYTerminal("", input, output, output)
        TerminalPager._pager!(
            term,
            text;
            input = TerminalPager.PagerInput(input),
            show_ruler = true,
            use_alternate_screen_buffer = false,
        )

        written = String(take!(output.io))
        @test occursin("Lines 1-$num_lines of $num_lines", written)
        @test !occursin(" $(num_lines + 1) │", written)
    end

    # The session started with the options also drops the line.
    layouts = Any[]
    options = TerminalPager._session_options((;
        _layout_factory = lines -> (push!(layouts, collect(lines)); nothing),
        _display_config_loader = () -> nothing,
        _input_factory = stream -> nothing,
        _terminal_factory = () -> nothing,
        _raw_runner = (f, terminal) -> nothing,
    ))
    TerminalPager._pager("one\ntwo\n", options)
    @test layouts == [["one", "two"]]
end
