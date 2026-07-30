## Description #############################################################################
#
# Tests for the search functions.
#
############################################################################################

"""
    _create_modal_pagerd(lines::Vector{String}, input_text::AbstractString) ->
        TerminalPager.Pager

Create a pager whose terminal and shared input are backed by in-memory buffers.

# Arguments

- `lines::Vector{String}`: Pager text, one entry per line.
- `input_text::AbstractString`: Keystrokes the pager reads.
"""
function _create_modal_pagerd(lines::Vector{String}, input_text::AbstractString)
    input = IOBuffer(input_text)
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    text_layout = TerminalPager.TextViewLayout(lines)

    return TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => false),
        display_size = (10, 40),
        input = TerminalPager.PagerInput(input),
        num_lines = length(lines),
        term = term,
        text_layout = text_layout,
    )
end

@testset "Regular Expression Validation" begin
    @test TerminalPager._try_regex("abc") == r"abc"
    @test TerminalPager._try_regex("a(b|c)+") == r"a(b|c)+"

    # These used to escape the pager main loop and tear down the session.
    @test isnothing(TerminalPager._try_regex("["))
    @test isnothing(TerminalPager._try_regex("("))
    @test isnothing(TerminalPager._try_regex("*"))
    @test isnothing(TerminalPager._try_regex("a{2,1}"))
end

@testset "Invalid Search Pattern" begin
    lines = ["first line", "second line", "third line"]

    # A malformed pattern must show a message, wait for a keystroke, and keep the session
    # alive in view mode with no matches recorded.
    pagerd = _create_modal_pagerd(lines, "[\n ")
    pagerd.event = :search

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.mode == :view
    @test pagerd.num_matches == 0
    @test occursin("Invalid regex!", String(take!(pagerd.term.out_stream)))

    # A valid pattern must still work through the same code path.
    pagerd = _create_modal_pagerd(lines, "line\n")
    pagerd.event = :search

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.mode == :searching
    @test pagerd.num_matches == 3
    @test pagerd.active_search_match_id == 1
end
