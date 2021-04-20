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

    k = TerminalPager.Keystroke(value = :down)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (11, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (10, 10, false, nothing)

    # Shift down
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :down, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (15, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 2, 20, 20)
    @test ret == (12, 10, true, nothing)

    # Up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :up)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (9, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 1, 10, 20, 20, 20)
    @test ret == (1, 10, false, nothing)

    # Shift up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :up, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (5, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 2, 10, 0, 20, 20)
    @test ret == (1, 10, true, nothing)

    # Right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 11, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 0, 20)
    @test ret == (10, 10, false, nothing)

    # Alt right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right, alt = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 30, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 0, 20)
    @test ret == (10, 10, false, nothing)

    # Shift right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 20, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 2, 20)
    @test ret == (10, 12, true, nothing)

    # Left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 9, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 1, 20, 20, 20)
    @test ret == (10, 1, false, nothing)

    # Alt left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left, alt = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 1, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 1, 20, 20, 20)
    @test ret == (10, 1, false, nothing)

    # Shift left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 15, 20, 20, 20)
    @test ret == (10, 5, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 4, 20, 2, 20)
    @test ret == (10, 1, true, nothing)

    # End
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :end)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (30, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (10, 10, false, nothing)

    # Home
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :home)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (1, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 1, 10, 0, 20, 20)
    @test ret == (1, 10, false, nothing)

    # Page up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :pageup)

    ret = TerminalPager._pager_keyprocess(k, 40, 10, 20, 20, 20)
    @test ret == (20, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 0, 20, 20)
    @test ret == (1, 10, true, nothing)

    # Page down
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :pagedown)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 30, 20, 20)
    @test ret == (30, 10, true, nothing)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 10, 20, 20)
    @test ret == (20, 10, true, nothing)

end

@testset "Key bindings" begin
    TerminalPager.set_keybinding('L', :left)
    k = TerminalPager.Keystroke(value = "L")

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 9, true, nothing)

    TerminalPager.delete_keybinding('L')

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 10, false, nothing)

    TerminalPager.set_keybinding(:left, :bol, shift = true)
    k = TerminalPager.Keystroke(value = :left, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 1, true, nothing)

    TerminalPager.delete_keybinding(:left, shift = true)

    ret = TerminalPager._pager_keyprocess(k, 10, 10, 20, 20, 20)
    @test ret == (10, 10, false, nothing)

    TerminalPager.reset_keybindings()

    ret = TerminalPager._pager_keyprocess(k, 10, 15, 20, 20, 20)
    @test ret == (10, 5, true, nothing)
end
