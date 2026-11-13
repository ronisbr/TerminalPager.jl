## Description #############################################################################
#
# Tests for the bookmarks.
#
############################################################################################

@testset "Bookmarks" begin
    lines = ["line $i" for i in 1:30]
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "m")) ===
        :set_bookmark
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "M")) ===
        :select_visual_mode_line
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "'")) ===
        :goto_bookmark

    # Setting a bookmark records the top row and column, shows the prompt, and confirms.
    pagerd = _create_modal_pagerd(lines, "a")
    pagerd.start_row = 7
    pagerd.start_column = 3
    pagerd.redraw = false
    pagerd.event = :set_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.bookmarks == Dict('a' => (7, 3))
    @test pagerd.message == "Mark a set"
    @test pagerd.message_kind === :info
    @test pagerd.redraw
    @test occursin("\e[10;1H\e[0Km", String(take!(pagerd.term.out_stream)))

    # Jumping shows the bookmark at the top and remembers the position before the jump.
    pagerd.input = TerminalPager.PagerInput(TypedInput("a"))
    pagerd.start_row = 1
    pagerd.start_column = 1
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 7
    @test pagerd.start_column == 3
    @test pagerd.last_position == (1, 1)
    @test occursin("\e[10;1H\e[0K'", String(take!(pagerd.term.out_stream)))

    # `''` returns to the position before the jump, and again to the one before that.
    pagerd.input = TerminalPager.PagerInput(TypedInput("'"))
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test (pagerd.start_row, pagerd.start_column) == (1, 1)
    @test pagerd.last_position == (7, 3)
    pagerd.input = TerminalPager.PagerInput(TypedInput("'"))
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test (pagerd.start_row, pagerd.start_column) == (7, 3)

    # A missing bookmark, a cancelled prompt, and a key that is not a letter are reported or
    # ignored without moving.
    pagerd.input = TerminalPager.PagerInput(TypedInput("z"))
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 7
    @test pagerd.message == "Mark z not set"
    @test pagerd.message_kind === :error

    for input in ("\e", "\x03", "\e[A")
        pagerd.input = TerminalPager.PagerInput(TypedInput(input))
        TerminalPager._clear_message!(pagerd)
        pagerd.event = :set_bookmark
        @test TerminalPager._pager_event_process!(pagerd)
        @test pagerd.bookmarks == Dict('a' => (7, 3))
        @test isempty(pagerd.message)
    end

    pagerd.input = TerminalPager.PagerInput(TypedInput("1"))
    pagerd.event = :set_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.bookmarks == Dict('a' => (7, 3))
    @test pagerd.message == "Bookmarks are letters"

    # Without a previous position, `''` is reported.
    pagerd = _create_modal_pagerd(lines, "'")
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.message == "No previous position"
    @test pagerd.message_kind === :error

    # The jump never enters the frozen rows or columns.
    pagerd = _create_modal_pagerd(lines, "b")
    pagerd.bookmarks['b'] = (2, 1)
    pagerd.frozen_rows = 3
    pagerd.frozen_columns = 2
    pagerd.start_row = 4
    pagerd.start_column = 3
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test (pagerd.start_row, pagerd.start_column) == (4, 3)
end

@testset "Bookmarks in the Visual Mode" begin
    lines = ["line $i" for i in 1:30]

    # The visual line is bookmarked, and the jump puts the visual line on it.
    pagerd = _create_modal_pagerd(lines, "a")
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.start_row = 3
    pagerd.visual_mode_line = 4
    pagerd.event = :set_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.bookmarks == Dict('a' => (6, 1))

    pagerd.input = TerminalPager.PagerInput(TypedInput("a"))
    pagerd.start_row = 20
    pagerd.visual_mode_line = 5
    pagerd.event = :goto_bookmark
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 6
    @test pagerd.visual_mode_line == 1
end

@testset "Jumps Remember the Position" begin
    lines = ["line $i" for i in 1:30]

    # The goto and the search record the viewport before the jump.
    pagerd = _create_modal_pagerd(lines, "25\n")
    pagerd.start_row = 4
    pagerd.event = :goto_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 25
    @test pagerd.last_position == (4, 1)

    pagerd = _create_modal_pagerd(lines, "line 2\n")
    pagerd.start_row = 4
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.last_position == (4, 1)

    pagerd.start_row = 10
    pagerd.event = :next_match
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.last_position == (10, 1)
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Bookmarks in the Ruler" begin
    lines = ["line $i" for i in 1:6]
    pagerd = _create_redraw_pagerd(lines; display_size = (8, 20), color = true)
    pagerd.show_ruler = true
    pagerd.bookmarks['a'] = (2, 1)
    pagerd.bookmarks['b'] = (5, 1)

    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    ruler = pagerd.display_config.ruler
    mark = pagerd.display_config.bookmark
    @test startswith(rows[1], ruler * " 1 │")
    @test startswith(rows[2], ruler * mark * "•" * ruler * "2 │")
    @test startswith(rows[5], ruler * mark * "•" * ruler * "5 │")
    @test startswith(rows[6], ruler * " 6 │")

    @test isnothing(TerminalPager._bookmark_rows(_create_modal_pagerd(lines, "")))
    @test TerminalPager._bookmark_rows(pagerd) == Set([2, 5])
end
