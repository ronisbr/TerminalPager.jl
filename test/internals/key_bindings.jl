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

@testset "Key Binding Encoding" begin
    for kb in (
        ("<left>", true, false, false),
        ("x", false, true, true),
        ("+", true, false, false),
        (" ", false, false, false),
        ("alt+", false, false, false),
        ("<F1>", true, true, true),
    )
        @test TerminalPager._decode_binding(TerminalPager._encode_binding(kb)) == kb
    end

    @test TerminalPager._encode_binding(("<left>", true, false, false)) == "alt+<left>"
    @test TerminalPager._encode_binding(("x", false, true, true)) == "ctrl+shift+x"
    @test TerminalPager._encode_binding(("+", true, false, false)) == "alt++"
end

@testset "Persistent Key Bindings" begin
    try
        TerminalPager.reset_keybindings(; persist = true)
        @test isempty(TerminalPager._keybinding_preferences())

        # A binding set without `persist` is not stored.
        TerminalPager.set_keybinding("w", :quit)
        @test isempty(TerminalPager._keybinding_preferences())

        TerminalPager.set_keybinding("x", :quit; persist = true)
        TerminalPager.delete_keybinding("q"; persist = true)
        TerminalPager.set_keybinding("<left>", :bol; alt = true, shift = true, persist = true)

        stored = TerminalPager._keybinding_preferences()
        @test stored["x"] == "quit"
        @test stored["q"] == "delete"
        @test stored["alt+shift+<left>"] == "bol"

        # A non-persistent reset keeps the persisted bindings, which are part of the session
        # defaults, and drops the others.
        TerminalPager.reset_keybindings()
        @test TerminalPager._KEYBINDINGS[("x", false, false, false)] === :quit
        @test !haskey(TerminalPager._KEYBINDINGS, ("q", false, false, false))
        @test !haskey(TerminalPager._KEYBINDINGS, ("w", false, false, false))
        @test TerminalPager._KEYBINDINGS[("<left>", true, false, true)] === :bol

        # A persistent reset restores the defaults and empties the preference.
        TerminalPager.reset_keybindings(; persist = true)
        @test !haskey(TerminalPager._KEYBINDINGS, ("x", false, false, false))
        @test TerminalPager._KEYBINDINGS[("q", false, false, false)] === :quit
        @test isempty(TerminalPager._keybinding_preferences())

        # `drop_all_preferences!` drops the persisted bindings too.
        TerminalPager.set_keybinding("x", :quit; persist = true)
        TerminalPager.drop_all_preferences!()
        @test isempty(TerminalPager._keybinding_preferences())
        @test !haskey(TerminalPager._KEYBINDINGS, ("x", false, false, false))
    finally
        TerminalPager.reset_keybindings(; persist = true)
    end
end

@testset "Unknown Stored Action" begin
    try
        TerminalPager.Preferences.set_preferences!(
            TerminalPager,
            "keybindings" => Dict("z" => "nope", "y" => "quit", "w" => 1);
            force = true,
        )

        @test_logs (:warn, r"unknown actions.*w => 1, z => nope") TerminalPager._load_keybindings!()
        @test TerminalPager._KEYBINDINGS[("y", false, false, false)] === :quit
        @test !haskey(TerminalPager._KEYBINDINGS, ("z", false, false, false))
        @test !haskey(TerminalPager._KEYBINDINGS, ("w", false, false, false))

        # A preference that is not a table is ignored with a warning.
        TerminalPager.Preferences.set_preferences!(
            TerminalPager, "keybindings" => "quit"; force = true
        )
        @test_logs (:warn, r"must be a table") TerminalPager._load_keybindings!()
    finally
        TerminalPager.reset_keybindings(; persist = true)
    end

    @test_throws ArgumentError TerminalPager.set_keybinding("x", :nope)
    @test !haskey(TerminalPager._KEYBINDINGS, ("x", false, false, false))
end

@testset "Action List" begin
    @test Set(values(TerminalPager._DEFAULT_KEYBINDINGS)) ⊆ Set(TerminalPager._ACTIONS)
    @test keys(TerminalPager._EVENT_FEATURES) ⊆ Set(TerminalPager._ACTIONS)
    @test allunique(TerminalPager._ACTIONS)

    doc = string(@doc TerminalPager.set_keybinding)

    for action in TerminalPager._ACTIONS
        @test occursin(":$action", doc)
    end
end
