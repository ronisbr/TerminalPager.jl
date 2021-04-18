# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Test of internal functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

@testset "Views" begin
    a   = [(i, j) for i = 1:99, j = 1:9]
    str = sprint(show, MIME"text/plain"(), a)

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
 (9, 1)   (9, 2)   (9, 3)  
"""

    buf = IOBuffer()
    lines_cropped, columns_cropped = Less._view(buf, str, (10, 9*3), 1, 1)
    result = String(take!(buf))

    @test expected == result
    @test lines_cropped == 89
    @test columns_cropped == 52

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
11, 1)  (11, 2)  (11, 3)  (
"""

    buf = IOBuffer()
    lines_cropped, columns_cropped = Less._view(buf, str, (10, 9*3), 3, 3)
    result = String(take!(buf))

    @test expected == result
    @test lines_cropped == 87
    @test columns_cropped == 51
end
