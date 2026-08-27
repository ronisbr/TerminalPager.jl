## Description #############################################################################
#
# Test of the function `_view`.
#
############################################################################################

@testset "Views" begin
    # Create the pager structure.
    a = [(i, j) for i in 1:99, j in 1:9]
    str = sprint(show, MIME"text/plain"(), a)
    pagerd = _create_pagerd(str)

    # == Initial View ======================================================================

    expected = """
99×9 Matrix{Tuple{Int64, In
 (1, 1)   (1, 2)   (1, 3)  
 (2, 1)   (2, 2)   (2, 3)  
 (3, 1)   (3, 2)   (3, 3)  
 (4, 1)   (4, 2)   (4, 3)  
 (5, 1)   (5, 2)   (5, 3)  
 (6, 1)   (6, 2)   (6, 3)  
 (7, 1)   (7, 2)   (7, 3)  
 (8, 1)   (8, 2)   (8, 3)  
 (9, 1)   (9, 2)   (9, 3)  """

    buf = IOBuffer()
    pagerd.display_size = (11, 9 * 3)
    TerminalPager._view!(pagerd)
    result = String(take!(pagerd.buf.io))

    @test expected == result
    @test pagerd.cropped_lines == 90
    @test pagerd.cropped_columns == 52

    # == Moving the View ===================================================================

    expected = """
2, 1)   (2, 2)   (2, 3)   (
3, 1)   (3, 2)   (3, 3)   (
4, 1)   (4, 2)   (4, 3)   (
5, 1)   (5, 2)   (5, 3)   (
6, 1)   (6, 2)   (6, 3)   (
7, 1)   (7, 2)   (7, 3)   (
8, 1)   (8, 2)   (8, 3)   (
9, 1)   (9, 2)   (9, 3)   (
10, 1)  (10, 2)  (10, 3)  (
11, 1)  (11, 2)  (11, 3)  ("""

    buf = IOBuffer()
    pagerd.display_size = (11, 9 * 3)
    pagerd.start_row = 3
    pagerd.start_column = 3
    TerminalPager._view!(pagerd)
    result = String(take!(pagerd.buf.io))

    @test expected == result
    @test pagerd.cropped_lines == 88
    @test pagerd.cropped_columns == 51
end

@testset "Resize Keeps the Screen Full" begin
    # The text has 20 lines and is 32 columns wide. The view shows the end of it.
    lines = ["x"^30 * string(i) for i in 1:20]
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))
    pagerd.start_row = 12
    pagerd.start_column = 13
    @test TerminalPager._text_width(pagerd) == 32

    # Growing the terminal used to leave blank rows and columns after the end of the text.
    pagerd.display_size = (15, 25)
    TerminalPager._clamp_viewport!(pagerd)
    @test pagerd.start_row == 7
    @test pagerd.start_column == 8

    # The view never moves into the frozen region.
    pagerd.frozen_rows = 2
    pagerd.frozen_columns = 3
    pagerd.start_row = 3
    pagerd.start_column = 4
    pagerd.display_size = (40, 80)
    TerminalPager._clamp_viewport!(pagerd)
    @test pagerd.start_row == 3
    @test pagerd.start_column == 4

    # The ruler occupies columns, so fewer text columns fit.
    pagerd.frozen_rows = 0
    pagerd.frozen_columns = 0
    pagerd.show_ruler = true
    pagerd.start_column = 13
    pagerd.display_size = (10, 25)
    TerminalPager._clamp_viewport!(pagerd)
    @test pagerd.start_column == 8 + TerminalPager._ruler_width(20)

    # A degenerate display leaves the viewport alone.
    pagerd.start_row = 12
    pagerd.display_size = (1, 0)
    TerminalPager._clamp_viewport!(pagerd)
    @test pagerd.start_row == 12

    # The clamp is applied when the display size changes. The sink reports the default size.
    pagerd.display_size = (10, 20)
    pagerd.redraw = false
    TerminalPager._update_display_size!(pagerd)
    @test pagerd.display_size == displaysize(pagerd.term.out_stream)
    @test pagerd.start_row == max(1, 20 - (pagerd.display_size[1] - 1) + 1)
    @test pagerd.redraw
end
