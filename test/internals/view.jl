# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Test of the function `_view`.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

@testset "Views" begin
    # Create the pager structure.
    a   = [(i, j) for i = 1:99, j = 1:9]
    str = sprint(show, MIME"text/plain"(), a)
    pagerd = _create_pagerd(str)

    # Initial view
    # ==========================================================================

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
    pagerd.display_size = (11, 9*3)
    TerminalPager._view!(pagerd)
    result = String(take!(pagerd.buf.io))

    @test expected == result
    @test pagerd.lines_cropped == 90
    @test pagerd.columns_cropped == 52

    # Moving the view
    # ==========================================================================

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
    pagerd.display_size = (11, 9*3)
    pagerd.start_row = 3
    pagerd.start_col = 3
    TerminalPager._view!(pagerd)
    result = String(take!(pagerd.buf.io))

    @test expected == result
    @test pagerd.lines_cropped == 88
    @test pagerd.columns_cropped == 51
end

