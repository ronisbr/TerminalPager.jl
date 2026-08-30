## Description #############################################################################
#
# Tests for the command line editor.
#
############################################################################################

"""
    _read_cmd(input_text::AbstractString; prefix::String = "/") ->
        Tuple{String, String}

Run the command line editor over `input_text` and return the command and the terminal output.

# Arguments

- `input_text::AbstractString`: Keystrokes the editor reads.

# Keywords

- `prefix::String`: Prompt displayed before the command.
    (**Default**: `"/"`)
- `history::Union{Nothing, Vector{String}}`: Commands recalled with the up and down keys.
    (**Default**: `nothing`)
"""
function _read_cmd(input_text::AbstractString; prefix::String = "/", history = nothing)
    pagerd = _create_modal_pagerd(["x", "y"], input_text)
    cmd = TerminalPager._read_cmd!(pagerd; prefix = prefix, history = history)
    return cmd, String(take!(pagerd.term.out_stream))
end

@testset "Command Line Editing" begin
    @test first(_read_cmd("query\n")) == "query"
    @test first(_read_cmd("\n")) == ""

    # Backspace used to truncate the end of the command while moving the cursor, so the string
    # and the cursor disagreed after the first movement.
    @test first(_read_cmd("abc\x7f\n")) == "ab"
    @test first(_read_cmd("abc\e[D\e[D\x7f\n")) == "bc"
    @test first(_read_cmd("abc\e[D\x7f\n")) == "ac"

    # Backspace on an empty command still leaves the editor.
    @test first(_read_cmd("\x7f")) == ""

    # Insertion must honor the cursor.
    @test first(_read_cmd("abc\e[D\e[DX\n")) == "aXbc"
    @test first(_read_cmd("abc\e[HX\n")) == "Xabc"
    @test first(_read_cmd("abc\e[H\e[FX\n")) == "abcX"

    # Moving beyond either end must be a no-op.
    @test first(_read_cmd("ab\e[D\e[D\e[D\e[DX\n")) == "Xab"
    @test first(_read_cmd("ab\e[C\e[C\e[CX\n")) == "abX"

    # Delete removes the character under the cursor.
    @test first(_read_cmd("abc\e[H\e[3~\n")) == "bc"
    @test first(_read_cmd("abc\e[3~\n")) == "abc"
end

@testset "Command Line Ignores Non-Printable Keys" begin
    # These used to be inserted verbatim, so a search for `x` after pressing the up arrow
    # looked for `<up>x`. They also desynchronized the length bookkeeping, after which a
    # backspace truncated an arbitrary amount of text.
    for (name, code) in (
        ("<up>", "\e[A"),
        ("<down>", "\e[B"),
        ("<pageup>", "\e[5~"),
        ("<F1>", "\eOP"),
        ("<tab>", "\t"),
    )
        cmd, _ = _read_cmd("ab" * code * "c\n")
        @test cmd == "abc"
        @test !occursin(name, cmd)
    end

    # A special key followed by a backspace must delete exactly one character.
    @test first(_read_cmd("ab\e[A\x7f\n")) == "a"

    # ALT and CTRL combinations must not be inserted either.
    @test !TerminalPager._is_printable_keystroke(
        TerminalPager.Keystroke(; value = "a", alt = true)
    )
    @test !TerminalPager._is_printable_keystroke(
        TerminalPager.Keystroke(; value = "a", ctrl = true)
    )
    @test TerminalPager._is_printable_keystroke(TerminalPager.Keystroke(; value = "a"))
    @test TerminalPager._is_printable_keystroke(TerminalPager.Keystroke(; value = " "))
    @test TerminalPager._is_printable_keystroke(TerminalPager.Keystroke(; value = "界"))
    @test !TerminalPager._is_printable_keystroke(TerminalPager.Keystroke(; value = "<up>"))
    @test !TerminalPager._is_printable_keystroke(TerminalPager.Keystroke(; value = ""))
end

@testset "Command Line Does Not Wrap the Screen" begin
    # A command wider than the terminal used to wrap the last row, scrolling the whole
    # screen while the frame snapshot still described the old rows. The rendered command is
    # now truncated at the right edge, while the edited command keeps every character.
    pagerd = _create_modal_pagerd(["x", "y"], repeat("x", 60) * "\n")
    pagerd.display_size = (10, 40)

    cmd = TerminalPager._read_cmd!(pagerd)
    output = String(take!(pagerd.term.out_stream))

    @test cmd == repeat("x", 60)

    # The prompt occupies column 1, so at most 39 characters fit on the row.
    @test maximum(m -> length(m.match), eachmatch(r"x+", output)) == 39

    # A wide character that does not fit entirely must not be painted at all.
    pagerd = _create_modal_pagerd(["x", "y"], "ab界\n")
    pagerd.display_size = (10, 4)

    cmd = TerminalPager._read_cmd!(pagerd)
    output = String(take!(pagerd.term.out_stream))

    @test cmd == "ab界"
    @test !occursin("界", output)
end

@testset "Status Bar Redraw Clears the Row" begin
    # On a terminal too narrow for the hints, they are not written. Without an explicit
    # clear, the text left behind by the command editor persisted on the command line.
    pagerd = _create_modal_pagerd(["x", "y"], "")
    pagerd.display_size = (10, 19)
    pagerd.features = [:help]

    TerminalPager._redraw_status_bar!(pagerd)
    output = String(take!(pagerd.term.out_stream))

    @test occursin("\e[10;1H\e[0K", output)
    @test occursin("All", output)
    @test !occursin("quit", output)
end

@testset "Command Line Cursor Column" begin
    # The column is a display width, not a character count. A wide character advances the
    # cursor by two columns.
    @test TerminalPager._cmd_cursor_column(Char[], 1, 1, 80) == 2
    @test TerminalPager._cmd_cursor_column(collect("abc"), 1, 1, 80) == 2
    @test TerminalPager._cmd_cursor_column(collect("abc"), 4, 1, 80) == 5
    @test TerminalPager._cmd_cursor_column(collect("界界"), 3, 1, 80) == 6
    @test TerminalPager._cmd_cursor_column(collect("a界b"), 4, 1, 80) == 6

    # A longer prompt shifts everything to the right.
    @test TerminalPager._cmd_cursor_column(collect("ab"), 3, 10, 80) == 13

    # A command longer than the display must not move the cursor off the command line.
    @test TerminalPager._cmd_cursor_column(collect(repeat("x", 100)), 101, 1, 40) == 40

    # A wide command must place the cursor under the insertion point. The prompt occupies
    # column 1, the first `界` columns 2 and 3, and the second one columns 4 and 5. Hence,
    # inserting before the second `界` happens at column 4.
    cmd, output = _read_cmd("界界\e[D\n")
    @test cmd == "界界"
    @test endswith(output, "\e[10;4H\e[?25l")
end

@testset "Command Line Cancel" begin
    # ESC used to be ignored, so the only ways to leave the prompt were Enter and Backspace on
    # an empty command.
    @test isnothing(first(_read_cmd("ab\e")))
    @test isnothing(first(_read_cmd("\e")))

    # The raw mode delivers CTRL-C as a keystroke, which cancels the prompt as well.
    @test isnothing(first(_read_cmd("ab\x03")))

    # Cancelling the search prompt keeps the view mode and records no match.
    pagerd = _create_modal_pagerd(["line"], "li\e")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :view
    @test isempty(pagerd.ordered_search_matches)

    # Cancelling the frozen rows prompt skips the frozen columns prompt as well.
    pagerd = _create_modal_pagerd(["line"], "\e")
    pagerd.features = [:change_freeze]
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test (pagerd.frozen_rows, pagerd.frozen_columns) == (0, 0)
    output = String(take!(pagerd.term.out_stream))
    @test occursin("Frozen rows", output)
    @test !occursin("Frozen columns", output)
end

@testset "Command Line Messages" begin
    pagerd = _create_modal_pagerd(["x"], "")
    pagerd.redraw = false
    TerminalPager._set_message!(pagerd, "3 lines copied")
    @test pagerd.redraw
    @test pagerd.message_kind === :info
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin("3 lines copied", String(take!(pagerd.term.out_stream)))

    # The message is removed by the next keystroke, and the key hints are back.
    pagerd.redraw = false
    TerminalPager._clear_message!(pagerd)
    @test pagerd.redraw
    @test isempty(pagerd.message)
    TerminalPager._redraw_status_bar!(pagerd)
    output = String(take!(pagerd.term.out_stream))
    @test !occursin("3 lines copied", output)
    @test occursin("q:quit", output)

    # Clearing without a message does not request a redraw.
    pagerd.redraw = false
    TerminalPager._clear_message!(pagerd)
    @test !pagerd.redraw

    # An invalid number leaves a message instead of consuming the next keystroke.
    pagerd = _create_modal_pagerd(["x"], "bad\nq")
    @test TerminalPager._prompt_number!(pagerd, "Rows", 0) == (:invalid, 0)
    @test pagerd.message == "Not a number: bad"
    @test pagerd.message_kind === :error
    @test TerminalPager._read_keystroke!(pagerd.input).value == "q"
end

@testset "Prompt Styling and Feedback" begin
    # The prompts show the current value in brackets, and the freeze events confirm the new
    # values with a message.
    pagerd = _create_modal_pagerd(["a", "b", "c"], "2\n1\n")
    pagerd.features = [:change_freeze]
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    output = String(take!(pagerd.term.out_stream))
    @test occursin("Frozen rows [0] › ", output)
    @test occursin("Frozen columns [0] › ", output)
    @test pagerd.message == "Frozen 2 rows × 1 columns"
    @test pagerd.message_kind === :info

    pagerd = _create_modal_pagerd(["a", "b", "c"], "1\n")
    pagerd.features = [:change_freeze]
    pagerd.event = :change_title_rows
    @test TerminalPager._pager_event_process!(pagerd)
    @test occursin("Title rows [0] › ", String(take!(pagerd.term.out_stream)))
    @test pagerd.message == "1 title rows"
end

@testset "Command Line Editing Keys" begin
    # CTRL-U clears the command, CTRL-A and CTRL-E jump to its ends, CTRL-W deletes the word
    # before the cursor, and CTRL-H is a backspace on terminals that send it for the key.
    @test first(_read_cmd("abc\x15xy\n")) == "xy"
    @test first(_read_cmd("abc\x01X\n")) == "Xabc"
    @test first(_read_cmd("abc\x01X\x05Y\n")) == "XabcY"
    @test first(_read_cmd("foo bar\x17\n")) == "foo "
    @test first(_read_cmd("foo bar  \x17\n")) == "foo "
    @test first(_read_cmd("foo bar\e[D\e[D\x17\n")) == "foo ar"
    @test first(_read_cmd("\x17\n")) == ""
    @test first(_read_cmd("abc\x08\n")) == "ab"
    @test first(_read_cmd("\x08")) == ""
end

@testset "Command Line History" begin
    history = ["one", "two"]

    # The up key recalls the newest entry first and stops at the oldest one.
    @test first(_read_cmd("\e[A\n"; history = history)) == "two"
    @test first(_read_cmd("\e[A\e[A\n"; history = history)) == "one"
    @test first(_read_cmd("\e[A\e[A\e[A\n"; history = history)) == "one"

    # The down key goes back to the newest entry and then to the command typed before.
    @test first(_read_cmd("x\e[A\e[A\e[B\e[B\n"; history = history)) == "x"
    @test first(_read_cmd("x\e[A\e[B\n"; history = history)) == "x"
    @test first(_read_cmd("\e[B\n"; history = history)) == ""

    # A recalled entry can be edited, and the history itself is not modified.
    @test first(_read_cmd("\e[A\x7f\x7fen\n"; history = history)) == "ten"
    @test history == ["one", "two"]

    # Without a history, the up and down keys are ignored.
    @test first(_read_cmd("a\e[A\e[Bb\n")) == "ab"

    # The history keeps one copy of each entry, the newest last, and is bounded.
    entries = String[]
    TerminalPager._push_history!(entries, "a")
    TerminalPager._push_history!(entries, "b")
    TerminalPager._push_history!(entries, "a")
    TerminalPager._push_history!(entries, "")
    @test entries == ["b", "a"]

    for i in 1:(TerminalPager._MAX_HISTORY + 10)
        TerminalPager._push_history!(entries, string(i))
    end
    @test length(entries) == TerminalPager._MAX_HISTORY
    @test entries[end] == string(TerminalPager._MAX_HISTORY + 10)

    # A confirmed search pattern is recorded, an invalid one is not.
    empty!(TerminalPager._SEARCH_HISTORY)
    pagerd = _create_modal_pagerd(["line one", "line two"], "line\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test TerminalPager._SEARCH_HISTORY == ["line"]

    pagerd = _create_modal_pagerd(["line one", "line two"], "[\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test TerminalPager._SEARCH_HISTORY == ["line"]

    # The recalled pattern is searched again.
    pagerd = _create_modal_pagerd(["line one", "line two"], "\e[A\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching
    @test length(pagerd.ordered_search_matches) == 2
    empty!(TerminalPager._SEARCH_HISTORY)
end

@testset "Command Line Change Callback" begin
    # The callback runs whenever the text changes, not when only the cursor moves, and its
    # result is shown at the right of the prompt row.
    calls = String[]
    pagerd = _create_modal_pagerd(["x"], "ab\e[D\e[Dc\x7f\x15z\n")
    cmd = TerminalPager._read_cmd!(pagerd; on_change = text -> (push!(calls, text); "S:" * text))
    @test cmd == "z"
    @test calls == ["a", "ab", "cab", "ab", "", "z"]
    output = String(take!(pagerd.term.out_stream))
    @test occursin("S:ab", output)
    @test endswith(replace(output, r"\e\[[0-9;?]*[A-Za-z]" => ""), "/z" * " "^35 * "S:z")

    # A status that does not fit the row is not shown.
    pagerd = _create_modal_pagerd(["x"], "a\n")
    pagerd.display_size = (10, 6)
    TerminalPager._read_cmd!(pagerd; on_change = text -> "too long")
    @test !occursin("too long", String(take!(pagerd.term.out_stream)))
end

@testset "Go To Line" begin
    lines = ["line $i" for i in 1:30]
    k = TerminalPager.Keystroke(; value = ":")
    @test TerminalPager._pager_action(k) === :goto_line

    pagerd = _create_modal_pagerd(lines, "25\n")
    @test TerminalPager._pager_key_process!(pagerd, k) === :goto_line
    @test pagerd.event === :goto_line
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.start_row == 25
    @test pagerd.redraw
    @test occursin("\e[0K\e[?25h:25", String(take!(pagerd.term.out_stream)))

    # The line is clamped to the text and never enters the frozen rows.
    for (input, frozen_rows, expected) in
        (("0\n", 0, 1), ("99\n", 0, 30), ("1\n", 2, 3), ("-5\n", 0, 1))
        pagerd = _create_modal_pagerd(lines, input)
        pagerd.frozen_rows = frozen_rows
        pagerd.start_row = frozen_rows + 1
        pagerd.event = :goto_line
        @test TerminalPager._pager_event_process!(pagerd)
        @test pagerd.start_row == expected
    end

    # Cancelling, an empty number, or an invalid one keeps the position.
    for input in ("\e", "\n", "abc\n")
        pagerd = _create_modal_pagerd(lines, input)
        pagerd.start_row = 7
        pagerd.event = :goto_line
        @test TerminalPager._pager_event_process!(pagerd)
        @test pagerd.start_row == 7
    end
    @test pagerd.message == "Not a number: abc"
end
