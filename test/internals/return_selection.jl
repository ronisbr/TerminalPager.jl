## Description #############################################################################
#
# Tests for the result of a pager session and for Enter in the visual mode.
#
############################################################################################

"""
    _run_session(text::String, keys::String; kwargs...) -> TerminalPager.PagerResult

Run a pager session over `text` fed with `keys` and return its result.

# Arguments

- `text::String`: Text shown by the pager.
- `keys::String`: Keystrokes typed, which must end the session.
"""
function _run_session(text::String, keys::String; kwargs...)
    input = IOBuffer(keys)
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)

    return TerminalPager._pager!(
        term,
        text;
        input = TerminalPager.PagerInput(input),
        use_alternate_screen_buffer = false,
        kwargs...,
    )
end

@testset "Session Result" begin
    text = join(["line $i" for i in 1:5], '\n')
    empty!(TerminalPager._LAST_YANK)

    # Enter in the visual mode copies the selection and quits.
    result = _run_session(text, "vMj\n")
    @test result isa TerminalPager.PagerResult
    @test result.selection == ["line 1", "line 2"]
    @test result.start_row == 1
    @test result.search_pattern == ""
    @test TerminalPager.yanked() == ["line 1", "line 2"]
    @test TerminalPager.yanked() !== TerminalPager._LAST_YANK

    # Quitting without a yank leaves an empty selection and records the viewport and the
    # search pattern.
    result = _run_session(text, "/line\nq")
    @test isempty(result.selection)
    @test result.search_pattern == "line"
    result = _run_session(join(["line $i" for i in 1:100], '\n'), "jjq")
    @test result.start_row == 3
    @test isempty(result.search_pattern)
    empty!(TerminalPager._SEARCH_HISTORY)

    # The yanked lines are kept even when the clipboard is not available, and the
    # decorations are removed.
    result = _run_session("\e[31mred\e[0m\nplain", "vy\n")
    @test result.selection == ["red"]
    @test TerminalPager.yanked() == ["red"]

    # The automatic mode returns an empty result for a text that fits.
    result = _run_session("a\nb", "q"; auto = true)
    @test isempty(result.selection)
    @test (result.start_row, result.start_column, result.search_pattern) == (1, 1, "")
    empty!(TerminalPager._LAST_YANK)
end

@testset "Return Selection From the Public Entry Point" begin
    # Without a terminal, the text is printed and the keyword still returns a result.
    old_stdout = stdout
    output = IOBuffer()

    try
        Base.eval(:(stdout = $(IOContext(output, :color => false))))
        @test isnothing(pager("a\nb"))
        @test String(take!(output)) == "a\nb"
        result = pager("a\nb"; return_selection = true)
        @test result isa TerminalPager.PagerResult
        @test isempty(result.selection)
        @test String(take!(output)) == "a\nb"
        result = @stdout_to_pager print("x") return_selection = true
        @test result isa TerminalPager.PagerResult
        @test isempty(result.selection)
        @test isnothing(@stdout_to_pager print("x"))
    finally
        Base.eval(:(stdout = $old_stdout))
    end
end

@testset "Enter Outside the Visual Mode Moves Down" begin
    lines = ["line $i" for i in 1:20]
    k = TerminalPager.Keystroke(; value = "<enter>")
    @test TerminalPager._pager_action(k) === :yank_quit

    # Outside the visual mode, Enter is one line down and raises no event, and a held Enter
    # is coalesced like the other vertical movements.
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.features = [:visual_mode]
    pagerd.cropped_lines = 11
    @test TerminalPager._resolve_action(pagerd, k) === :down
    @test TerminalPager._pager_key_process!(pagerd, k) === :down
    @test pagerd.start_row == 2
    @test isnothing(pagerd.event)

    pagerd.input = TerminalPager.PagerInput(TypedInput(["\n\n"]))
    key = TerminalPager._read_keystroke!(pagerd.input)
    action = TerminalPager._pager_key_process!(pagerd, key)
    @test TerminalPager._coalesce_navigation!(
        pagerd, action; display_size_function = _ -> pagerd.display_size
    ) == 2
    @test pagerd.start_row == 4

    # In the visual mode, Enter raises the event, which copies the selection and quits.
    pagerd.visual_mode = true
    @test TerminalPager._resolve_action(pagerd, k) === :yank_quit
    @test TerminalPager._pager_key_process!(pagerd, k) === :yank_quit
    @test pagerd.event === :yank_quit
    @test !TerminalPager._pager_event_process!(pagerd)
    @test pagerd.yanked == ["line 4"]

    # Without the visual mode feature, the event is not raised.
    pagerd.features = Symbol[]
    pagerd.visual_mode = true
    TerminalPager._pager_key_process!(pagerd, k)
    @test isnothing(pagerd.event)
    empty!(TerminalPager._LAST_YANK)
end
