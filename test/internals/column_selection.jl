## Description #############################################################################
#
# Tests for the highlight of the columns that restrict a search.
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
end

@testset "Columns and View Cells" begin
    pagerd = _create_modal_pagerd(_COLUMN_LINES, "")
    cells(columns; title = false) = TerminalPager._view_cells(pagerd, columns, 40, title)

    # Without scrolling, the cells are the columns, cut at the edge of the view.
    @test cells(3:6) == 3:6
    @test cells(30:typemax(Int)) == 30:40
    @test isempty(cells(41:50))
    @test isempty(cells(1:0))

    # The scrolled view shows the columns from the first visible one.
    pagerd.start_column = 5
    @test cells(3:6) == 1:2
    @test cells(5:5) == 1:1
    @test isempty(cells(1:4))
    @test cells(12:typemax(Int)) == 8:40

    # The frozen columns are the first cells, and the columns hidden between them and the
    # first visible one have no cell.
    pagerd.frozen_columns = 2
    @test cells(1:2) == 1:2
    @test cells(1:6) == 1:4
    @test isempty(cells(3:4))
    @test cells(4:5) == 3:3

    # A title row is not scrolled.
    @test cells(3:6; title = true) == 3:6
    @test cells(30:typemax(Int); title = true) == 30:40
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
