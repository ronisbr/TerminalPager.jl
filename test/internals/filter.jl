## Description #############################################################################
#
# Tests for the line filter.
#
############################################################################################

const _FILTER_LINES = [
    "header",
    "error one",
    "info two",
    "\e[31merror\e[0m three",
    "info four",
    "error five",
]

@testset "Filter Parsing and Rows" begin
    @test TerminalPager._parse_filter("abc") == ("abc", false)
    @test TerminalPager._parse_filter("!abc") == ("abc", true)
    @test TerminalPager._parse_filter("\\!abc") == ("!abc", false)
    @test TerminalPager._parse_filter("") == ("", false)

    layout = TerminalPager.ViewLayout(_FILTER_LINES)
    @test TerminalPager._filter_rows(layout, r"error", false, 0) == [2, 4, 6]
    @test TerminalPager._filter_rows(layout, r"error", true, 0) == [1, 3, 5]
    @test TerminalPager._filter_rows(layout, r"error", false, 1) == [1, 2, 4, 6]
    @test TerminalPager._filter_rows(layout, r"error", true, 2) == [1, 2, 3, 5]
    @test TerminalPager._filter_rows(layout, r"nothing", false, 0) == Int[]
    @test TerminalPager._filter_rows(layout, r"\e", false, 0) == Int[]
end

@testset "Filter Flow" begin
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "&")) === :filter

    # The filter keeps the matching lines, maps the rows to the source lines, and resets
    # the width and the frame.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "err\n")
    pagerd.frame_cache.valid = true
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.filter_regex == r"err"i
    @test !pagerd.filter_inverted
    @test pagerd.filter_pattern == "err"
    @test pagerd.num_lines == 3
    @test collect(pagerd.text_layout) == ["error one", "\e[31merror\e[0m three", "error five"]
    @test pagerd.row_to_line == [2, 4, 6]
    @test pagerd.line_to_row == [0, 1, 0, 2, 0, 3]
    @test pagerd.source_layout[1] == "header"
    @test TerminalPager._text_width(pagerd) == 11
    @test TerminalPager._FILTER_HISTORY == ["err"]
    @test occursin("3 of 6 lines", String(take!(pagerd.term.out_stream)))

    # The ruler shows the source line numbers, and its width follows the last one.
    pagerd.show_ruler = true
    @test TerminalPager._ruler_width(pagerd) == 4
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    ruler = pagerd.display_config.ruler
    @test startswith(rows[1], ruler * " 2 │\e[0m")
    @test startswith(rows[2], ruler * " 4 │\e[0m")
    @test startswith(rows[3], ruler * " 6 │\e[0m")
    pagerd.show_ruler = false

    # An inverted filter hides the matching lines, and a literal `!` is escaped.
    pagerd.input = TerminalPager.PagerInput(TypedInput("!err\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.filter_inverted
    @test pagerd.row_to_line == [1, 3, 5]
    pagerd.input = TerminalPager.PagerInput(TypedInput("\\!x\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.filter_pattern == "\\!x"
    @test pagerd.filter_regex == r"!x"i
    @test pagerd.num_lines == 0

    # An empty pattern clears the filter, and the layout is the source again.
    pagerd.input = TerminalPager.PagerInput(TypedInput("\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test isnothing(pagerd.filter_regex)
    @test pagerd.text_layout === pagerd.source_layout
    @test isnothing(pagerd.row_to_line)
    @test pagerd.num_lines == 6

    # Cancelling the prompt restores the previous filter and viewport.
    pagerd.input = TerminalPager.PagerInput(TypedInput("err\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    pagerd.start_row = 2
    pagerd.input = TerminalPager.PagerInput(TypedInput("info\e"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.filter_pattern == "err"
    @test pagerd.row_to_line == [2, 4, 6]
    @test pagerd.start_row == 2

    # An invalid pattern is reported while typing and rejected on Enter.
    pagerd.input = TerminalPager.PagerInput(TypedInput("[\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.message == "Invalid regex: ["
    @test pagerd.filter_pattern == "err"
    @test occursin("invalid regex", String(take!(pagerd.term.out_stream)))

    # The frozen rows are always shown, and the top line is kept when it is visible.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "info\n")
    pagerd.frozen_rows = 1
    pagerd.start_row = 3
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.row_to_line == [1, 3, 5]
    @test pagerd.start_row == 2

    empty!(TerminalPager._FILTER_HISTORY)
end

@testset "Filter and Search" begin
    # The search runs over the visible rows and again when the filter changes.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "o\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test length(pagerd.ordered_search_matches) == 8
    pagerd.input = TerminalPager.PagerInput(TypedInput("err\n"))
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test [m.line for m in pagerd.ordered_search_matches] == [1, 1, 2, 3]
    @test pagerd.search_regex == r"o"i

    # Esc clears the search first, and then the filter.
    pagerd.event = :quit_search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test isempty(pagerd.ordered_search_matches)
    @test isnothing(pagerd.search_regex)
    @test pagerd.filter_pattern == "err"
    pagerd.event = :quit_search
    @test TerminalPager._pager_event_process!(pagerd)
    @test isnothing(pagerd.filter_regex)
    @test pagerd.num_lines == 6
    empty!(TerminalPager._SEARCH_HISTORY)
    empty!(TerminalPager._FILTER_HISTORY)
end

@testset "Filter and Positions" begin
    lines = ["line $i" for i in 1:30]
    pagerd = _create_modal_pagerd(lines, "")
    pagerd.filter_regex = r"[05]$"
    pagerd.filter_pattern = "[05]\$"
    TerminalPager._rebuild_view_layout!(pagerd)
    @test pagerd.row_to_line == [5, 10, 15, 20, 25, 30]

    # A line number is a source line; a hidden one goes to the next visible line.
    pagerd.input = TerminalPager.PagerInput(TypedInput("15\n"))
    pagerd.event = :goto_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 3
    @test isempty(pagerd.message)
    pagerd.input = TerminalPager.PagerInput(TypedInput("12\n"))
    pagerd.event = :goto_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 3
    @test pagerd.message == "Line 12 is hidden by the filter"
    pagerd.input = TerminalPager.PagerInput(TypedInput("99\n"))
    pagerd.event = :goto_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 6

    # The marks, the anchor, and the bookmarks store source lines and survive a change of
    # the filter.
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.start_row = 1
    pagerd.visual_mode_line = 2
    pagerd.event = :select_visual_mode_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_mode_selected_lines == [10]
    pagerd.visual_mode_line = 4
    pagerd.event = :toggle_visual_anchor
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.visual_anchor == 20
    pagerd.visual_mode_line = 6
    @test TerminalPager._visual_range(pagerd) == 4:6
    @test TerminalPager._selected_line_ids(pagerd) == [10, 20, 25, 30]
    @test TerminalPager._num_selected_lines(pagerd) == 4
    pagerd.input = TerminalPager.PagerInput(TypedInput("a"))
    pagerd.event = :set_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.bookmarks['a'] == (30, 1)

    TerminalPager._clear_filter!(pagerd)
    @test pagerd.visual_mode_selected_lines == [10]
    @test pagerd.start_row == 5
    @test pagerd.visual_mode_line == 6
    @test TerminalPager._visual_range(pagerd) == 10:20
    @test TerminalPager._bookmark_rows(pagerd) == Set([30])
    pagerd.input = TerminalPager.PagerInput(TypedInput("a"))
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 30

    # With the filter back, a hidden mark is not drawn and a hidden bookmark jumps to the
    # next visible line.
    pagerd.filter_regex = r"[05]$"
    pagerd.filter_pattern = "[05]\$"
    push!(pagerd.visual_mode_selected_lines, 12)
    pagerd.bookmarks['b'] = (12, 1)
    TerminalPager._rebuild_view_layout!(pagerd)
    @test TerminalPager._bookmark_rows(pagerd) == Set([6])
    pagerd.visual_mode = true
    pagerd.start_row = 1
    pagerd.visual_mode_line = 1
    pagerd.visual_anchor = 0
    TerminalPager._view!(pagerd)
    @test pagerd.visual_lines == [1, 2]
    pagerd.input = TerminalPager.PagerInput(TypedInput("b"))
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 3

    # The copies take the selection from the source lines, without the hidden marks, and
    # the whole text from the visible rows.
    pagerd.visual_mode_line = 1
    @test TerminalPager._num_selected_lines(pagerd) == 2
    @test TerminalPager._assemble_yank_text(
        pagerd.source_layout, TerminalPager._selected_line_ids(pagerd)
    ) == ("line 10\nline 15\n", 2)
    pagerd.event = :yank_all
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.yanked == ["line 5", "line 10", "line 15", "line 20", "line 25", "line 30"]
    empty!(TerminalPager._LAST_YANK)
end

@testset "Frozen and Title Rows Changed With a Filter" begin
    # The frozen and the title rows are always shown. Hence, the visible rows must be the
    # same whether the rows are frozen before or after the filter is applied.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "1\n\n")
    pagerd.features = [:change_freeze, :change_frozen_columns, :change_frozen_rows]
    TerminalPager._apply_filter!(pagerd, r"info", false, "info")
    filtered = copy(pagerd.row_to_line)
    @test first(filtered) != 1

    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.frozen_rows == 1
    @test pagerd.row_to_line == [1; filtered]

    # Unfreezing the rows hides the ones that do not match again.
    pagerd.input = TerminalPager.PagerInput(TypedInput("0\n\n"))
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.row_to_line == filtered

    # The same applies to the title rows.
    pagerd.input = TerminalPager.PagerInput(TypedInput("1\n"))
    pagerd.event = :change_title_rows
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.title_rows == 1
    @test pagerd.row_to_line == [1; filtered]

    # Without a filter, nothing is rebuilt.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "1\n\n")
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test isnothing(pagerd.row_to_line)
end

@testset "Inverted Filter Without a Pattern" begin
    # `!` alone has no pattern. It must keep the lines as they are whether it is typed, in
    # which case it is previewed, or pasted at once.
    for input in (TypedInput("!\n"), TypedInput(["!\n"]))
        pagerd = _create_modal_pagerd(_FILTER_LINES, "")
        pagerd.input = TerminalPager.PagerInput(input)
        pagerd.term = REPL.Terminals.TTYTerminal("", input, IOBuffer(), IOBuffer())
        pagerd.event = :filter
        @test TerminalPager._pager_event_process!(pagerd)
        @test isnothing(pagerd.filter_regex)
        @test pagerd.filter_pattern == ""
        @test pagerd.num_lines == length(_FILTER_LINES)
        @test isempty(TerminalPager._FILTER_HISTORY)
    end

    # An active filter is kept.
    pagerd = _create_modal_pagerd(_FILTER_LINES, "!\n")
    TerminalPager._apply_filter!(pagerd, r"info", false, "info")
    num_lines = pagerd.num_lines
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.filter_pattern == "info"
    @test pagerd.num_lines == num_lines
    @test isempty(TerminalPager._FILTER_HISTORY)
end

@testset "Filter With Huge Frozen Rows" begin
    # The numbers of frozen and title rows are selected by the user. A value larger than
    # the number of lines must not overflow when the rows of the filter are computed.
    layout = TerminalPager.ViewLayout(["a1", "b", "a2"])
    @test TerminalPager._filter_rows(layout, r"a", false, typemax(Int)) == [1, 2, 3]
    @test TerminalPager._filter_rows(layout, r"a", false, -5) == [1, 3]

    pagerd = _create_modal_pagerd(["a1", "b", "a2"], "")
    pagerd.frozen_rows = typemax(Int)
    TerminalPager._apply_filter!(pagerd, r"a", false, "a")
    @test pagerd.num_lines == 3
end

@testset "Filter Status Line" begin
    pagerd, output = _create_status_pagerd(["line $i" for i in 1:20])
    pagerd.features = [:help]
    pagerd.filter_regex = r"1"
    pagerd.filter_pattern = "1"
    TerminalPager._rebuild_view_layout!(pagerd)
    @test pagerd.num_lines == 11

    text = _status_bar_text(pagerd, output)
    @test text == "❯  FILTER 1 11/20" * " "^2 * "?:help  &:filter  Esc:clear  q:quit   All"
    @test textwidth(text) == 60
    @test TerminalPager._status_hint(:filter, false) == "&:filter  Esc:clear  q:quit"

    # The segment is dropped before the mode name on a narrow display.
    pagerd.display_size = (10, 12)
    @test _status_bar_text(pagerd, output) == "❯" * " "^8 * "All"

    # The name is styled with the filter face.
    pagerd, output = _create_status_pagerd(["line $i" for i in 1:20]; color = true)
    pagerd.filter_regex = r"1"
    pagerd.filter_pattern = "1"
    TerminalPager._rebuild_view_layout!(pagerd)
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(pagerd.display_config.mode_filter * "FILTER", String(take!(output)))
end

@testset "Filter Keyword" begin
    # The filter is a feature of the session, enabled unless the keyword disables it.
    text = join(("line $i" for i in 1:20), '\n')
    filtered = r"FILTER 1 11/20"

    @test occursin(filtered, _session_output(text, "&1\rq"))
    @test occursin(filtered, _session_output(text, "&1\rq"; has_filter = true))
    @test !occursin(filtered, _session_output(text, "&1\rq"; has_filter = false))
    @test_throws TypeError _session_output(text, "q"; has_filter = 1)

    @test TerminalPager._action_event(:filter, [:filter]) === :filter
    @test TerminalPager._action_event(:filter, [:help]) === nothing

    # The search does not need the feature, and the cheat sheet marks the action with it.
    @test TerminalPager._action_event(:search, Symbol[]) === :search
    @test occursin(":filter [filter]", TerminalPager._help_string(false))

    # The filter history is shared by the sessions.
    empty!(TerminalPager._FILTER_HISTORY)
end
