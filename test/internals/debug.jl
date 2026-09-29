## Description #############################################################################
#
# Tests for the key input debugging tool.
#
############################################################################################

@testset "Debug Keycode Terminal Modes" begin
    # The tool used to read the keys without the modes the pager enables, so it showed the
    # sequences of the normal cursor key mode and no mouse event at all.
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", IOBuffer("\eOAq"), output, output)
    raw_transitions = Bool[]
    raw_runner = (f, t) -> TerminalPager._with_raw_mode(
        f, t; raw_function = (_, enabled) -> push!(raw_transitions, enabled)
    )

    function debug_keycode(term)
        return TerminalPager.debug_keycode(;
            _terminal_factory = () -> term,
            _raw_runner = raw_runner,
        )
    end

    @test isnothing(debug_keycode(term))
    @test raw_transitions == [true, false]

    text = String(take!(output))
    mouse = TerminalPager._get_preference("mouse")::Bool

    # Each line tells the arguments of `set_keybinding` and the bytes of the keystroke,
    # which the keystroke itself does not keep.
    no_modifiers = "alt = false, ctrl = false, shift = false"
    @test occursin("value = \"<up>\", $no_modifiers, bytes = [27, 79, 65]\r\n", text)
    @test occursin("value = \"q\", $no_modifiers, bytes = [113]", text)
    @test occursin(TerminalPager._CURSOR_KEYS_ON, text)
    @test endswith(text, TerminalPager._CURSOR_KEYS_OFF)
    @test occursin(TerminalPager._MOUSE_ON, text) == mouse
    @test occursin(TerminalPager._MOUSE_OFF, text) == mouse

    # The modes are enabled before the first keystroke is read.
    @test findfirst(TerminalPager._CURSOR_KEYS_ON, text)[1] < findfirst("<up>", text)[1]

    # The mouse events show their position.
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", IOBuffer("\e[<0;3;4Mq"), output, output)
    debug_keycode(term)
    @test occursin(
        "value = \"<mouse_press>\", $no_modifiers, x = 3, y = 4, " *
            "bytes = [27, 91, 60, 48, 59, 51, 59, 52, 77]",
        String(take!(output)),
    )
end
