## Description #############################################################################
#
# Test of key bindings.
#
############################################################################################

@testset "Key Bindings" begin
    pagerd = _create_pagerd("")

    TerminalPager.set_keybinding("L", :left)
    k = TerminalPager.Keystroke(; value = "L")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_column == 9
    @test pagerd.redraw == true
    @test pagerd.event === nothing

    TerminalPager.delete_keybinding("L")

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw == false
    @test pagerd.event === nothing

    TerminalPager.set_keybinding("<left>", :bol; shift = true)
    k = TerminalPager.Keystroke(; value = "<left>", shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_column == 1
    @test pagerd.redraw == true
    @test pagerd.event === nothing

    TerminalPager.delete_keybinding("<left>"; shift = true)

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 10
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_column == 10
    @test pagerd.redraw == false
    @test pagerd.event === nothing

    TerminalPager.reset_keybindings()

    pagerd.redraw          = false
    pagerd.start_row       = 10
    pagerd.start_column    = 15
    pagerd.cropped_lines   = 20
    pagerd.cropped_columns = 20
    pagerd.display_size    = (20, 20)

    TerminalPager._pager_key_process!(pagerd, k)

    @test pagerd.start_row == 10
    @test pagerd.start_column == 5
    @test pagerd.redraw == true
    @test pagerd.event === nothing
end

@testset "Mode-Dependent Key Bindings" begin
    # `_apply_mode_keybindings!` is shared by `__init__` and `reset_keybindings`. It used to
    # be duplicated in `__init__`, where it referred to a non-existing dictionary, making
    # `using TerminalPager` fail whenever the `pager_mode` preference was `"vi"`.
    default_getter = _ -> "default"
    vi_getter = _ -> "vi"

    try
        TerminalPager.reset_keybindings()
        TerminalPager._apply_mode_keybindings!(default_getter)

        @test TerminalPager._KEYBINDINGS[("<eot>", false, false, false)] == :quit_eot
        @test !haskey(TerminalPager._KEYBINDINGS, ("<shiftin>", false, false, false))

        # This is exactly what `__init__` does. It must not throw.
        TerminalPager._apply_mode_keybindings!(vi_getter)

        @test TerminalPager._KEYBINDINGS[("<eot>", false, false, false)] == :halfpagedown
        @test TerminalPager._KEYBINDINGS[("<shiftin>", false, false, false)] == :halfpageup

        # Switching back to the default mode must remove the vi-only CTRL-U binding, which
        # used to survive the switch.
        TerminalPager._apply_mode_keybindings!(default_getter)

        @test TerminalPager._KEYBINDINGS[("<eot>", false, false, false)] == :quit_eot
        @test !haskey(TerminalPager._KEYBINDINGS, ("<shiftin>", false, false, false))

        # A user reassignment of the key must survive the switch, however.
        TerminalPager._apply_mode_keybindings!(vi_getter)
        TerminalPager.set_keybinding("<shiftin>", :quit)
        TerminalPager._apply_mode_keybindings!(default_getter)

        @test TerminalPager._KEYBINDINGS[("<shiftin>", false, false, false)] == :quit
    finally
        TerminalPager.reset_keybindings()
    end
end

@testset "CTRL-C Cancels the Search" begin
    # CTRL-C used to be a silent no-op inside the pager, because the raw mode disables the
    # interrupt signal and the keystroke was unbound.
    k = TerminalPager._read_keystroke!(TerminalPager.PagerInput(IOBuffer("\x03")))
    @test (k.value, k.ctrl) == ("c", true)
    @test TerminalPager._pager_action(k) === :quit_search
    @test TerminalPager._DEFAULT_KEYBINDINGS[("c", false, true, false)] === :quit_search
end
