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

"""
    _frame_rows(pagerd::TerminalPager.Pager) -> Vector{String}

Render the view of `pagerd` and return its rows.

# Arguments

- `pagerd::TerminalPager.Pager`: Pager state to render.
"""
function _frame_rows(pagerd::TerminalPager.Pager)
    TerminalPager._view!(pagerd)
    return split(String(take!(copy(pagerd.buf.io))), '\n')
end

@testset "Scrollbar" begin
    lines = ["line $i" for i in 1:40]
    pagerd = _create_redraw_pagerd(lines; display_size = (10, 20))

    # Without the scrollbar, the frame is the plain view.
    @test TerminalPager._get_pager_display_size(pagerd) == (9, 20)
    @test !any(occursin("\e[20G", row) for row in _frame_rows(pagerd))

    # The scrollbar takes the last column, and every row of the view ends with it. The nine
    # rows show nine of forty lines, so the thumb is two rows long and starts at the top.
    pagerd.show_scrollbar = true
    @test TerminalPager._get_pager_display_size(pagerd) == (9, 19)
    @test TerminalPager._scrollbar_thumb(pagerd, 9) == (1, 2)
    rows = _frame_rows(pagerd)
    @test length(rows) == 9
    @test all(occursin("\e[20G", row) for row in rows)
    @test count(endswith(row, TerminalPager._SCROLLBAR_THUMB) for row in rows) == 2
    @test endswith(rows[1], TerminalPager._SCROLLBAR_THUMB)
    @test endswith(rows[9], TerminalPager._SCROLLBAR_TRACK)
    @test startswith(rows[1], "line 1\e[")

    # The thumb follows the position and reaches the bottom at the end of the text.
    pagerd.start_row = 32
    @test TerminalPager._scrollbar_thumb(pagerd, 9) == (8, 9)
    rows = _frame_rows(pagerd)
    @test endswith(rows[9], TerminalPager._SCROLLBAR_THUMB)
    @test endswith(rows[1], TerminalPager._SCROLLBAR_TRACK)

    pagerd.start_row = 16
    thumb_first, thumb_last = TerminalPager._scrollbar_thumb(pagerd, 9)
    @test 1 < thumb_first < 8
    @test thumb_last == thumb_first + 1

    # The frozen rows are not scrollable.
    pagerd.frozen_rows = 2
    pagerd.start_row = 3
    @test TerminalPager._scrollbar_thumb(pagerd, 9) == (1, 2)
    pagerd.frozen_rows = 0
    pagerd.start_row = 1

    # A text shorter than the view fills the thumb, and the rows after the text carry only
    # the scrollbar, so that it spans the whole view.
    pagerd = _create_redraw_pagerd(["a", "b", "c"]; display_size = (10, 20), color = true)
    pagerd.show_scrollbar = true
    @test TerminalPager._scrollbar_thumb(pagerd, 9) == (1, 9)
    rows = _frame_rows(pagerd)
    @test length(rows) == 9
    thumb = pagerd.display_config.scrollbar_thumb * TerminalPager._SCROLLBAR_THUMB * "\e[0m"
    @test all(endswith(row, thumb) for row in rows)
    @test rows[4] == "\e[20G" * thumb

    # Without color, the scrollbar has no decoration.
    pagerd = _create_redraw_pagerd(["a"]; display_size = (10, 20), color = false)
    pagerd.show_scrollbar = true
    @test _frame_rows(pagerd)[2] == "\e[20G" * TerminalPager._SCROLLBAR_THUMB

    # The text is cropped one column earlier, and the crop counter says so.
    pagerd = _create_redraw_pagerd(["x"^25]; display_size = (10, 20))
    TerminalPager._view!(pagerd)
    @test pagerd.cropped_columns == 5
    pagerd.show_scrollbar = true
    TerminalPager._view!(pagerd)
    @test pagerd.cropped_columns == 6

    # The action toggles the scrollbar, and hiding it reclaims the column when the text is
    # scrolled to its end.
    pagerd.features = Symbol[]
    k = TerminalPager.Keystroke(; value = "s")
    @test TerminalPager._pager_key_process!(pagerd, k) === :toggle_scrollbar
    @test pagerd.event === :toggle_scrollbar
    @test TerminalPager._pager_event_process!(pagerd)
    @test !pagerd.show_scrollbar
    pagerd.event = :toggle_scrollbar
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.show_scrollbar
    pagerd.start_column = 7
    pagerd.cropped_columns = 0
    pagerd.event = :toggle_scrollbar
    @test TerminalPager._pager_event_process!(pagerd)
    @test !pagerd.show_scrollbar
    @test pagerd.start_column == 6
end
