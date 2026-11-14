## Description #############################################################################
#
# Tests for the highlight and the on-screen selection of the columns that restrict a search.
#
############################################################################################

# Six lines with 56 columns, which are wider than the display: `row i` and ten values, each
# one starting five columns after the previous one, the first at the column 7.
const _COLUMN_LINES = ["row $i " * join(("v$(i)_$j" for j in 1:10), " ") for i in 1:6]

# Background of the default face `search_columns`.
const _COLUMN_BACKGROUND = "\e[100m"

"""
    _run_search!(pagerd::TerminalPager.Pager) -> String

Run the search event on `pagerd` and return the text sent to the terminal.
"""
function _run_search!(pagerd::TerminalPager.Pager)
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    empty!(TerminalPager._SEARCH_HISTORY)
    return String(take!(pagerd.term.out_stream))
end

"""
    _highlighted_row(line::String, cells::UnitRange{Int}, ruler_width::Int = 0) -> String

Return the view row `line` with the background `"100"` drawn on `cells`, counted after the
`ruler_width` columns of the ruler.
"""
function _highlighted_row(line::String, cells::UnitRange{Int}, ruler_width::Int = 0)
    out = IOBuffer()
    TerminalPager._draw_highlighted_columns_row!(out, line, cells, ruler_width, "100")
    return String(take!(out))
end

"""
    _view_rows(pagerd::TerminalPager.Pager) -> Vector{String}

Render the view of `pagerd` and return its rows.
"""
function _view_rows(pagerd::TerminalPager.Pager)
    TerminalPager._view!(pagerd)
    return String.(split(String(take!(copy(pagerd.buf.io))), '\n'))
end

"""
    _highlighted_cells(row::AbstractString) -> UnitRange{Int}

Return the cells of the rendered `row` drawn with the background of the face
`search_columns`, or an empty range if there is none.
"""
function _highlighted_cells(row::AbstractString)
    column = 0
    first_cell = 0
    last_cell = 0
    active = false
    index = 1

    # Account for the text before each escape sequence, and then apply the sequence.
    function advance!(stop::Int)
        width = textwidth(row[index:stop])

        if active && (width > 0)
            (first_cell == 0) && (first_cell = column + 1)
            last_cell = column + width
        end

        column += width
        return nothing
    end

    for m in eachmatch(r"\e\[([0-9;]*)([A-Za-z])", row)
        advance!(prevind(row, m.offset))
        index = m.offset + ncodeunits(m.match)
        m[2] == "m" || continue

        # A reset and every other background end the one of the face.
        for parameter in split(m[1], ';')
            if parameter == "100"
                active = true
            elseif (parameter in ("", "0", "48", "49")) || occursin(r"^4[0-7]$", parameter)
                active = false
            end
        end
    end

    advance!(lastindex(row))

    return first_cell == 0 ? (1:0) : (first_cell:last_cell)
end

@testset "Typed Column Range" begin
    # The range is recognized before the blank that ends it, with open bounds.
    @test TerminalPager._typed_columns("@12:20") == 12:20
    @test TerminalPager._typed_columns("@12:20 x y") == 12:20
    @test TerminalPager._typed_columns("@12") == 12:typemax(Int)
    @test TerminalPager._typed_columns("@12:") == 12:typemax(Int)
    @test TerminalPager._typed_columns("@:20") == 1:20

    # No range, an invalid range, and an input that is not a range are empty.
    @test isempty(TerminalPager._typed_columns(""))
    @test isempty(TerminalPager._typed_columns("abc"))
    @test isempty(TerminalPager._typed_columns("@"))
    @test isempty(TerminalPager._typed_columns("@:"))
    @test isempty(TerminalPager._typed_columns("@ x"))
    @test isempty(TerminalPager._typed_columns("@12:2"))
    @test isempty(TerminalPager._typed_columns("@0"))
    @test isempty(TerminalPager._typed_columns("@12x"))
    @test isempty(TerminalPager._typed_columns("@99999999999999999999"))

    # The selected range replaces the typed one and keeps the pattern.
    @test TerminalPager._replace_typed_columns("@", 3:6) == "@3:6 "
    @test TerminalPager._replace_typed_columns("@12", 3:6) == "@3:6 "
    @test TerminalPager._replace_typed_columns("@12:20 ", 3:6) == "@3:6 "
    @test TerminalPager._replace_typed_columns("@12:20 a b", 3:6) == "@3:6 a b"
    @test TerminalPager._replace_typed_columns("@:20 a", 1:1) == "@1:1 a"
    @test TerminalPager._replace_typed_columns("@foo", 3:6) == "@3:6 foo"
end

@testset "Columns and View Cells" begin
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    cells(columns; title = false) = TerminalPager._view_cells(pagerd, columns, 40, title)
    column(cell; title = false) = TerminalPager._text_column(pagerd, cell, 40, title)

    # Without scrolling, the cells are the columns, cut at the edge of the view.
    @test cells(3:6) == 3:6
    @test cells(30:typemax(Int)) == 30:40
    @test isempty(cells(41:50))
    @test isempty(cells(1:0))
    @test column(3) == 3

    # The scrolled view shows the columns from the first visible one.
    pagerd.start_column = 5
    @test cells(3:6) == 1:2
    @test cells(5:5) == 1:1
    @test isempty(cells(1:4))
    @test cells(12:typemax(Int)) == 8:40
    @test column(1) == 5
    @test column(8) == 12

    # The frozen columns are the first cells, and the columns hidden between them and the
    # first visible one have no cell.
    pagerd.frozen_columns = 2
    @test cells(1:2) == 1:2
    @test cells(1:6) == 1:4
    @test isempty(cells(3:4))
    @test cells(4:5) == 3:3
    @test column(2) == 2
    @test column(3) == 5

    # A title row is not scrolled.
    @test cells(3:6; title = true) == 3:6
    @test cells(30:typemax(Int); title = true) == 30:40
    @test column(3; title = true) == 3

    # Every column is the column of its cell.
    for c in vcat(1:2, 5:42)
        cell = only(cells(c:c))
        @test column(cell) == c
    end
end

@testset "Highlighted Columns of a Row" begin
    background = _COLUMN_BACKGROUND

    # The cells get the background, which is removed for the rest of the row.
    @test _highlighted_row("abcdef", 2:3) == "a" * background * "bc\e[49m\e[0mdef"
    @test _highlighted_row("NNNNabcdef", 2:3, 4) ==
        "NNNNa" * background * "bc\e[49m\e[0mdef"

    # A row that ends before the cells, or that is empty, is padded up to them.
    @test _highlighted_row("ab", 4:5) == "ab " * background * "  \e[49m\e[0m"
    @test _highlighted_row("", 2:3, 4) == "     " * background * "  \e[49m\e[0m"

    # The text with its own background keeps it, and the decorations in effect before the
    # cells still apply inside and after them.
    @test _highlighted_row("\e[44mabcdef\e[0m", 2:3) ==
        "\e[44ma" * background * "\e[44mbc\e[0m\e[44mdef\e[0m"
    @test _highlighted_row("\e[31mabcdef", 2:3) ==
        "\e[31ma" * background * "\e[31mbc\e[49m\e[0m\e[31mdef"

    # A decoration that ends inside the cells does not reach the rest of the row.
    row = _highlighted_row("a\e[1mbcd\e[0mef", 3:4)
    @test row == "a\e[1mb" * background * "\e[1mcd\e[0m\e[0m\e[0mef"

    # The printable text never changes, but for the padding.
    for (line, cells) in (("abcdef", 2:3), ("\e[44mabcdef\e[0m", 1:6), ("ab", 4:5))
        text = TerminalPager.remove_decorations(_highlighted_row(line, cells))
        plain = TerminalPager.remove_decorations(line)
        @test text == rpad(plain, max(length(plain), last(cells)))
    end
end

@testset "Highlighted Columns of the View" begin
    lines = ["\e[1mabc\e[0mdef", "gh\e[1mijkl\e[0m", "x"]
    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    plain = _view_rows(pagerd)

    # The columns are drawn on every row of the view, including the short rows and the rows
    # after the end of the text.
    pagerd.highlighted_columns = 2:3
    rows = _view_rows(pagerd)
    @test length(rows) == 4
    @test all(row -> _highlighted_cells(row) == 2:3, rows)
    @test rows[2] == "g" * _COLUMN_BACKGROUND * "h\e[1mi\e[49m\e[0m\e[1mjkl\e[0m"
    @test rows[3] == "x" * _COLUMN_BACKGROUND * "  \e[49m\e[0m"
    @test rows[4] == " " * _COLUMN_BACKGROUND * "  \e[49m\e[0m"
    @test TerminalPager.remove_decorations(rows[1]) == "abcdef"

    # The columns end at the widest line of the text, even if the range is open.
    pagerd.highlighted_columns = 5:typemax(Int)
    @test all(row -> _highlighted_cells(row) == 5:6, _view_rows(pagerd))

    # Columns outside the view draw nothing.
    pagerd.highlighted_columns = 20:30
    @test _view_rows(pagerd) == plain[1:3]

    # The line-number ruler shifts the cells, and the scrollbar is kept on every row.
    pagerd.highlighted_columns = 2:3
    pagerd.show_ruler = true
    pagerd.show_scrollbar = true
    ruler_width = TerminalPager._ruler_width(pagerd)
    rows = _view_rows(pagerd)
    @test length(rows) == 4
    @test _highlighted_cells(rows[1]) == (ruler_width + 2):(ruler_width + 3)
    @test all(row -> occursin("\e[12G", row), rows)

    # The scrolled view draws the cells that show the columns.
    pagerd.show_ruler = false
    pagerd.show_scrollbar = false
    pagerd.display_size = (5, 4)
    pagerd.start_column = 3
    pagerd.highlighted_columns = 3:4
    @test _highlighted_cells(_view_rows(pagerd)[1]) == 1:2

    # A title row is not scrolled, so that its columns are drawn in other cells.
    pagerd.title_rows = 1
    pagerd.frozen_rows = 1
    rows = _view_rows(pagerd)
    @test _highlighted_cells(rows[1]) == 3:4
    @test _highlighted_cells(rows[2]) == 1:2

    # A face without a background draws nothing.
    pagerd = _create_redraw_pagerd(lines; display_size = (5, 12), color = true)
    pagerd.display_config = TerminalPager._display_config() do name
        name === :search_columns ? TerminalPager.Face() : TerminalPager._default_face(name)
    end
    pagerd.highlighted_columns = 2:3
    @test isempty(TerminalPager._highlighted_columns(pagerd))
    @test _view_rows(pagerd) == plain[1:3]
end

@testset "Highlighted Columns on the Column Ruler" begin
    pagerd = _create_redraw_pagerd(_COLUMN_LINES; display_size = (10, 40), color = true)
    pagerd.show_column_ruler = true
    plain = _view_rows(pagerd)

    # Both rows of the ruler mark the cells of the columns, and nothing else changes.
    pagerd.highlighted_columns = 7:10
    rows = _view_rows(pagerd)
    @test _highlighted_cells(rows[1]) == 7:10
    @test _highlighted_cells(rows[2]) == 7:10
    @test TerminalPager.remove_decorations.(rows[1:8]) ==
        TerminalPager.remove_decorations.(plain)

    # The row after the end of the text only carries the columns.
    @test length(rows) == 9
    @test _highlighted_cells(rows[9]) == 7:10

    # The marks follow the scrolled columns, like the numbers do.
    pagerd.start_column = 5
    rows = _view_rows(pagerd)
    @test _highlighted_cells(rows[1]) == 3:6
    @test _highlighted_cells(rows[3]) == 3:6

    # A terminal without colors has a ruler without decorations.
    pagerd = _create_redraw_pagerd(_COLUMN_LINES; display_size = (10, 40))
    pagerd.show_column_ruler = true
    pagerd.highlighted_columns = 7:10
    rows = _view_rows(pagerd)
    @test !occursin('\e', rows[1])
    @test !occursin('\e', rows[2])
    @test _highlighted_cells(rows[3]) == 7:10
end

@testset "Columns Highlighted While the Range Is Typed" begin
    # The columns are highlighted as soon as the range is typed, before its pattern.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:10")
    seen = UnitRange{Int}[]
    preview = pattern -> (push!(seen, pagerd.highlighted_columns); "")
    @test_throws EOFError TerminalPager._prompt_pattern!(
        preview, pagerd, 6, "/", String[]; select_columns = true
    )
    @test seen == [1:0, 7:typemax(Int), 7:typemax(Int), 7:1, 7:10]
    @test isempty(pagerd.highlighted_columns)

    # The prompt of the search highlights them, and the highlight ends with the prompt,
    # both when it is confirmed and when it is cancelled.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:10 v2\n")
    output = _run_search!(pagerd)
    @test occursin(_COLUMN_BACKGROUND, output)
    @test pagerd.search_columns == 7:10
    @test isempty(pagerd.highlighted_columns)
    TerminalPager._paint_view!(pagerd)
    @test !occursin(_COLUMN_BACKGROUND, String(take!(pagerd.term.out_stream)))

    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:10\e")
    @test occursin(_COLUMN_BACKGROUND, _run_search!(pagerd))
    @test isempty(pagerd.highlighted_columns)

    # A pattern without a range highlights nothing, and neither does the filter prompt.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "v2\n")
    @test !occursin(_COLUMN_BACKGROUND, _run_search!(pagerd))

    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:10 v2\n")
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    empty!(TerminalPager._FILTER_HISTORY)
    @test !occursin(_COLUMN_BACKGROUND, String(take!(pagerd.term.out_stream)))
    @test pagerd.filter_pattern == "@7:10 v2"

    # A text that is too long to be previewed still shows the columns.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:10\e")
    pagerd.num_lines = TerminalPager._INCREMENTAL_SEARCH_MAX_LINES + 1
    @test occursin(_COLUMN_BACKGROUND, _run_search!(pagerd))
end

@testset "Column Selection From the Search Prompt" begin
    # A second `@` selects the range on the screen: the cursor starts at the first visible
    # column, the first Enter fixes a column, and the second one applies the range, which is
    # written in the prompt before the pattern.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@@llllll\nl\nv2\n")
    output = _run_search!(pagerd)
    @test pagerd.search_pattern == "@7:8 v2"
    @test pagerd.search_columns == 7:8
    @test pagerd.mode == :searching
    @test [(m.line, m.column) for m in pagerd.ordered_search_matches] == [(2, 7)]
    @test isempty(pagerd.highlighted_columns)
    @test pagerd.column_selection_cursor == 0
    @test pagerd.column_selection_anchor == 0

    # The status line names the mode and shows the range, and the prompt gets it.
    text = replace(output, r"\e\[[0-9;?]*[A-Za-z]" => "")
    @test occursin("COLUMN  @1:1 ", text)
    @test occursin("COLUMN  @7:7 ", text)
    @test occursin("COLUMN  @7:8 ", text)
    @test occursin("/@7:8 v2", text)

    # The range can be selected backwards.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@@lllllll\nh\nv2\n")
    _run_search!(pagerd)
    @test pagerd.search_columns == 7:8

    # A cancelled selection goes back to the prompt with the input as it was.
    # Notice that Esc must arrive on its own, because it begins the sequences of the keys.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    keys = ["@", "@", "l", "l", "\r", "l", "l", "\e", "1", " ", "r", "o", "w", "\r"]
    pagerd.input = TerminalPager.PagerInput(TypedInput(keys))
    _run_search!(pagerd)
    @test pagerd.search_pattern == "@1 row"
    @test pagerd.search_columns == TerminalPager._UNRESTRICTED_COLUMNS
    @test length(pagerd.ordered_search_matches) == 6

    # A second `@` typed right after the first one of an input selects the range again,
    # starting at its first column and keeping the pattern.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@7:8 v\e[H\e[C@\nlll\n\n")
    _run_search!(pagerd)
    @test pagerd.search_pattern == "@7:10 v"
    @test pagerd.search_columns == 7:10
    @test length(pagerd.ordered_search_matches) == 6

    # Elsewhere, `@` is a character of the pattern, and so is a pasted one.
    lines = vcat(_COLUMN_LINES, "a@@b")
    pagerd = _create_modal_pagerd(lines, "a@@b\n")
    _run_search!(pagerd)
    @test pagerd.search_pattern == "a@@b"
    @test length(pagerd.ordered_search_matches) == 1

    pagerd = _create_modal_pagerd(lines, "")
    pagerd.input = TerminalPager.PagerInput(TypedInput(["@@b\n"]))
    _run_search!(pagerd)
    @test pagerd.search_pattern == "@@b"
    @test length(pagerd.ordered_search_matches) == 1

    # The filter has no range of columns, so its prompt does not select them.
    pagerd = _create_modal_pagerd(lines, "@@b\n")
    pagerd.event = :filter
    @test TerminalPager._pager_event_process!(pagerd)
    empty!(TerminalPager._FILTER_HISTORY)
    @test pagerd.filter_pattern == "@@b"
    @test pagerd.num_lines == 1

    # The selection scrolls the view to show the cursor, and the view is restored when it
    # ends. The search then moves it to the first match.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "@@\$\n\n\e")
    output = _run_search!(pagerd)
    @test occursin("COLUMN  @56:56 ", replace(output, r"\e\[[0-9;?]*[A-Za-z]" => ""))
    @test pagerd.start_column == 1
    @test pagerd.mode == :view

    # Nothing can be selected in an empty text, so the `@` is ignored.
    pagerd = _create_modal_pagerd(String[], "@@\e")
    _run_search!(pagerd)
    @test pagerd.mode == :view
end

@testset "Column Selection With the Mouse" begin
    # A press fixes the column under the pointer and a drag extends the range from it.
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    pagerd.input = TerminalPager.PagerInput(
        TypedInput(["@", "@", "\e[<0;7;3M", "\e[<32;10;4M", "\e[<0;10;4m", "\r", "v\r"])
    )
    _run_search!(pagerd)
    @test pagerd.search_pattern == "@7:10 v"
    @test pagerd.search_columns == 7:10
    @test length(pagerd.ordered_search_matches) == 6

    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    pagerd.mode = :column_selection
    pagerd.column_selection_cursor = 1
    mouse(value, x, y) = TerminalPager._move_column_selection!(
        pagerd, nothing, TerminalPager.Keystroke(; value = value, x = x, y = y)
    )

    mouse("<mouse_press>", 12, 2)
    @test pagerd.column_selection_anchor == 12
    @test pagerd.highlighted_columns == 12:12
    mouse("<mouse_drag>", 5, 6)
    @test pagerd.column_selection_anchor == 12
    @test pagerd.column_selection_cursor == 5
    @test pagerd.highlighted_columns == 5:12

    # The pointer selects the text column under it: the ruler and the frozen columns shift
    # the scrolled ones, and the column ruler is aligned with the text.
    pagerd.show_ruler = true
    pagerd.frozen_columns = 2
    pagerd.start_column = 11
    ruler_width = TerminalPager._ruler_width(pagerd)
    column(x, y) = TerminalPager._column_at(pagerd, x, y)
    @test column(ruler_width + 1, 2) == 1
    @test column(ruler_width + 2, 2) == 2
    @test column(ruler_width + 3, 2) == 11
    @test column(ruler_width, 2) == 0
    @test column(40, 9) == 11 + (40 - ruler_width - 2) - 1

    # The status line, the scrollbar, and the rows outside the display select nothing.
    @test column(ruler_width + 3, 10) == 0
    @test column(ruler_width + 3, 0) == 0
    pagerd.show_scrollbar = true
    @test column(40, 2) == 0
    @test column(39, 2) > 0

    # A title row is not scrolled.
    pagerd.title_rows = 1
    pagerd.frozen_rows = 1
    @test column(ruler_width + 3, 1) == 3
    @test column(ruler_width + 3, 2) == 11

    # The column ruler takes two rows, which select the columns they number.
    pagerd.show_column_ruler = true
    @test column(ruler_width + 3, 1) == 11
    @test column(ruler_width + 3, 3) == 3
    @test column(ruler_width + 3, 4) == 11
    @test column(ruler_width + 3, 9) == 11
    @test column(ruler_width + 3, 10) == 0
end

@testset "Column Selection Movements" begin
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    pagerd.mode = :column_selection
    pagerd.column_selection_cursor = 1
    key = TerminalPager.Keystroke(; value = "x")
    move!(action) = TerminalPager._move_column_selection!(pagerd, action, key)
    text_width = 56

    @test TerminalPager._max_selectable_column(pagerd) == text_width

    # The cursor moves by one or by ten columns and stays inside the text. A movement
    # that changes nothing does not request a redraw.
    pagerd.redraw = false
    move!(:left)
    @test pagerd.column_selection_cursor == 1
    @test !pagerd.redraw
    move!(:right)
    @test pagerd.column_selection_cursor == 2
    @test pagerd.highlighted_columns == 2:2
    @test pagerd.redraw
    move!(:fastright)
    @test pagerd.column_selection_cursor == 12
    move!(:fastleft)
    @test pagerd.column_selection_cursor == 2

    # The view is scrolled so that the cursor is visible.
    move!(:eol)
    @test pagerd.column_selection_cursor == text_width
    @test pagerd.start_column == text_width - 40 + 1
    move!(:left)
    @test pagerd.start_column == text_width - 40 + 1
    move!(:bol)
    @test pagerd.column_selection_cursor == 1
    @test pagerd.start_column == 1

    # A fixed column makes the movements extend the range from it, in both directions.
    pagerd.column_selection_cursor = 20
    pagerd.column_selection_anchor = 20
    move!(:fastright)
    @test pagerd.highlighted_columns == 20:30
    move!(:bol)
    @test pagerd.highlighted_columns == 1:20

    # Every other action is ignored.
    pagerd.redraw = false
    move!(:down)
    move!(nothing)
    @test pagerd.highlighted_columns == 1:20
    @test !pagerd.redraw

    # The frozen columns are always visible, so the view does not scroll for them, and the
    # scrolled columns take what is left of the view.
    pagerd.column_selection_anchor = 0
    pagerd.frozen_columns = 2
    pagerd.start_column = 3
    move!(:eol)
    @test pagerd.start_column == text_width - 38 + 1
    move!(:bol)
    @test pagerd.column_selection_cursor == 1
    @test pagerd.start_column == text_width - 38 + 1
    move!(:right)
    move!(:right)
    @test pagerd.column_selection_cursor == 3
    @test pagerd.start_column == 3

    # If only frozen columns fit in the view, the columns after it cannot be selected.
    pagerd.display_size = (10, 10)
    pagerd.frozen_columns = 20
    @test TerminalPager._max_selectable_column(pagerd) == 10
    pagerd.column_selection_cursor = 30
    move!(nothing)
    @test pagerd.column_selection_cursor == 10

    # Nothing can be selected in a view without columns or in an empty text.
    pagerd.display_size = (10, 0)
    @test TerminalPager._max_selectable_column(pagerd) == 0
    @test isnothing(TerminalPager._select_columns!(pagerd, 1:0))
    @test pagerd.mode == :column_selection

    pagerd = _create_modal_pagerd(String[], "")
    @test TerminalPager._max_selectable_column(pagerd) == 0
end

@testset "Column Selection Status Line" begin
    pagerd, output = _create_status_pagerd(_COLUMN_LINES)
    pagerd.mode = :column_selection
    pagerd.column_selection_cursor = 3
    pagerd.highlighted_columns = 3:3

    # The hint tells what Enter does: it fixes the first column and then applies the range.
    text = _status_bar_text(pagerd, output)
    @test text == "COLUMN  @3:3" * " "^19 * "Enter:start  Esc:cancel   All"
    @test textwidth(text) == 60

    pagerd.column_selection_anchor = 3
    pagerd.highlighted_columns = 3:8
    text = _status_bar_text(pagerd, output)
    @test text == "COLUMN  @3:8" * " "^19 * "Enter:apply  Esc:cancel   All"

    # The mode takes over the row from the visual mode.
    pagerd.visual_mode = true
    @test startswith(_status_bar_text(pagerd, output), "COLUMN  @3:8 ")
end
