## Description #############################################################################
#
# Tests for the search functions.
#
############################################################################################

"""
    _create_modal_pagerd(lines::Vector{String}, input_text::AbstractString) ->
        TerminalPager.Pager

Create a pager whose terminal is backed by an in-memory buffer and whose shared input
delivers the keystrokes of `input_text` one at a time, as typed keys.

# Arguments

- `lines::Vector{String}`: Pager text, one entry per line.
- `input_text::AbstractString`: Keystrokes the pager reads.
"""
function _create_modal_pagerd(lines::Vector{String}, input_text::AbstractString)
    # Each keystroke arrives on its own, as when the user types it.
    input = TypedInput(input_text)
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
    # The search uses smart case: a pattern without uppercase letters is case-insensitive.
    @test TerminalPager._try_regex("abc") == r"abc"i
    @test TerminalPager._try_regex("a(b|c)+") == r"a(b|c)+"i
    @test TerminalPager._try_regex("Abc") == r"Abc"
    @test occursin(TerminalPager._try_regex("abc"), "xABCx")
    @test !occursin(TerminalPager._try_regex("Abc"), "xABCx")

    # These used to escape the pager main loop and tear down the session.
    @test isnothing(TerminalPager._try_regex("["))
    @test isnothing(TerminalPager._try_regex("("))
    @test isnothing(TerminalPager._try_regex("*"))
    @test isnothing(TerminalPager._try_regex("a{2,1}"))
end

@testset "Literal Search" begin
    # The literal mode quotes the pattern, keeping the smart case.
    @test TerminalPager._literal_pattern("a[1]") == "\\Qa[1]\\E"
    @test TerminalPager._literal_pattern("x\\Ey") == "\\Qx\\E\\\\E\\Qy\\E"
    regex = TerminalPager._try_regex("a[1]"; literal = true)
    @test occursin(regex, "xa[1]x")
    @test occursin(regex, "xA[1]x")
    @test !occursin(regex, "a1")
    @test !occursin(TerminalPager._try_regex("A[1]"; literal = true), "xa[1]x")
    @test occursin(TerminalPager._try_regex("x\\Ey"; literal = true), "x\\Ey")
    @test occursin(TerminalPager._try_regex("x.*y"; literal = false), "xzy")
    @test !occursin(TerminalPager._try_regex("x.*y"; literal = true), "xzy")

    # ALT-l at the prompt toggles the mode, which is shown and kept for the session.
    lines = ["x.*y", "xzy", "x.*y"]
    pagerd = _create_modal_pagerd(lines, "\elx.*y\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.literal_search
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 3]
    @test occursin("[lit] match 1/2", String(take!(pagerd.term.out_stream)))

    # The next search is still literal, and the tag is shown before the pattern is typed.
    pagerd.input = TerminalPager.PagerInput(TypedInput("x.*y\n"))
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 3]

    # Toggling the mode after the pattern reruns the search before Enter is confirmed.
    pagerd.input = TerminalPager.PagerInput(TypedInput("x.*y\el\n"))
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test !pagerd.literal_search
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 2, 3]
    @test !occursin("[lit]", split(String(take!(pagerd.term.out_stream)), "x.*y")[end])

    # The toggle arriving with Enter in one paste is applied by the confirmed search.
    pagerd.input = TerminalPager.PagerInput(TypedInput(["x.*y", "\el\n"]))
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.literal_search
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 3]

    # The tag is shown for huge texts, whose matches are not previewed.
    pagerd = _create_modal_pagerd(lines, "\elx.*y\n")
    pagerd.num_lines = TerminalPager._INCREMENTAL_SEARCH_MAX_LINES + 1
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 3]
    @test occursin("[lit]", String(take!(pagerd.term.out_stream)))
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Column Restricted Search" begin
    unrestricted = TerminalPager._UNRESTRICTED_COLUMNS

    # The range is written before the pattern; a missing bound is open.
    @test TerminalPager._parse_search_input("@12:20 x y") == ("x y", 12:20)
    @test TerminalPager._parse_search_input("@12 x") == ("x", 12:typemax(Int))
    @test TerminalPager._parse_search_input("@12: x") == ("x", 12:typemax(Int))
    @test TerminalPager._parse_search_input("@:20 x") == ("x", 1:20)
    @test TerminalPager._parse_search_input("abc") == ("abc", unrestricted)
    @test TerminalPager._parse_search_input("@ x") == ("@ x", unrestricted)
    @test TerminalPager._parse_search_input("@12:20") == ("@12:20", unrestricted)
    @test TerminalPager._parse_search_input("@12:20 ") == ("", 12:20)
    @test isnothing(TerminalPager._parse_search_input("@5:2 x"))
    @test isnothing(TerminalPager._parse_search_input("@0 x"))

    # Only the matches starting in the range are kept, in both the highlighting dictionary
    # and the navigation order.
    lines = ["a a a", "xa", "\e[31maaa\e[0m a"]
    pagerd = _create_modal_pagerd(lines, "")
    TerminalPager._find_matches!(pagerd, r"a"; columns = 3:4)
    @test pagerd.search_matches == TerminalPager.SearchMatches(1 => [(3, 1)], 3 => [(3, 1)])
    @test [(m.line, m.column) for m in pagerd.ordered_search_matches] == [(1, 3), (3, 3)]
    @test pagerd.search_columns == 3:4

    TerminalPager._find_matches!(pagerd, r"a")
    @test sum(length, values(pagerd.search_matches)) == 8
    @test pagerd.search_columns == unrestricted

    # The modal flow applies the range, and quitting the search resets it.
    pagerd = _create_modal_pagerd(lines, "@3:4 a\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test length(pagerd.ordered_search_matches) == 2
    @test pagerd.search_columns == 3:4
    @test occursin("match 1/2", String(take!(pagerd.term.out_stream)))
    pagerd.event = :quit_search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.search_columns == unrestricted

    # A plain pattern resets the range, and cancelling restores the previous one.
    pagerd = _create_modal_pagerd(lines, "@3:4 a\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    pagerd.input = TerminalPager.PagerInput(TypedInput("a\n"))
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.search_columns == unrestricted
    @test length(pagerd.ordered_search_matches) == 8
    pagerd.input = TerminalPager.PagerInput(TypedInput("@3:4 a\e"))
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.search_columns == unrestricted
    @test length(pagerd.ordered_search_matches) == 8

    # An invalid range is reported while typing and rejected on Enter. A range without a
    # pattern is like an empty pattern.
    pagerd = _create_modal_pagerd(lines, "@5:2 a\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test pagerd.message == "Invalid column range: @5:2 a"
    @test occursin("invalid range", String(take!(pagerd.term.out_stream)))
    pagerd = _create_modal_pagerd(lines, "@3:4 \n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test isempty(pagerd.message)

    # The range is parsed before the literal quoting.
    pagerd = _create_modal_pagerd(["a.a a.a", "aba"], "\el@3 a.a\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test [(m.line, m.column) for m in pagerd.ordered_search_matches] == [(1, 5)]
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Ordered Match Index Strategies" begin
    # The index is built by sorting the matched lines when they are sparse, and by walking the
    # lines when almost every one of them matches. Both must produce the same result.
    for (num_lines, matched) in (
        (1_000, (5, 999)),
        (1_000, Tuple(1:1_000)),
        (1_000, Tuple(1:100:1_000)),
        (10, Tuple(1:10)),
        (10, (10,)),
        (10, ()),
    )
        matches = TerminalPager.SearchMatches(
            line => [(line, 2), (line + 1, 3)] for line in matched
        )
        ordered = TerminalPager._ordered_search_matches(matches, num_lines)

        @test length(ordered) == 2 * length(matched)
        @test issorted(ordered; by = m -> (m.line, m.index_in_line))

        for match in ordered
            @test match.line in matched
            @test 1 <= match.index_in_line <= 2
        end
    end

    # Lines beyond the text must be ignored, as before.
    matches = TerminalPager.SearchMatches(5 => [(1, 1)], 500 => [(1, 1)])
    @test length(TerminalPager._ordered_search_matches(matches, 10)) == 1
    @test isempty(TerminalPager._ordered_search_matches(TerminalPager.SearchMatches(), 10))
end

@testset "Search Starts At The Viewport" begin
    lines = ["match"; ["filler $i" for i in 1:20]; "match"; ["tail $i" for i in 1:5]]
    pagerd = _create_modal_pagerd(lines, "")

    # From the top of the text, the first match in document order is selected.
    pagerd.start_row = 1
    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    @test length(pagerd.ordered_search_matches) == 2
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
    @test length(pagerd.ordered_search_matches) == 0
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

@testset "Search With Frozen Regions" begin
    # A match inside the frozen rows is always visible: navigating to it must not move the
    # view vertically.
    lines = ["match"; ["filler $i" for i in 1:50]; "match"; ["tail $i" for i in 1:5]]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.frozen_rows = 2
    pagerd.start_row = 40

    TerminalPager._find_matches!(pagerd, r"match")
    TerminalPager._change_active_match!(pagerd, true)
    TerminalPager._move_view_to_match!(pagerd)
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 52

    # The next match wraps to line 1, which is frozen and hence always on screen.
    TerminalPager._change_active_match!(pagerd, true)
    row_before = pagerd.start_row
    TerminalPager._move_view_to_match!(pagerd)
    @test pagerd.ordered_search_matches[pagerd.active_search_match_id].line == 1
    @test pagerd.start_row == row_before

    # The first visible column must never fall inside the frozen columns.
    lines = [repeat("x", 4) * "needle" * repeat("y", 60)]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.display_size = (10, 20)
    pagerd.frozen_columns = 8
    pagerd.start_column = 30

    TerminalPager._find_matches!(pagerd, r"needle")
    TerminalPager._change_active_match!(pagerd, true)
    TerminalPager._move_view_to_match!(pagerd)
    @test pagerd.start_column == 9

    # A match that ends inside the frozen columns is always visible: the view must not move
    # horizontally for it.
    lines = ["ne" * repeat("x", 100)]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.display_size = (10, 20)
    pagerd.frozen_columns = 8
    pagerd.start_column = 30

    TerminalPager._find_matches!(pagerd, r"ne")
    TerminalPager._change_active_match!(pagerd, true)
    TerminalPager._move_view_to_match!(pagerd)
    @test pagerd.start_column == 30
end

@testset "Invalid Search Pattern" begin
    lines = ["first line", "second line", "third line"]

    # A malformed pattern must show a message and keep the session alive in view mode with
    # no matches recorded. The message used to be modal, consuming the next keystroke.
    pagerd = _create_modal_pagerd(lines, "[\n ")
    pagerd.event = :search

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.mode == :view
    @test length(pagerd.ordered_search_matches) == 0
    @test pagerd.message == "Invalid regex: ["
    @test pagerd.message_kind === :error
    @test TerminalPager._read_keystroke!(pagerd.input).value == " "

    # A valid pattern must still work through the same code path.
    pagerd = _create_modal_pagerd(lines, "line\n")
    pagerd.event = :search

    @test TerminalPager._pager_event_process!(pagerd) != false
    @test pagerd.mode == :searching
    @test length(pagerd.ordered_search_matches) == 3
    @test pagerd.active_search_match_id == 1
end

@testset "Incremental Search" begin
    lines = ["line $i" for i in 1:30]

    # The matches are previewed while the pattern is typed, so the view moves before Enter.
    pagerd = _create_modal_pagerd(lines, "25\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test length(pagerd.ordered_search_matches) == 1
    @test pagerd.start_row == 25 - 9 + 1
    @test occursin("match 1/1", String(take!(pagerd.term.out_stream)))

    # Cancelling the prompt restores the viewport and the previous search.
    pagerd = _create_modal_pagerd(lines, "25\e")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test isempty(pagerd.ordered_search_matches)
    @test pagerd.start_row == 1

    pagerd = _create_modal_pagerd(lines, "2\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    matches_before = pagerd.ordered_search_matches
    pagerd = _create_modal_pagerd(lines, "25\e")
    pagerd.search_matches = TerminalPager.SearchMatches(2 => [(6, 1)])
    pagerd.ordered_search_matches = [TerminalPager.SearchMatch(2, 1, 6, 1)]
    pagerd.active_search_match_id = 1
    pagerd.mode = :searching
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test [m.line for m in pagerd.ordered_search_matches] == [2]
    @test pagerd.start_row == 1

    # A pattern that stops matching while it is typed restores the viewport, and the prompt
    # reports it.
    pagerd = _create_modal_pagerd(lines, "25x\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test isempty(pagerd.ordered_search_matches)
    @test pagerd.start_row == 1
    @test occursin("no match", String(take!(pagerd.term.out_stream)))

    # An invalid pattern is reported while typing and rejected on Enter.
    pagerd = _create_modal_pagerd(lines, "[\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test pagerd.message == "Invalid regex: ["
    @test occursin("invalid regex", String(take!(pagerd.term.out_stream)))

    # The preview is skipped for huge texts, and the search runs on Enter.
    pagerd = _create_modal_pagerd(lines, "25\n")
    pagerd.num_lines = TerminalPager._INCREMENTAL_SEARCH_MAX_LINES + 1
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test pagerd.start_row == 25 - 9 + 1
    @test !occursin("match 1/1", String(take!(pagerd.term.out_stream)))
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Pasted Search Pattern" begin
    # A pasted pattern arrives at once. Previewing it used to search the whole text once per
    # character, although only the last result was shown. The search now runs once, when
    # the pattern is confirmed.
    lines = ["line $i" for i in 1:30]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.input = TerminalPager.PagerInput(TypedInput(["25\n"]))
    pagerd.event = :search

    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test length(pagerd.ordered_search_matches) == 1
    @test pagerd.start_row == 25 - 9 + 1
    @test !occursin("match", String(take!(pagerd.term.out_stream)))
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Search Wrap Notice" begin
    pagerd = _create_modal_pagerd(["a", "b", "a"], "")
    TerminalPager._find_matches!(pagerd, r"a")
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.active_search_match_id == 1
    @test isempty(pagerd.message)

    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.active_search_match_id == 2
    @test isempty(pagerd.message)

    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.active_search_match_id == 1
    @test pagerd.message == "Search wrapped to the top"

    TerminalPager._clear_message!(pagerd)
    TerminalPager._change_active_match!(pagerd, false)
    @test pagerd.active_search_match_id == 2
    @test pagerd.message == "Search wrapped to the bottom"
end
