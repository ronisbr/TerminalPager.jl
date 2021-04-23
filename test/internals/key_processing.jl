# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Test of the function `_pager_key_processing`.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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

