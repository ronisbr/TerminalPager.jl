# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Test of internal functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function _create_pagerd(str::AbstractString)
    lines = split(str, '\n')
    matches = NTuple{4, Int}[]
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
    iobuf = IOBuffer()
    buf = IOContext(iobuf, :color => get(stdout, :color, true))
    pagerd = TerminalPager.Pager(term = term,
                                 buf = buf,
                                 display_size = displaysize(term.out_stream),
                                 start_row = 1,
                                 start_col = 1,
                                 lines = lines,
                                 num_lines = length(lines))

    return pagerd
end

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
 (9, 1)   (9, 2)   (9, 3)  
"""

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
11, 1)  (11, 2)  (11, 3)  (
"""

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

@testset "Key processing" begin
    pagerd = _create_pagerd("")

    # Down
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :down)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 11
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 0
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Shift down
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :down, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 15
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 2
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 12
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    # Up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :up)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 9
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 1
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 1
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Shift up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :up, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 5
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 2
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 0
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 1
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    # Right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 11
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 11
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Alt right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right, alt = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 30
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Shift right
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :right, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 20
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 2
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 12
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    # Left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 9
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 1
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 1
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Alt left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left, alt = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 1
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 1
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 1
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Shift left
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :left, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 15
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 5
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 4
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 2
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 1
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    # End
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :end)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 30
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 0
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Home
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :home)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 1
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 1
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 0
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 1
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    # Page up
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :pageup)

    pagerd.redraw          = false
    pagerd.start_row       = 40
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 10)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 21
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 0
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 1
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    # Page down
    # ==========================================================================

    k = TerminalPager.Keystroke(value = :pagedown)

    pagerd.redraw          = false
    pagerd.start_row       = 20
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 30
    pagerd.columns_cropped = 20
    pagerd.display_size    = (10, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 29
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 10
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 20
    @test pagerd.start_col == 10
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing
end

@testset "Key bindings" begin
    pagerd = _create_pagerd("")

    TerminalPager.set_keybinding('L', :left)
    k = TerminalPager.Keystroke(value = "L")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 9
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    TerminalPager.delete_keybinding('L')

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    TerminalPager.set_keybinding(:left, :bol, shift = true)
    k = TerminalPager.Keystroke(value = :left, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 1
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing

    TerminalPager.delete_keybinding(:left, shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 10
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 10
    @test pagerd.redraw    == false
    @test pagerd.event     == nothing

    TerminalPager.reset_keybindings()

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_col       = 15
    pagerd.lines_cropped   = 20
    pagerd.columns_cropped = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_col == 5
    @test pagerd.redraw    == true
    @test pagerd.event     == nothing
end
