## Description #############################################################################
#
# Rendering of a view of the text: the rows of the layout that are visible, cropped to the
# width of the display, with the frozen rows and columns, the line-number ruler, the search
# highlights, and the visual line backgrounds.
#
############################################################################################

# Glyphs of the line-number ruler, all with a display width of one: the bar after the
# number, the foot that replaces it on the last frozen row, and the mark before the number
# of a bookmarked row.
const _RULER_BAR = "│"
const _RULER_FOOT = "┴"
const _RULER_MARK = "•"

"""
    _textview(buf::IO, layout::ViewLayout, options::ViewOptions) -> Int, Int
    _textview(layout::ViewLayout, options::ViewOptions) -> String, Int, Int

Write to `buf` the rows of `layout` selected by `options`, and return the number of rows
cropped below the view and the largest number of columns cropped at the right of a row.
Without `buf`, return the rendered text before the two numbers.

The frozen rows and columns are always written first, the title rows are written from the
first column, the line-number ruler is written before each row, the search matches are
highlighted, and the visual rows get a background. The rows are separated by `'\\n'`,
without one after the last row, and the frozen rows end with a reset of the attributes.

Each row is written so that it does not depend on the rows before it: a decoration that
begins in a previous line is written again at the beginning of the row, and a decoration
still in effect at its end is closed.

# Extended help

## Throws

- `ArgumentError`: If `options` has one background per visual row and their numbers differ.
"""
function _textview(buf::IO, layout::ViewLayout, options::ViewOptions)
    total_lines = length(layout)
    total_lines == 0 && return 0, 0

    visual_rows = options.visual_rows
    visual_backgrounds = options.visual_backgrounds

    if !isnothing(visual_rows) && (visual_backgrounds isa Vector{String})
        (length(visual_rows) != length(visual_backgrounds)) && throw(
            ArgumentError(
                "The number of visual rows must equal the number of their backgrounds."
            ),
        )
    end

    # == Rows ==============================================================================

    frozen_rows = clamp(options.frozen_rows, 0, total_lines)
    title_rows = clamp(options.title_rows, 0, frozen_rows)
    start_line = clamp(options.first_row, 1, total_lines)

    # The first scrolled row is after the frozen ones, or past the end if every row is
    # frozen.
    if frozen_rows > 0
        first_scrolled_line = frozen_rows + 1

        start_line = if first_scrolled_line > total_lines
            total_lines + 1
        else
            clamp(start_line, first_scrolled_line, total_lines)
        end
    end

    available_lines = max(total_lines - start_line + 1, 0)
    num_lines = if options.num_rows >= 0
        clamp(options.num_rows, 0, available_lines)
    else
        available_lines
    end

    # == Columns ===========================================================================

    frozen_columns = options.frozen_columns
    start_column = max(options.first_column, 1)
    num_columns = options.num_columns

    if (frozen_columns > 0) && (start_column <= frozen_columns)
        start_column = frozen_columns + 1
    end

    # == Ruler =============================================================================

    max_columns = options.max_columns
    ruler_spacing = 0

    if options.show_ruler
        line_numbers = options.line_numbers
        ruler_spacing = ndigits(isnothing(line_numbers) ? total_lines : line_numbers[end])

        # The ruler takes columns from the display.
        (max_columns >= 0) && (max_columns = max(max_columns - ruler_spacing - 3, 0))
    end

    # == Display Limits ====================================================================

    max_rows = options.max_rows
    num_cropped_lines_at_end = 0

    if (max_rows >= 0) && (frozen_rows >= max_rows)
        # Only frozen rows fit in the display.
        frozen_rows = max_rows
        num_lines = 0
    else
        (max_rows >= 0) && (num_lines = min(num_lines, max_rows - frozen_rows))
        num_cropped_lines_at_end = total_lines - start_line - (num_lines - 1)
    end

    if max_columns >= 0
        if frozen_columns >= max_columns
            # Only frozen columns fit in the display.
            frozen_columns = max_columns
            start_column = frozen_columns + 1
            num_columns = 0
        elseif num_columns < 0
            num_columns = max_columns - frozen_columns
        else
            num_columns = clamp(num_columns, -1, max_columns - frozen_columns)
        end
    end

    # A title row is never split into frozen and scrolled parts: it is one frozen block
    # spanning the whole width of the view, unbounded if the view is.
    title_num_columns = num_columns < 0 ? -1 : 0
    title_frozen_columns = num_columns < 0 ? 0 : num_columns + frozen_columns

    # The cropped columns are not counted when only the frozen columns are shown.
    count_cropped_columns = frozen_columns != max_columns
    max_cropped_chars = 0

    # == Frozen Rows =======================================================================

    for l in 1:frozen_rows
        is_last = l == frozen_rows
        _write_ruler!(buf, options, l, ruler_spacing, options.ruler_foot && is_last)

        if l <= title_rows
            _draw_line!(
                buf, layout, options, l, 1, title_num_columns, title_frozen_columns, false
            )
        else
            cropped_chars = _draw_line!(
                buf, layout, options, l, start_column, num_columns, frozen_columns, false
            )

            count_cropped_columns &&
                (max_cropped_chars = max(max_cropped_chars, cropped_chars))
        end

        # The last frozen row resets every attribute.
        is_last && write(buf, _SGR_RESET)
        (!is_last || (num_lines > 0)) && write(buf, UInt8('\n'))
    end

    # == Scrolled Rows =====================================================================

    for l in start_line:(start_line + num_lines - 1)
        _write_ruler!(buf, options, l, ruler_spacing, false)

        cropped_chars = _draw_line!(
            buf, layout, options, l, start_column, num_columns, frozen_columns, true
        )

        count_cropped_columns && (max_cropped_chars = max(max_cropped_chars, cropped_chars))

        (l != start_line + num_lines - 1) && write(buf, UInt8('\n'))
    end

    return num_cropped_lines_at_end, max_cropped_chars
end

function _textview(layout::ViewLayout, options::ViewOptions)
    buf = IOBuffer()
    cropped_lines, cropped_columns = _textview(buf, layout, options)
    return String(take!(buf)), cropped_lines, cropped_columns
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _visual_background(options::ViewOptions, line::Int) -> Union{Nothing, String}

Return the SGR parameters of the background of the row `line` if it is one of the visual
rows of `options`, or `nothing` otherwise. The first background of a repeated row wins.
"""
function _visual_background(options::ViewOptions, line::Int)
    visual_rows = options.visual_rows
    isnothing(visual_rows) && return nothing

    id = findfirst(==(line), visual_rows)
    isnothing(id) && return nothing

    backgrounds = options.visual_backgrounds
    return backgrounds isa Vector{String} ? backgrounds[id] : backgrounds
end

"""
    _write_ruler!(
        buf::IO,
        options::ViewOptions,
        line::Int,
        spacing::Int,
        foot::Bool
    ) -> Nothing

Write the line-number ruler of the row `line` to `buf`, if `options` shows it: the ruler
decoration, a mark or a blank, the number of the row right-aligned in `spacing` columns, a
blank, a foot if `foot` is set or a bar otherwise, and the reset of the attributes. A mark
is written with its own decoration unless it is empty, and the ruler decoration is written
again after it.
"""
function _write_ruler!(
    buf::IO, options::ViewOptions, line::Int, spacing::Int, foot::Bool
)
    options.show_ruler || return nothing

    line_numbers = options.line_numbers
    ruler_marks = options.ruler_marks
    decoration = options.ruler_decoration
    mark_decoration = options.ruler_mark_decoration
    number = isnothing(line_numbers) ? line : line_numbers[line]

    write(buf, decoration)

    if isnothing(ruler_marks) || !(line in ruler_marks)
        write(buf, UInt8(' '))
    elseif isempty(mark_decoration)
        write(buf, _RULER_MARK)
    else
        write(buf, mark_decoration)
        write(buf, _RULER_MARK)
        write(buf, decoration)
    end

    _write_blanks(buf, spacing - ndigits(number))
    _write_decimal(buf, number)
    write(buf, UInt8(' '))
    write(buf, foot ? _RULER_FOOT : _RULER_BAR)
    write(buf, _SGR_RESET)

    return nothing
end

"""
    _draw_line!(
        buf::IO,
        layout::ViewLayout,
        options::ViewOptions,
        line::Int,
        start_column::Int,
        num_columns::Int,
        frozen_columns::Int,
        scrolled_row::Bool
    ) -> Int

Write the view of the row `line` of `layout` to `buf` and return the number of printable
columns cropped at its right.

The first `frozen_columns` columns are written first and end with a reset of the
attributes. The scrolled part starts at `start_column` with the decorations of the cropped
left part collapsed into one sequence, has `num_columns` columns, or every remaining column
if it is negative, and ends with the decorations of the cropped right part, so that the
terminal state after the row is the one after the whole line. If `scrolled_row` is set and
the row is a visual row of `options`, it is padded to the width of the view and gets its
background. The search matches of `options` in the visible columns are highlighted at the
end.

The columns of a row with only printable ASCII characters are its bytes. Hence, its visible
parts are written directly from the line unless they must get a background or a highlight.
"""
function _draw_line!(
    buf::IO,
    layout::ViewLayout,
    options::ViewOptions,
    line::Int,
    start_column::Int,
    num_columns::Int,
    frozen_columns::Int,
    scrolled_row::Bool,
)
    str = layout.lines[line]
    plain = layout.plain_ascii[line]
    width = layout.printable_widths[line]

    search_matches = options.search_matches
    matches = isnothing(search_matches) ? nothing : get(search_matches, line, nothing)
    background = scrolled_row ? _visual_background(options, line) : nothing

    # A decoration that begins in a previous line is written again at the beginning of each
    # part of the row, and what is still in effect after the line is closed at its end.
    # Both are empty for almost every row.
    carried = _carried_decoration(layout.decorations[line])
    terminator = _row_terminator(layout, line)

    # The visible parts are copied into strings only when they must be transformed. The
    # plain rows, which are most of them, are written directly.
    transform = !isnothing(background) || !isnothing(matches)

    # == Frozen Columns ====================================================================

    if frozen_columns > 0
        frozen_width = min(frozen_columns, width)

        if plain && !transform
            write(buf, carried)
            (frozen_width > 0) && write(buf, SubString(str, 1, frozen_width))
        else
            left = if plain
                string(carried, SubString(str, 1, frozen_width))
            else
                string(carried, first(split_string(str, frozen_columns)))
            end

            # A visual row fills the frozen columns, so that the background covers them.
            isnothing(background) || (left = _fill_visual(left, frozen_columns, background))
            left = _highlight(left, options, line, matches, 1, 1, frozen_columns)

            write(buf, left)
        end

        write(buf, _SGR_RESET)
    end

    # == Scrolled Columns ==================================================================

    if plain
        first_visible = min(start_column, width + 1)
        available_width = max(width - first_visible + 1, 0)
        visible_width = available_width
        cropped_chars = 0

        if num_columns >= 0
            visible_width = min(num_columns, available_width)
            cropped_chars = available_width - visible_width
        end

        visible = SubString(str, first_visible, first_visible + visible_width - 1)

        if !transform
            write(buf, carried)
            write(buf, visible)
            write(buf, terminator)
            return cropped_chars
        end

        part = string(carried, visible)
    else
        # The decorations of the cropped left part are collapsed into one sequence, so that
        # the visible part starts with the right attributes.
        left, part = split_string(str, start_column - 1)
        left_ansi = String(parse_decoration(get_decorations(left)))
        right_ansi = ""
        cropped_chars = 0

        if num_columns >= 0
            # A visual row fills the view. It must be padded before it is cropped so that
            # the decorations of the cropped right part come after the padding.
            isnothing(background) || (part = _pad(part, num_columns))
            part, right = split_string(part, num_columns)

            # The decorations of the cropped right part are collapsed too, so that the
            # terminal state after the row is the one after the whole line.
            right_ansi = String(parse_decoration(get_decorations(right)))
            cropped_chars = printable_textwidth(right)
        end

        part = string(carried, left_ansi, part, right_ansi)
    end

    # A visual row fills the view, so that the background covers it. An unbounded view has
    # no width to fill.
    if !isnothing(background) && (num_columns >= 0)
        part = _fill_visual(part, num_columns, background)
    end

    max_column = num_columns < 0 ? 0 : start_column + num_columns - 1
    part = _highlight(part, options, line, matches, start_column, start_column, max_column)

    write(buf, part)
    write(buf, terminator)

    return cropped_chars
end

"""
    _pad(str::String, width::Int) -> String

Return `str` followed by the blanks required for its printable width to be `width`, or
`str` itself if it is at least that wide.
"""
function _pad(str::String, width::Int)
    missing_width = width - printable_textwidth(str)
    return missing_width > 0 ? str * " "^missing_width : str
end

"""
    _fill_visual(str::String, width::Int, background::String) -> String

Return the part `str` of a visual row padded with blanks up to the printable `width` and
with its default background replaced by the SGR parameters `background`.
"""
function _fill_visual(str::String, width::Int, background::String)
    return replace_default_background(_pad(str, width), background)
end

"""
    _highlight(
        str::String,
        options::ViewOptions,
        line::Int,
        matches::Union{Nothing, Vector{Tuple{Int, Int}}},
        start_column::Int,
        min_column::Int,
        max_column::Int
    ) -> String

Return the part `str` of the row `line`, whose first character is at the printable column
`start_column`, with the search `matches` of the row between the columns `min_column` and
`max_column` highlighted with the decorations of `options`. A `max_column` of `0` means no
limit, and `str` is returned as it is if `matches` is `nothing`.
"""
function _highlight(
    str::String,
    options::ViewOptions,
    line::Int,
    matches::Union{Nothing, Vector{Tuple{Int, Int}}},
    start_column::Int,
    min_column::Int,
    max_column::Int,
)
    isnothing(matches) && return str

    active_row, active_match = options.active_match

    return highlight_search(
        str,
        matches;
        active_highlight = options.active_highlight,
        active_match = active_row == line ? active_match : 0,
        highlight = options.highlight,
        max_column = max_column,
        min_column = min_column,
        start_column = start_column,
    )
end
