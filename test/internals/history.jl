## Description #############################################################################
#
# Tests for the history of the texts shown by the pager.
#
############################################################################################

@testset "Pager History" begin
    # The function is a binding of this package, not an extension of `Base.last`.
    @test TerminalPager.last !== Base.last
    empty!(TerminalPager._PAGER_HISTORY)

    try
        # The entries are kept from the oldest to the newest, up to the preference.
        TerminalPager.set_preference!("history_size", 2)
        TerminalPager._push_pager_history!("one\ntwo", (; frozen_rows = 1))
        TerminalPager._push_pager_history!("\e[31mred\e[0m\n", (;))
        entry = TerminalPager._push_pager_history!("three\nlines\nhere\n", (; auto = true))
        @test length(TerminalPager._PAGER_HISTORY) == 2
        @test TerminalPager._PAGER_HISTORY[end] === entry
        @test TerminalPager._PAGER_HISTORY[1].text == "\e[31mred\e[0m\n"
        @test isnothing(entry.result)
        @test entry.options == (; auto = true)

        # The byte cap drops the oldest entries, but the newest one is always kept.
        TerminalPager.set_preference!("history_max_bytes", 4)
        TerminalPager._push_pager_history!("12345678", (;))
        @test length(TerminalPager._PAGER_HISTORY) == 1
        @test TerminalPager._PAGER_HISTORY[1].text == "12345678"
        TerminalPager.drop_preference!("history_max_bytes")

        # The labels show the position, the time, the number of lines, and the first line
        # without the decorations, cropped to the width.
        empty!(TerminalPager._PAGER_HISTORY)
        TerminalPager._push_pager_history!("one\ntwo", (;))
        TerminalPager._push_pager_history!("\e[31mred line\e[0m is long\n", (;))
        label = TerminalPager._history_label(1, TerminalPager._PAGER_HISTORY[end]; width = 80)
        @test occursin(r"^#1  \d\d:\d\d  1 line  red line is long$", label)
        label = TerminalPager._history_label(2, TerminalPager._PAGER_HISTORY[1]; width = 80)
        @test occursin(r"^#2  \d\d:\d\d  2 lines  one$", label)
        label = TerminalPager._history_label(1, TerminalPager._PAGER_HISTORY[end]; width = 24)
        @test occursin(r"^#1  \d\d:\d\d  1 line  red …$", label)
        @test textwidth(label) == 24

        # A first line that fits exactly is not cropped.
        fits = TerminalPager._history_label(2, TerminalPager._PAGER_HISTORY[1]; width = 80)
        label = TerminalPager._history_label(
            2, TerminalPager._PAGER_HISTORY[1]; width = textwidth(fits)
        )
        @test label == fits
        label = TerminalPager._history_label(
            2, TerminalPager._PAGER_HISTORY[1]; width = textwidth(fits) - 1
        )
        @test endswith(label, "lines  o…")
        @test textwidth(label) == textwidth(fits) - 1

        label = TerminalPager._history_label(1, TerminalPager._PAGER_HISTORY[end]; width = 5)
        @test occursin(r"^#1  \d\d:\d\d  1 line$", label)
        @test TerminalPager._history_num_lines("") == 0
        @test TerminalPager._history_num_lines("a\n\nb\n") == 3

        # The history is listed from the most recent entry.
        io = IOBuffer()
        TerminalPager.history(io)
        listing = split(String(take!(io)), '\n'; keepempty = false)
        @test length(listing) == 2
        @test startswith(listing[1], "#1 ")
        @test endswith(listing[1], "red line is long")
        @test endswith(listing[2], "one")

        # Without a terminal, reopening prints the text; an entry out of range throws.
        old_stdout = stdout
        output = IOBuffer()
        try
            Base.eval(:(stdout = $(IOContext(output, :color => false))))
            @test isnothing(TerminalPager.last())
            @test String(take!(output)) == "\e[31mred line\e[0m is long\n"
            @test isnothing(TerminalPager.last(2))
            @test String(take!(output)) == "one\ntwo"
            @test_throws ArgumentError TerminalPager.last(3)
            @test_throws ArgumentError TerminalPager.last(0)
            @test length(TerminalPager._PAGER_HISTORY) == 2
        finally
            Base.eval(:(stdout = $old_stdout))
        end

        # The public entry point records the text only when a session can run.
        try
            Base.eval(:(stdout = $(IOContext(output, :color => false))))
            pager("not recorded")
            @test length(TerminalPager._PAGER_HISTORY) == 2
        finally
            Base.eval(:(stdout = $old_stdout))
        end

        empty!(TerminalPager._PAGER_HISTORY)
        TerminalPager.history(io)
        @test String(take!(io)) == "The pager history is empty.\n"
        @test_throws ArgumentError TerminalPager.last()
    finally
        TerminalPager.drop_preference!("history_size")
        TerminalPager.drop_preference!("history_max_bytes")
        empty!(TerminalPager._PAGER_HISTORY)
    end
end

@testset "History of the Printed Texts" begin
    empty!(TerminalPager._PAGER_HISTORY)

    old_stdout = stdout
    output = IOContext(IOBuffer(), :displaysize => (8, 30), :color => false)
    sessions = Ref(0)

    # The hooks make the session a counter, so that no terminal is needed.
    keywords = (;
        auto = true,
        _display_config_loader = TerminalPager.DisplayConfig,
        _input_factory = stream -> nothing,
        _terminal_factory = () -> nothing,
        _raw_runner = (f, terminal) -> (sessions[] += 1; nothing),
    )

    try
        Base.eval(:(stdout = $output))

        # A text that fits in the display is only printed. Hence, it is not shown by the
        # pager and it must not be recorded in the history.
        for text in ("fits\n", "")
            options = TerminalPager._session_options(keywords)
            TerminalPager._pager(text, options, keywords)
        end

        @test sessions[] == 0
        @test isempty(TerminalPager._PAGER_HISTORY)
        @test String(take!(output.io)) == "fits\n"

        # A text that does not fit starts a session, which is recorded.
        text = join(fill("long line", 40), '\n')
        TerminalPager._pager(text, TerminalPager._session_options(keywords), keywords)

        @test sessions[] == 1
        @test length(TerminalPager._PAGER_HISTORY) == 1
        @test TerminalPager._PAGER_HISTORY[1].text == text
        @test TerminalPager._PAGER_HISTORY[1].options === keywords

        # A session without options for the history is not recorded.
        TerminalPager._pager(text, TerminalPager._session_options(keywords))
        @test sessions[] == 2
        @test length(TerminalPager._PAGER_HISTORY) == 1
    finally
        Base.eval(:(stdout = $old_stdout))
        empty!(TerminalPager._PAGER_HISTORY)
    end
end

@testset "Restore the Viewport and the Search" begin
    lines = ["line $i" for i in 1:30]

    # The viewport is restored and clamped, and the search is applied again.
    pagerd = _create_modal_pagerd(lines, "")
    TerminalPager._restore_state!(
        pagerd, TerminalPager.PagerResult(String[], 12, 3, "line 2")
    )
    @test pagerd.start_row == 12
    @test pagerd.start_column == 1
    @test pagerd.mode == :searching
    @test pagerd.search_pattern == "line 2"
    @test length(pagerd.ordered_search_matches) == 11

    # The restored search behaves like one that was typed: its active match is the first
    # one at or after the top of the view, and it is applied again when the rows change.
    @test pagerd.search_regex isa Regex
    @test pagerd.active_search_match_id == 2
    @test pagerd.ordered_search_matches[2].line == 20
    @test isempty(pagerd.message)

    TerminalPager._apply_filter!(pagerd, r"line 1$|line 20", false, "line 1\$|line 20")
    @test pagerd.num_lines == 2
    @test [m.line for m in pagerd.ordered_search_matches] == [2]

    pagerd = _create_modal_pagerd(lines, "")
    pagerd.frozen_rows = 2
    TerminalPager._restore_state!(pagerd, TerminalPager.PagerResult(String[], 1, 1, "["))
    @test pagerd.start_row == 3
    @test pagerd.mode == :view
    @test isempty(pagerd.search_pattern)

    pagerd = _create_modal_pagerd(lines, "")
    TerminalPager._restore_state!(pagerd, TerminalPager.PagerResult(String[], 99, 1, ""))
    @test pagerd.start_row == 22

    # A session started with a result restores it before the first frame.
    input = IOBuffer("q")
    output = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    result = TerminalPager._pager!(
        term,
        join(lines, '\n');
        input = TerminalPager.PagerInput(input),
        use_alternate_screen_buffer = false,
        _restore = TerminalPager.PagerResult(String[], 7, 1, "@1:4 line"),
    )
    @test result.start_row == 7
    @test result.search_pattern == "@1:4 line"
    @test occursin("SEARCH", String(take!(output)))

    # The result has the line of the text at the top of the view, even if the session quits
    # with a filter, so that the same line is at the top when the text is reopened.
    input = TypedInput("&[05]\$\njjq")
    output = IOContext(IOBuffer(), :displaysize => (5, 40), :color => false)
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    result = TerminalPager._pager!(
        term,
        join(lines, '\n');
        input = TerminalPager.PagerInput(input),
        use_alternate_screen_buffer = false,
    )
    @test result.start_row == 15
    empty!(TerminalPager._FILTER_HISTORY)

    input = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input, output, output)
    reopened = TerminalPager._pager!(
        term,
        join(lines, '\n');
        input = TerminalPager.PagerInput(input),
        use_alternate_screen_buffer = false,
        _restore = result,
    )
    @test reopened.start_row == 15
end

@testset "History Menu and Shortcuts" begin
    empty!(TerminalPager._PAGER_HISTORY)
    TerminalPager._push_pager_history!("first text", (;))
    TerminalPager._push_pager_history!("second text", (;))
    request = (term, menu) -> REPL.TerminalMenus.request(term, menu; suppress_output = true)

    try
        # The menu returns the position of the chosen entry, or zero when it is cancelled.
        term = REPL.Terminals.TTYTerminal("", IOBuffer("\e[B\r"), IOBuffer(), IOBuffer())
        @test TerminalPager._history_menu(term; request = request) == 2
        term = REPL.Terminals.TTYTerminal("", IOBuffer("q"), IOBuffer(), IOBuffer())
        @test TerminalPager._history_menu(term; request = request) == 0

        empty!(TerminalPager._PAGER_HISTORY)
        output = IOBuffer()
        term = REPL.Terminals.TTYTerminal("", IOBuffer("\r"), output, output)
        @test TerminalPager._history_menu(term; request = request) == 0
        @test isempty(take!(output))
    finally
        empty!(TerminalPager._PAGER_HISTORY)
    end

    # The shortcuts are registered in the pager prompt only, not in the main one.
    function create_mode(prompt = "julia> ")
        escapes = Dict{Char, Any}('O' => Dict{Char, Any}())
        return (; prompt = prompt, keymap_dict = Dict{Char, Any}('\e' => escapes))
    end

    regular_mode = create_mode()
    pager_mode = create_mode(TerminalPager._tp_mode_prompt)
    repl = (; interface = (; modes = [regular_mode, pager_mode]))
    fetch(TerminalPager._register_history_shortcuts(repl))

    escapes = pager_mode.keymap_dict['\e']
    @test escapes['l'] === TerminalPager._reopen_last_output
    @test escapes['L'] === TerminalPager._choose_history_entry
    @test !haskey(regular_mode.keymap_dict['\e'], 'l')
    @test !haskey(regular_mode.keymap_dict['\e'], 'L')
end
