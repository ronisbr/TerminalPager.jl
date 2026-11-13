## Description #############################################################################
#
# Tests for opening the text in the editor.
#
############################################################################################

@testset "Open in the Editor" begin
    lines = ["first", "\e[31mred\e[0m", "third", "fourth"]
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "e")) === :edit

    calls = Tuple{String, String, Int}[]
    recorder = (path, line) -> (push!(calls, (path, read(path, String), line)); nothing)
    old_editor = TerminalPager._EDITOR[]

    try
        TerminalPager._EDITOR[] = recorder

        # The whole text is written without the decorations, the editor opens at the top
        # row, and the terminal modes are left and entered again. The file is kept until
        # the session ends, because many editors return before they open it.
        pagerd = _create_modal_pagerd(lines, "")
        modes = pagerd.terminal_modes
        modes.cursor_key_mode = true
        modes.alternate_screen = true
        modes.cursor_hidden = true
        modes.mouse = true
        pagerd.start_row = 3
        pagerd.frame_cache.valid = true
        pagerd.redraw = false
        pagerd.event = :edit
        @test TerminalPager._pager_event_process!(pagerd)
        @test length(calls) == 1
        @test calls[1][2] == "first\nred\nthird\nfourth\n"
        @test calls[1][3] == 3
        @test isfile(calls[1][1])
        @test pagerd.temporary_files == [calls[1][1]]
        TerminalPager._remove_temporary_files!(pagerd)
        @test !isfile(calls[1][1])
        @test isempty(pagerd.temporary_files)
        @test !pagerd.frame_cache.valid
        @test pagerd.redraw
        @test isempty(pagerd.message)

        output = String(take!(pagerd.term.out_stream))
        leave = "\e[?1006l\e[?1000l\e[?25h\e[?1049l\e[?1l"
        enter = "\e[?1h\e[?1049h\e[?25l\e[?1000h\e[?1006h"
        @test occursin(leave, output)
        @test occursin(enter, output)
        @test findfirst(leave, output).stop < findfirst(enter, output).start
        @test modes.cursor_key_mode && modes.alternate_screen
        @test modes.cursor_hidden && modes.mouse

        # In the visual mode, the selection is opened at the visual line.
        empty!(calls)
        pagerd = _create_modal_pagerd(lines, "")
        pagerd.features = [:visual_mode]
        pagerd.visual_mode = true
        pagerd.visual_mode_line = 3
        push!(pagerd.visual_mode_selected_lines, 1)
        pagerd.event = :edit
        @test TerminalPager._pager_event_process!(pagerd)
        @test calls[1][2] == "first\nthird\n"
        @test calls[1][3] == 2

        # Without the alternate screen buffer, the screen is cleared when the modes are
        # entered again.
        empty!(calls)
        pagerd = _create_modal_pagerd(lines, "")
        pagerd.terminal_modes.cursor_hidden = true
        pagerd.event = :edit
        @test TerminalPager._pager_event_process!(pagerd)
        clear = IOBuffer()
        TerminalPager._clear_screen(clear)
        output = String(take!(pagerd.term.out_stream))
        @test occursin("\e[0m\e[0K\e[?25h", output)
        @test occursin(String(take!(clear)) * "\e[?25l", output)

        # An editor that throws leaves a message, enters the modes again, and removes the
        # file.
        TerminalPager._EDITOR[] = (path, line) -> error("no editor")
        pagerd = _create_modal_pagerd(lines, "")
        pagerd.terminal_modes.alternate_screen = true
        pagerd.event = :edit
        @test TerminalPager._pager_event_process!(pagerd)
        @test pagerd.message == "Could not open the editor: no editor"
        @test pagerd.message_kind === :error
        @test occursin("\e[?1049l", String(take!(pagerd.term.out_stream)))

        # An empty text has nothing to edit.
        TerminalPager._EDITOR[] = recorder
        empty!(calls)
        pagerd = _create_modal_pagerd(String[], "")
        pagerd.event = :edit
        @test TerminalPager._pager_event_process!(pagerd)
        @test pagerd.message == "Nothing to edit"
        @test isempty(calls)
    finally
        TerminalPager._EDITOR[] = old_editor
    end
end

@testset "Terminal Modes" begin
    # The modes are recorded as they are enabled and undone in the reverse order.
    modes = TerminalPager.TerminalModes()
    io = IOBuffer()
    TerminalPager._enter_terminal_modes!(
        modes, io; cursor_key_mode = true, alternate_screen = true, hide_cursor = true,
        mouse = false,
    )
    @test String(take!(io)) == "\e[?1h\e[?1049h\e[?25l"
    @test modes.cursor_key_mode && modes.alternate_screen && modes.cursor_hidden
    @test !modes.mouse

    TerminalPager._leave_terminal_modes!(modes, io)
    @test String(take!(io)) == "\e[?25h\e[?1049l\e[?1l"
    @test modes.cursor_key_mode && modes.alternate_screen && modes.cursor_hidden

    # The raw mode is not touched on a terminal reading from a buffer.
    term = REPL.Terminals.TTYTerminal("", IOBuffer(), io, io)
    @test isnothing(TerminalPager._set_raw_mode!(term, true))
end

@testset "File of the Editor Removed With the Session" begin
    paths = String[]
    kept = Bool[]
    old_editor = TerminalPager._EDITOR[]

    try
        # This editor returns right away, like the ones that open a window. Each time it is
        # called, it records whether the files of the previous calls still exist.
        TerminalPager._EDITOR[] = (path, line) -> begin
            push!(paths, path)
            push!(kept, all(isfile, paths))
            return nothing
        end

        input = TypedInput("ejeq")
        output = IOContext(IOBuffer(), :displaysize => (10, 40), :color => false)
        term = REPL.Terminals.TTYTerminal("", input, output, output)

        TerminalPager._pager!(
            term,
            "first\nsecond\nthird";
            input = TerminalPager.PagerInput(input),
            use_alternate_screen_buffer = false,
        )

        # The files are kept after the editor returns, and they are removed when the
        # session ends.
        @test length(paths) == 2
        @test paths[1] != paths[2]
        @test kept == [true, true]
        @test !any(isfile, paths)
    finally
        TerminalPager._EDITOR[] = old_editor
        foreach(path -> rm(path; force = true), paths)
    end
end
