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
    tokens = split(str, '\n')

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
    lines_cropped, columns_cropped = TerminalPager._view(buf, tokens, (10, 9*3), 1, 1)
    result = String(take!(buf))

    @test expected == result
    @test lines_cropped == 90
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
    lines_cropped, columns_cropped = TerminalPager._view(buf, tokens, (10, 9*3), 3, 3)
    result = String(take!(buf))

    @test expected == result
    @test lines_cropped == 88
    @test columns_cropped == 51
end

@testset "Key processing" begin
    # Down
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :down, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (11, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (10, 10, false)

    # Shift down
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :down, value = "", shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (15, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 2, 20, 20)
    @test ret == (12, 10, true)

    # Up
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :up, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (9, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 1, 10, 20, 20, 20)
    @test ret == (1, 10, false)

    # Shift up
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :up, value = "", shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (5, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 2, 10, 0, 20, 20)
    @test ret == (1, 10, true)

    # Right
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :right, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 11, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 0, 20)
    @test ret == (10, 10, false)

    # Alt right
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :right, value = "", alt = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 30, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 0, 20)
    @test ret == (10, 10, false)

    # Shift right
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :right, value = "", shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 20, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 2, 20)
    @test ret == (10, 12, true)

    # Left
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :left, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 9, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 1, 20, 20, 20)
    @test ret == (10, 1, false)

    # Alt left
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :left, value = "", alt = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 1, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 1, 20, 20, 20)
    @test ret == (10, 1, false)

    # Shift left
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :left, value = "", shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 15, 20, 20, 20)
    @test ret == (10, 5, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 4, 20, 2, 20)
    @test ret == (10, 1, true)

    # End
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :end, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (30, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (10, 10, false)

    # Home
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :home, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (1, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 1, 10, 0, 20, 20)
    @test ret == (1, 10, false)

    # Page up
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :pageup, value = "")

    ret = TerminalPager._pager_keyprocess(k, 40, 10, 20, 20, 20)
    @test ret == (20, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (1, 10, true)

    # Page down
    # ==========================================================================

    k = TerminalPager.Keystroke(ktype = :pagedown, value = "")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 30, 20, 20)
    @test ret == (30, 10, true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 10, 20, 20)
    @test ret == (20, 10, true)

end
