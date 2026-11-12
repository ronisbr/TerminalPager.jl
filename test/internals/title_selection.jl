## Description #############################################################################
#
# Tests for the title selection mode. The helpers of the freeze selection tests are reused.
#
############################################################################################

"""
    _run_select_title_rows!(pagerd::TerminalPager.Pager) -> String

Run the title selection event on `pagerd` and return the text sent to the terminal.
"""
function _run_select_title_rows!(pagerd::TerminalPager.Pager)
    pagerd.event = :select_title_rows
    @test TerminalPager._pager_event_process!(pagerd)
    return String(take!(pagerd.term.out_stream))
end

@testset "Title Selection Key Binding and Feature Gate" begin
    k = TerminalPager.Keystroke(; value = "T")
    @test TerminalPager._pager_action(k) === :select_title_rows

    pagerd = _create_redraw_pagerd(_FREEZE_LINES)
    pagerd.features = [:change_freeze]
    TerminalPager._pager_key_process!(pagerd, k)
    @test pagerd.event === :select_title_rows

    pagerd.features = Symbol[]
    TerminalPager._pager_key_process!(pagerd, k)
    @test pagerd.event === nothing
end

@testset "Title Selection Applies the Rows" begin
    # The titles are always frozen, so the frozen rows are raised to them.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, "jj\r"; start_row = 12, start_column = 5, cropped_lines = 3
    )
    output = _run_select_title_rows!(pagerd)

    @test pagerd.title_rows == 2
    @test pagerd.frozen_rows == 2
    @test pagerd.frozen_columns == 0
    @test pagerd.mode === :view
    @test pagerd.message == "2 title rows, frozen rows raised to 2"
    @test pagerd.message_kind === :info
    @test pagerd.visual_mode_line == 1
    @test pagerd.redraw

    # The viewport is restored, and the crop counters are recomputed by the next frame.
    @test pagerd.start_row == 12
    @test pagerd.start_column == 5
    @test pagerd.cropped_lines == 0
    @test pagerd.cropped_columns == 0

    # The status line showed the mode and the live selection, the view started at the
    # top-left corner, and the frozen tag was hidden.
    @test occursin("TITLES", output)
    @test occursin("row 1 v1_1", output)
    @test !occursin("frozen", output)

    # More frozen rows than titles are kept, and the frozen columns are never touched.
    pagerd = _create_freeze_pagerd(
        _FREEZE_LINES, "jj\r"; frozen_rows = 5, frozen_columns = 3, visual_mode_line = 4
    )
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 2
    @test pagerd.frozen_rows == 5
    @test pagerd.frozen_columns == 3
    @test pagerd.visual_mode_line == 4
    @test pagerd.message == "2 title rows"

    # The selection starts at the current title rows, and the restored viewport is clamped
    # to the raised frozen rows.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "j\r"; title_rows = 2, start_row = 1)
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 3
    @test pagerd.frozen_rows == 3
    @test pagerd.start_row == 4

    # The keypad Enter applies the selection as well, and the previous mode is restored.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "j\eOM"; mode = :searching)
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 1
    @test pagerd.mode === :searching
end

@testset "Title Selection Cancels" begin
    for keys in ("jj\e", "jjq", "jj\x03", "jj\x04")
        pagerd = _create_freeze_pagerd(
            _FREEZE_LINES,
            keys;
            start_row = 12,
            start_column = 5,
            frozen_rows = 4,
            frozen_columns = 2,
            title_rows = 1,
            mode = :searching,
        )
        _run_select_title_rows!(pagerd)
        @test pagerd.title_rows == 1
        @test pagerd.frozen_rows == 4
        @test pagerd.frozen_columns == 2
        @test pagerd.start_row == 12
        @test pagerd.start_column == 5
        @test pagerd.mode === :searching
        @test pagerd.message == ""
    end
end

@testset "Title Selection Has No Columns and Stays in the View" begin
    # The horizontal movements and the mouse never select columns.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, ["l", "\$", "\e[<0;7;4M", "\r"])
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 3
    @test pagerd.frozen_rows == 3
    @test pagerd.frozen_columns == 0

    # The rows are bounded by the view, leaving one row for the guide, and by the text.
    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "G\r")
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 8

    pagerd = _create_freeze_pagerd(["a", "b", "c"], "G\r")
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 3

    pagerd = _create_freeze_pagerd(_FREEZE_LINES, "kkkk\r"; title_rows = 2)
    _run_select_title_rows!(pagerd)
    @test pagerd.title_rows == 0
    @test pagerd.message == "0 title rows"

    # An empty text has nothing to select.
    pagerd = _create_freeze_pagerd(String[], "q")
    _run_select_title_rows!(pagerd)
    @test pagerd.message == "Nothing to select"
    @test pagerd.message_kind === :error
end

@testset "Title Guide Rendering" begin
    face = "\e[0;36;1m"
    lines = ["\e[1mabc\e[0mdef", "gh\e[1mijkl\e[0m", "x"]

    # Only the horizontal guide is drawn, and the other rows are kept as they are.
    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    pagerd.mode = :title_selection
    pagerd.freeze_selection_rows = 1
    pagerd.freeze_selection_columns = 3
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test length(rows) == 4
    @test rows[1] == lines[1]
    @test rows[2] == face * "━━━━━━━━━━━━" * "\e[0m"
    @test rows[3] == lines[3]
    @test rows[4] == ""

    # The ruler is kept, and the guide starts after it.
    pagerd.show_ruler = true
    TerminalPager._view!(pagerd)
    rows = split(String(take!(copy(pagerd.buf.io))), '\n')
    @test rows[2] == "\e[0;90m 2 │\e[0m" * face * "━━━━━━━━" * "\e[0m"
end

@testset "Status Line in the Title Mode" begin
    pagerd, output = _create_status_pagerd(_FREEZE_LINES; display_size = (10, 60))
    pagerd.frozen_rows = 2
    pagerd.frozen_columns = 3
    pagerd.mode = :title_selection
    pagerd.freeze_selection_rows = 4

    text = _status_bar_text(pagerd, output)
    @test startswith(text, "TITLES  4")
    @test occursin("Enter:apply  Esc:cancel", text)
    @test !occursin("frozen", text)
    @test textwidth(text) == 60

    # The mode name has the face of the freeze selection.
    pagerd, output = _create_status_pagerd(_FREEZE_LINES; color = true, display_size = (10, 60))
    pagerd.mode = :title_selection
    TerminalPager._redraw_status_bar!(pagerd)
    @test occursin(pagerd.display_config.mode_freeze * "TITLES", String(take!(output)))
end
