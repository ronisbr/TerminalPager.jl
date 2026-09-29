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

    @test isnothing(
        TerminalPager.debug_keycode(; _terminal_factory = () -> term, _raw_runner = raw_runner)
    )
    @test raw_transitions == [true, false]

    text = String(take!(output))
    mouse = TerminalPager._get_preference("mouse")::Bool

    @test occursin("<up>", text)
    @test occursin(TerminalPager._CURSOR_KEYS_ON, text)
    @test endswith(text, TerminalPager._CURSOR_KEYS_OFF)
    @test occursin(TerminalPager._MOUSE_ON, text) == mouse
    @test occursin(TerminalPager._MOUSE_OFF, text) == mouse

    # The modes are enabled before the first keystroke is read.
    @test findfirst(TerminalPager._CURSOR_KEYS_ON, text)[1] < findfirst("<up>", text)[1]
end
