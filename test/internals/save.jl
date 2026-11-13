## Description #############################################################################
#
# Tests for saving the text to a file.
#
############################################################################################

@testset "Save to a File" begin
    lines = ["first", "\e[31mred\e[0m", "third"]
    @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "S")) === :save

    mktempdir() do dir
        try
            # The whole text is saved without the decorations.
            path = joinpath(dir, "out.txt")
            pagerd = _create_modal_pagerd(lines, path * "\n")
            pagerd.redraw = false
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test read(path, String) == "first\nred\nthird\n"
            @test pagerd.message == "3 lines saved to $path"
            @test pagerd.message_kind === :info
            @test pagerd.redraw
            @test TerminalPager._SAVE_HISTORY == [path]
            @test occursin("Save to › ", String(take!(pagerd.term.out_stream)))

            # A leading `!` keeps the decorations, and the selection is saved in the visual
            # mode.
            decorated = joinpath(dir, "decorated.txt")
            pagerd = _create_modal_pagerd(lines, "!" * decorated * "\n")
            pagerd.features = [:visual_mode]
            pagerd.visual_mode = true
            pagerd.visual_mode_line = 2
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test read(decorated, String) == "\e[31mred\e[0m\n"
            @test pagerd.message == "1 line saved to $decorated"

            pagerd = _create_modal_pagerd(lines, joinpath(dir, "range.txt") * "\n")
            pagerd.features = [:visual_mode]
            pagerd.visual_mode = true
            pagerd.visual_anchor = 1
            pagerd.visual_mode_line = 2
            push!(pagerd.visual_mode_selected_lines, 3)
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test read(joinpath(dir, "range.txt"), String) == "first\nred\nthird\n"

            # An existing file is overwritten only after a confirmation.
            pagerd = _create_modal_pagerd(["new"], path * "\nn")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test read(path, String) == "first\nred\nthird\n"
            @test pagerd.message == "Save cancelled"
            @test occursin("Overwrite $path? (y/n)", String(take!(pagerd.term.out_stream)))

            pagerd = _create_modal_pagerd(["new"], path * "\ny")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test read(path, String) == "new\n"

            # Cancelling or an empty path saves nothing.
            for input in ("\e", "\n", "   \n", "!\n")
                pagerd = _create_modal_pagerd(["new"], input)
                pagerd.event = :save
                @test TerminalPager._pager_event_process!(pagerd)
                @test isempty(pagerd.message)
            end
            @test readdir(dir) == ["decorated.txt", "out.txt", "range.txt"]

            # The errors of the file system are reported.
            pagerd = _create_modal_pagerd(lines, joinpath(dir, "missing", "x.txt") * "\n")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test pagerd.message == "Could not save: No such file or directory"
            @test pagerd.message_kind === :error

            pagerd = _create_modal_pagerd(lines, dir * "\ny")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test startswith(pagerd.message, "Could not save: ")
            @test pagerd.message_kind === :error

            # An empty text has nothing to save.
            pagerd = _create_modal_pagerd(String[], joinpath(dir, "empty.txt") * "\n")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test pagerd.message == "Nothing to save"
            @test !isfile(joinpath(dir, "empty.txt"))

            # The tilde is expanded.
            if !Sys.iswindows()
                withenv("HOME" => dir) do
                    pagerd = _create_modal_pagerd(lines, "~/home.txt\n")
                    pagerd.event = :save
                    @test TerminalPager._pager_event_process!(pagerd)
                    @test read(joinpath(dir, "home.txt"), String) == "first\nred\nthird\n"
                end
            end
        finally
            empty!(TerminalPager._SAVE_HISTORY)
        end
    end

    @test TerminalPager._assemble_yank_text(lines, [2]; keep_decorations = true) ==
        ("\e[31mred\e[0m\n", 1)
end

@testset "Save Errors" begin
    # A path that cannot be expanded or accessed is reported instead of throwing.
    for path in ("~no_such_user_of_terminal_pager/out.txt", "/" * "x"^300 * "/out.txt")
        pagerd = _create_modal_pagerd(["a", "b"], path * "\n")
        pagerd.event = :save
        @test TerminalPager._pager_event_process!(pagerd)
        @test startswith(pagerd.message, "Could not save: ")
        @test pagerd.message_kind === :error
    end

    try
        mktempdir() do dir
            pagerd = _create_modal_pagerd(["a"], joinpath(dir, "missing", "out.txt") * "\n")
            pagerd.event = :save
            @test TerminalPager._pager_event_process!(pagerd)
            @test startswith(pagerd.message, "Could not save: ")
            @test pagerd.message_kind === :error
        end
    finally
        empty!(TerminalPager._SAVE_HISTORY)
    end
end
