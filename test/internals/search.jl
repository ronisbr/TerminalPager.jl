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

@testset "Search Starts At The Viewport" begin
    lines = ["match" ; ["filler $i" for i in 1:20] ; "match" ; ["tail $i" for i in 1:5]]
    pagerd = _create_modal_pagerd(lines, "")

    # From the top of the text, the first match in document order is selected.
    pagerd.start_row = 1
    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.num_matches == 2
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 1

    # Searching from below the first match must select the next one instead of jumping back to
    # the top of the text, which is what `less` does.
    pagerd.start_row = 10
    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 22

    # Exactly on a match, that match is selected.
    pagerd.start_row = 22
    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 22

    # Below every match, the navigation wraps to the first one.
    pagerd.start_row = 25
    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 1

    # No match at all must not select anything.
    TerminalPager._find_matches!(pagerd, r"nothing_here")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.num_matches == 0
    @test pagerd.active_search_match_id == 0
end

@testset "Search Viewport Bounds" begin
    # A match ending exactly at the right edge of the view used to be considered visible,
    # because the last column was computed one too far to the right.
    lines = [repeat("x", 40) * "needle" * repeat("y", 40)]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.display_size = (10, 20)
    pagerd.start_column = 1

    TerminalPager._find_matches!(pagerd, r"needle")
    TerminalPager._change_active_match!(pagerd, true)
    TerminalPager._move_view_to_match!(pagerd)

    match = pagerd.ordered_search_matches[1]
    last_column = match.column + match.width - 1
    view_last_column = pagerd.start_column + pagerd.display_size[2] - 1

    @test pagerd.start_column <= match.column
    @test last_column <= view_last_column

    # A zero-width match must not produce an end column before its start column.
    pagerd = _create_modal_pagerd(["abc", "def"], "")
    pagerd.display_size = (10, 20)
    TerminalPager._find_matches!(pagerd, r"^")
    TerminalPager._change_active_match!(pagerd, true)
    @test isnothing(TerminalPager._move_view_to_match!(pagerd))
    @test pagerd.start_column >= 1
    @test pagerd.start_row >= 1
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
