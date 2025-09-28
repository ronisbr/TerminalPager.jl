## Description #############################################################################
#
# Test of key bindings.
#
############################################################################################

@testset "Key bindings" begin
    pagerd = _create_pagerd("")

    TerminalPager.set_keybinding("L", :left)
    k = TerminalPager.Keystroke(value = "L")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 9
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    TerminalPager.delete_keybinding("L")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    TerminalPager.set_keybinding("<left>", :bol, shift = true)
    k = TerminalPager.Keystroke(value = "<left>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing

    TerminalPager.delete_keybinding("<left>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw       == false
    @test pagerd.event        === nothing

    TerminalPager.reset_keybindings()

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 15
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20,20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row    == 10
    @test pagerd.start_column == 5
    @test pagerd.redraw       == true
    @test pagerd.event        === nothing
end
