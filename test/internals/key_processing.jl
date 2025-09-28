## Description #############################################################################
#
# Test of the function `_pager_key_processing`.
#
############################################################################################

@testset "Key processing" begin
    pagerd = _create_pagerd("")

    # == Down ==============================================================================

    k = TerminalPager.Keystroke(value = "<down>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 11
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    k = TerminalPager.Keystroke(value = "<enter>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 11
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Shift Down ========================================================================

    k = TerminalPager.Keystroke(value = "<down>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 15
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 2
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 12
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Up ================================================================================

    k = TerminalPager.Keystroke(value = "<up>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 9
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 1
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Shift Up ==========================================================================

    k = TerminalPager.Keystroke(value = "<up>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 5
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 2
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Right =============================================================================

    k = TerminalPager.Keystroke(value = "<right>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 11
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Right =============================================================================

    k = TerminalPager.Keystroke(value = "<right>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 11
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Alt Right =========================================================================

    k = TerminalPager.Keystroke(value = "<right>", alt = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 30
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 0
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Shift Right =======================================================================

    k = TerminalPager.Keystroke(value = "<right>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 20
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 2
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 12
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Left ==============================================================================

    k = TerminalPager.Keystroke(value = "<left>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 9
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 1
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Alt Left ==========================================================================

    k = TerminalPager.Keystroke(value = "<left>", alt = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 1
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Shift Left ========================================================================

    k = TerminalPager.Keystroke(value = "<left>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 15
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 5
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 4
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 2
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == End ===============================================================================

    k = TerminalPager.Keystroke(value = "<end>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 30
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Home ==============================================================================

    k = TerminalPager.Keystroke(value = "<home>")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 1
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    # == Half Page Up ======================================================================

    k = TerminalPager.Keystroke(value = "u")

    pagerd.redraw          = false
    pagerd.start_row       = 40
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 10)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 31
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Half Page Down ====================================================================

    k = TerminalPager.Keystroke(value = "d")

    pagerd.redraw          = false
    pagerd.start_row       = 20
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 30
    pagerd.cropped_columns = 20
    pagerd.display_size    = (10, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 24
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 10
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 19
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Page Up ===========================================================================

    k = TerminalPager.Keystroke(value = "<pageup>")

    pagerd.redraw          = false
    pagerd.start_row       = 40
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 10)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 21
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 0
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 1
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    # == Page Down =========================================================================

    k = TerminalPager.Keystroke(value = "<pagedown>")

    pagerd.redraw          = false
    pagerd.start_row       = 20
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 30
    pagerd.cropped_columns = 20
    pagerd.display_size    = (10, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 29
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 10
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 20
    @test pagerd.start_column == 10
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing
end
