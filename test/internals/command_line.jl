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
"""
function _read_cmd(input_text::AbstractString; prefix::String = "/")
    pagerd = _create_modal_pagerd(["x", "y"], input_text)
    cmd = TerminalPager._read_cmd!(pagerd; prefix = prefix)
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
    @test endswith(output, "\e[10;4H")
end
