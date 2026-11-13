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

# Default decorations of the renderer, used only when the caller passes none.
const _DEFAULT_HIGHLIGHT = "$(CSI)7m"
const _DEFAULT_ACTIVE_HIGHLIGHT = "$(CSI)30;43m"
const _DEFAULT_RULER_DECORATION = "$(CSI)90m"
const _DEFAULT_VISUAL_BACKGROUND = "44"

"""
    _textview(buf::IO, layout::ViewLayout, view::NTuple{4, Int}; kwargs...) ->
        Tuple{Int, Int}
    _textview(layout::ViewLayout, view::NTuple{4, Int}; kwargs...) ->
        Tuple{String, Int, Int}

Write to `buf` the rows of `layout` selected by `view`, which is the first row, the number
of rows, the first printable column, and the number of columns, where a negative number
means every remaining row or column. Return the number of rows cropped below the view and
the largest number of columns cropped at the right of a row. Without `buf`, return the
rendered text before the two numbers.

The frozen rows and columns are always written first, the title rows are written from the
first column, the line-number ruler is written before each row, the search matches are
highlighted, and the visual rows get a background. The rows are separated by `'\\n'`,
without one after the last row, and the frozen rows end with a reset of the attributes.

# Arguments

- `buf::IO`: Buffer receiving the rows.
- `layout::ViewLayout`: Layout of the text.
- `view::NTuple{4, Int}`: First row, number of rows, first column, and number of columns.

# Keywords

- `active_highlight::String`: Escape sequence that decorates the active search match.
    (**Default**: `"\\e[30;43m"`)
- `active_match_location::NTuple{2, Int}`: Row and index in the row of the active search
    match, or `(0, 0)` for none. A location without a match is ignored.
    (**Default**: `(0, 0)`)
- `frozen_columns_at_beginning::Int`: Number of leading columns written before the scrolled
    ones in every row.
    (**Default**: `0`)
- `frozen_lines_at_beginning::Int`: Number of leading rows written before the scrolled ones.
    (**Default**: `0`)
- `highlight::String`: Escape sequence that decorates the other search matches.
    (**Default**: `"\\e[7m"`)
- `line_numbers::Union{Nothing, Vector{Int}}`: Number written in the ruler for each row of
    `layout`, which must not decrease, or `nothing` to write the row index. The width of the
    ruler follows the last number.
    (**Default**: `nothing`)
- `maximum_number_of_columns::Int`: Width of the display, including the ruler, or a negative
    number for an unbounded one.
    (**Default**: `-1`)
- `maximum_number_of_lines::Int`: Number of rows of the display, including the frozen ones,
    or a negative number for an unbounded one.
    (**Default**: `-1`)
- `ruler_decoration::String`: Escape sequence that decorates the ruler.
    (**Default**: `"\\e[90m"`)
- `ruler_foot::Bool`: End the ruler of the last frozen row with a foot instead of a bar.
    (**Default**: `false`)
- `ruler_mark_decoration::String`: Escape sequence that decorates the marks of the ruler, or
    an empty string to decorate them like the ruler.
    (**Default**: `""`)
- `ruler_marks::Union{Nothing, Set{Int}}`: Rows whose ruler starts with a mark instead of a
    blank, or `nothing` for none.
    (**Default**: `nothing`)
- `search_matches::Union{Nothing, SearchMatches}`: Search matches of each row, as the first
    printable column and the width of each match, or `nothing` for none.
    (**Default**: `nothing`)
- `show_ruler::Bool`: Write the line-number ruler before each row.
    (**Default**: `false`)
- `title_lines::Int`: Number of frozen rows written from the first column, which do not
    scroll horizontally.
    (**Default**: `0`)
- `visual_line_backgrounds::Union{String, Vector{String}}`: SGR parameters of the background
    of every visual row, or of each one of them.
    (**Default**: `"44"`)
- `visual_lines::Union{Nothing, Vector{Int}}`: Rows written with a background, or `nothing`
    for none. The first background of a repeated row wins.
    (**Default**: `nothing`)
"""
function _textview(
    buf::IO,
    layout::ViewLayout,
    view::NTuple{4, Int};
    active_highlight::String = _DEFAULT_ACTIVE_HIGHLIGHT,
    active_match_location::NTuple{2, Int} = (0, 0),
    frozen_columns_at_beginning::Int = 0,
    frozen_lines_at_beginning::Int = 0,
    highlight::String = _DEFAULT_HIGHLIGHT,
    line_numbers::Union{Nothing, Vector{Int}} = nothing,
    maximum_number_of_columns::Int = -1,
    maximum_number_of_lines::Int = -1,
    ruler_decoration::String = _DEFAULT_RULER_DECORATION,
    ruler_foot::Bool = false,
    ruler_mark_decoration::String = "",
    ruler_marks::Union{Nothing, Set{Int}} = nothing,
    search_matches::Union{Nothing, SearchMatches} = nothing,
    show_ruler::Bool = false,
    title_lines::Int = 0,
    visual_line_backgrounds::Union{String, Vector{String}} = _DEFAULT_VISUAL_BACKGROUND,
    visual_lines::Union{Nothing, Vector{Int}} = nothing,
)
    total_lines = length(layout)
    total_lines == 0 && return 0, 0

    if !isnothing(visual_lines) && (visual_line_backgrounds isa AbstractVector)
        (length(visual_lines) != length(visual_line_backgrounds)) && throw(
            ArgumentError(
                "The length of `visual_lines` must equal the length of " *
                    "`visual_line_backgrounds`.",
            ),
        )
    end

    # == Rows ==============================================================================

    frozen_lines_at_beginning = clamp(frozen_lines_at_beginning, 0, total_lines)
    title_lines = clamp(title_lines, 0, frozen_lines_at_beginning)
    start_line = clamp(view[1], 1, total_lines)

    # The first scrolled row is after the frozen ones, or past the end if every row is
    # frozen.
    if frozen_lines_at_beginning > 0
        first_scrolled_line = frozen_lines_at_beginning + 1

        start_line = if first_scrolled_line > total_lines
            total_lines + 1
        else
            clamp(start_line, first_scrolled_line, total_lines)
        end
    end

    available_lines = max(total_lines - start_line + 1, 0)
    num_lines = view[2] >= 0 ? clamp(view[2], 0, available_lines) : available_lines

    # == Columns ===========================================================================

    start_column = max(view[3], 1)
    num_columns = view[4]

    if (frozen_columns_at_beginning > 0) && (start_column <= frozen_columns_at_beginning)
        start_column = frozen_columns_at_beginning + 1
    end

    # == Ruler =============================================================================

    ruler_spacing = 0

    if show_ruler
        ruler_spacing = if isnothing(line_numbers)
            ndigits(total_lines)
        else
            ndigits(line_numbers[end])
        end

        # The ruler takes columns from the display.
        if maximum_number_of_columns >= 0
            maximum_number_of_columns =
                max(maximum_number_of_columns - ruler_spacing - 3, 0)
        end
    end

    # == Display Limits ====================================================================

    num_cropped_lines_at_end = 0

    if maximum_number_of_lines >= 0
        if frozen_lines_at_beginning >= maximum_number_of_lines
            # Only frozen rows fit in the display.
            frozen_lines_at_beginning = maximum_number_of_lines
            num_lines = 0
        else
            num_lines = min(num_lines, maximum_number_of_lines - frozen_lines_at_beginning)
            num_cropped_lines_at_end = total_lines - start_line - (num_lines - 1)
        end
    else
        num_cropped_lines_at_end = total_lines - start_line - (num_lines - 1)
    end

    if maximum_number_of_columns >= 0
        if frozen_columns_at_beginning >= maximum_number_of_columns
            # Only frozen columns fit in the display.
            frozen_columns_at_beginning = maximum_number_of_columns
            start_column = frozen_columns_at_beginning + 1
            num_columns = 0
        elseif num_columns < 0
            num_columns = maximum_number_of_columns - frozen_columns_at_beginning
        else
            num_columns = clamp(
                num_columns, -1, maximum_number_of_columns - frozen_columns_at_beginning
            )
        end
    end

    max_cropped_chars = 0

    # == Frozen Rows =======================================================================

    for l in 1:frozen_lines_at_beginning
        line_search_matches = _line_search_matches(search_matches, l)
        line_active_match = _line_active_match(active_match_location, l)

        if show_ruler
            _write_ruler!(
                buf,
                _ruler_number(line_numbers, l),
                ruler_spacing,
                ruler_decoration,
                ruler_mark_decoration,
                ruler_foot && (l == frozen_lines_at_beginning),
                _is_ruler_mark(ruler_marks, l),
            )
        end

        cropped_chars_in_line = 0

        if l <= title_lines
            # A title row is never split into frozen and scrolled parts: it is one frozen
            # block spanning the whole width of the view, unbounded if the view is.
            if num_columns < 0
                title_num_columns = -1
                title_frozen_columns = 0
            else
                title_num_columns = 0
                title_frozen_columns = num_columns + frozen_columns_at_beginning
            end

            _draw_layout_line!(
                buf,
                layout,
                l,
                line_search_matches,
                line_active_match,
                highlight,
                active_highlight,
                1,
                title_num_columns,
                title_frozen_columns,
            )
        else
            cropped_chars_in_line = _draw_layout_line!(
                buf,
                layout,
                l,
                line_search_matches,
                line_active_match,
                highlight,
                active_highlight,
                start_column,
                num_columns,
                frozen_columns_at_beginning,
            )
        end

        # The cropped columns are not counted when only the frozen columns are shown.
        if frozen_columns_at_beginning != maximum_number_of_columns
            max_cropped_chars = max(max_cropped_chars, cropped_chars_in_line)
        end

        # The last frozen row resets every attribute.
        if l != frozen_lines_at_beginning
            write(buf, UInt8('\n'))
        else
            write(buf, _SGR_RESET)
            (num_lines > 0) && write(buf, UInt8('\n'))
        end
    end

    # == Scrolled Rows =====================================================================

    for k in 1:num_lines
        l = start_line + k - 1
        line_search_matches = _line_search_matches(search_matches, l)
        line_active_match = _line_active_match(active_match_location, l)

        if show_ruler
            _write_ruler!(
                buf,
                _ruler_number(line_numbers, l),
                ruler_spacing,
                ruler_decoration,
                ruler_mark_decoration,
                false,
                _is_ruler_mark(ruler_marks, l),
            )
        end

        is_visual_line, visual_line_background = _visual_line_background(
            visual_lines, visual_line_backgrounds, l
        )

        cropped_chars_in_line = _draw_layout_line!(
            buf,
            layout,
            l,
            line_search_matches,
            line_active_match,
            highlight,
            active_highlight,
            start_column,
            num_columns,
            frozen_columns_at_beginning,
            is_visual_line,
            visual_line_background,
        )

        if frozen_columns_at_beginning != maximum_number_of_columns
            max_cropped_chars = max(max_cropped_chars, cropped_chars_in_line)
        end

        (k != num_lines) && write(buf, UInt8('\n'))
    end

    return num_cropped_lines_at_end, max_cropped_chars
end

function _textview(layout::ViewLayout, view::NTuple{4, Int}; kwargs...)
    buf = IOBuffer()
    cropped_lines, cropped_columns = _textview(buf, layout, view; kwargs...)
    return String(take!(buf)), cropped_lines, cropped_columns
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _line_search_matches(search_matches::Union{Nothing, SearchMatches}, line::Int) ->
        Union{Nothing, Vector{Tuple{Int, Int}}}

Return the search matches of `line`, or `nothing` if there is none.

# Arguments

- `search_matches::Union{Nothing, SearchMatches}`: Search matches of each row, or `nothing`.
- `line::Int`: Row whose matches are returned.
"""
function _line_search_matches(search_matches::Union{Nothing, SearchMatches}, line::Int)
    isnothing(search_matches) && return nothing
    return get(search_matches, line, nothing)
end

"""
    _line_active_match(active_match_location::NTuple{2, Int}, line::Int) -> Int

Return the index of the active search match in `line`, or `0` if the active match is in
another row.

# Arguments

- `active_match_location::NTuple{2, Int}`: Row and index in the row of the active match.
- `line::Int`: Row whose active match is returned.
"""
function _line_active_match(active_match_location::NTuple{2, Int}, line::Int)
    return active_match_location[1] == line ? active_match_location[2] : 0
end

"""
    _ruler_number(line_numbers::Union{Nothing, Vector{Int}}, line::Int) -> Int

Return the number written in the ruler for the row `line`, which is the row itself when
`line_numbers` is `nothing`.

# Arguments

- `line_numbers::Union{Nothing, Vector{Int}}`: Number of each row, or `nothing`.
- `line::Int`: Row whose number is returned.
"""
function _ruler_number(line_numbers::Union{Nothing, Vector{Int}}, line::Int)
    return isnothing(line_numbers) ? line : line_numbers[line]
end

"""
    _is_ruler_mark(ruler_marks::Union{Nothing, Set{Int}}, line::Int) -> Bool

Return whether the ruler of the row `line` starts with a mark.

# Arguments

- `ruler_marks::Union{Nothing, Set{Int}}`: Marked rows, or `nothing`.
- `line::Int`: Row to check.
"""
function _is_ruler_mark(ruler_marks::Union{Nothing, Set{Int}}, line::Int)
    return !isnothing(ruler_marks) && (line in ruler_marks)
end

"""
    _visual_line_background(visual_lines::Union{Nothing, Vector{Int}},
        visual_line_backgrounds::Union{String, Vector{String}}, line::Int) ->
        Tuple{Bool, String}

Return whether the row `line` is a visual row and the SGR parameters of its background,
which are empty otherwise. The first background of a repeated row wins.

# Arguments

- `visual_lines::Union{Nothing, Vector{Int}}`: Visual rows, or `nothing`.
- `visual_line_backgrounds::Union{String, Vector{String}}`: Background of every visual row,
    or of each one of them.
- `line::Int`: Row to check.
"""
function _visual_line_background(
    visual_lines::Union{Nothing, Vector{Int}},
    visual_line_backgrounds::Union{String, Vector{String}},
    line::Int,
)
    isnothing(visual_lines) && return false, ""
    id = findfirst(==(line), visual_lines)
    isnothing(id) && return false, ""

    background = if visual_line_backgrounds isa AbstractVector
        visual_line_backgrounds[id]
    else
        visual_line_backgrounds
    end

    return true, background
end

"""
    _write_ruler!(buf::IO, number::Int, spacing::Int, decoration::String,
        mark_decoration::String, foot::Bool, mark::Bool) -> Nothing

Write the line-number ruler of one row to `buf`: `decoration`, a mark or a blank, `number`
right-aligned in `spacing` columns, a blank, a foot or a bar, and the reset of the
attributes. A mark is written with `mark_decoration` unless it is empty, and `decoration` is
written again after it.

# Arguments

- `buf::IO`: Buffer receiving the ruler.
- `number::Int`: Number of the row.
- `spacing::Int`: Width of the number column.
- `decoration::String`: Escape sequence that decorates the ruler.
- `mark_decoration::String`: Escape sequence that decorates the mark, or an empty string.
- `foot::Bool`: Write a foot instead of a bar after the number.
- `mark::Bool`: Write a mark instead of a blank before the number.
"""
function _write_ruler!(
    buf::IO,
    number::Int,
    spacing::Int,
    decoration::String,
    mark_decoration::String,
    foot::Bool,
    mark::Bool,
)
    write(buf, decoration)

    if !mark
        write(buf, UInt8(' '))
    elseif isempty(mark_decoration)
        write(buf, _RULER_MARK)
    else
        write(buf, mark_decoration)
        write(buf, _RULER_MARK)
        write(buf, decoration)
    end

    for _ in 1:(spacing - ndigits(number))
        write(buf, UInt8(' '))
    end

    _write_decimal(buf, number)
    write(buf, UInt8(' '))
    write(buf, foot ? _RULER_FOOT : _RULER_BAR)
    write(buf, _SGR_RESET)

    return nothing
end

"""
    _draw_layout_line!(buf::IO, layout::ViewLayout, line::Int, args...) -> Int

Write the view of the row `line` of `layout` to `buf` with the fastest renderer for it, and
return the number of printable columns cropped at its right. `args` are the arguments of
[`_draw_line_view!`](@ref) after the line.

# Arguments

- `buf::IO`: Buffer receiving the row.
- `layout::ViewLayout`: Layout of the text.
- `line::Int`: Row to write.
- `args...`: Remaining arguments of the renderers.
"""
function _draw_layout_line!(buf::IO, layout::ViewLayout, line::Int, args...)
    @inbounds plain = layout.plain_ascii[line]
    plain && return _draw_ascii_line_view!(buf, layout, line, args...)
    return _draw_line_view!(buf, @inbounds(layout.lines[line]), args...)
end

"""
    _draw_ascii_line_view!(
        buf::IO,
        layout::ViewLayout,
        line::Int,
        line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}},
        line_active_match::Int,
        highlight::String,
        active_highlight::String,
        start_column::Int,
        num_columns::Int,
        frozen_columns_at_beginning::Int,
        visual_line::Bool = false,
        visual_line_background::String = ""
    ) -> Int

Write the view of the plain ASCII row `line` of `layout` to `buf`, like
[`_draw_line_view!`](@ref) does, and return the number of printable columns cropped at its
right.

The columns of a plain ASCII row are its bytes, so the visible parts are written directly
from the row unless they must be transformed by a background or a highlight.

# Arguments

- `buf::IO`: Buffer receiving the row.
- `layout::ViewLayout`: Layout of the text.
- `line::Int`: Row to write.
- `line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}}`: First printable column
    and width of each search match of the row, or `nothing`.
- `line_active_match::Int`: Index of the active search match in the row, or `0`.
- `highlight::String`: Escape sequence that decorates the search matches.
- `active_highlight::String`: Escape sequence that decorates the active search match.
- `start_column::Int`: First scrolled printable column.
- `num_columns::Int`: Number of scrolled columns, or a negative number for every column.
- `frozen_columns_at_beginning::Int`: Number of leading columns written before the scrolled
    ones.
- `visual_line::Bool`: Whether the row is a visual row.
    (**Default**: `false`)
- `visual_line_background::String`: SGR parameters of the background of a visual row.
    (**Default**: `""`)
"""
function _draw_ascii_line_view!(
    buf::IO,
    layout::ViewLayout,
    line::Int,
    line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}},
    line_active_match::Int,
    highlight::String,
    active_highlight::String,
    start_column::Int,
    num_columns::Int,
    frozen_columns_at_beginning::Int,
    visual_line::Bool = false,
    visual_line_background::String = "",
)
    @inbounds str = layout.lines[line]
    @inbounds width = layout.printable_widths[line]

    # The visible parts are copied into strings only when they must be transformed. The
    # plain rows, which are most of them, are written directly.
    transform = visual_line || !isnothing(line_search_matches)

    if frozen_columns_at_beginning > 0
        frozen_width = min(frozen_columns_at_beginning, width)

        if !transform
            (frozen_width > 0) && write(buf, SubString(str, 1, frozen_width))
            write(buf, _SGR_RESET)
            @goto scrolled
        end

        left = frozen_width == 0 ? "" : String(SubString(str, 1, frozen_width))

        if visual_line
            if frozen_width < frozen_columns_at_beginning
                left *= " "^(frozen_columns_at_beginning - frozen_width)
            end

            left = replace_default_background(left, visual_line_background)
        end

        if !isnothing(line_search_matches)
            left = highlight_search(
                left,
                line_search_matches;
                active_highlight = active_highlight,
                active_match = line_active_match,
                highlight = highlight,
                min_column = 1,
                max_column = frozen_columns_at_beginning,
                start_column = 1,
            )
        end

        write(buf, left)
        write(buf, _SGR_RESET)
    end

    @label scrolled

    first_visible = min(start_column, width + 1)
    available_width = max(width - first_visible + 1, 0)
    visible_width = num_columns < 0 ? available_width : min(num_columns, available_width)
    cropped_chars = num_columns < 0 ? 0 : max(available_width - num_columns, 0)

    if !transform
        (visible_width > 0) &&
            write(buf, SubString(str, first_visible, first_visible + visible_width - 1))
        return cropped_chars
    end

    line_str = if visible_width == 0
        ""
    else
        String(SubString(str, first_visible, first_visible + visible_width - 1))
    end

    if (num_columns >= 0) && visual_line && (visible_width < num_columns)
        line_str *= " "^(num_columns - visible_width)
    end

    if visual_line && (num_columns >= 0)
        line_str = replace_default_background(line_str, visual_line_background)
    end

    if !isnothing(line_search_matches)
        line_str = highlight_search(
            line_str,
            line_search_matches;
            active_highlight = active_highlight,
            active_match = line_active_match,
            highlight = highlight,
            start_column = start_column,
            min_column = start_column,
            max_column = num_columns < 0 ? 0 : start_column + num_columns - 1,
        )
    end

    write(buf, line_str)

    return cropped_chars
end

"""
    _draw_line_view!(
        buf::IO,
        line::AbstractString,
        line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}},
        line_active_match::Int,
        highlight::String,
        active_highlight::String,
        start_column::Int,
        num_columns::Int,
        frozen_columns_at_beginning::Int,
        visual_line::Bool = false,
        visual_line_background::String = ""
    ) -> Int

Write the view of `line` to `buf` and return the number of printable columns cropped at its
right.

The frozen columns are written first and end with a reset of the attributes. The scrolled
part starts at `start_column` with the decorations of the cropped left part collapsed into
one sequence, has `num_columns` columns, and ends with the decorations of the cropped right
part, so that the terminal state after the row is the one after the whole line. A visual row
is padded to the width of the view and gets the background. The search matches in the
visible columns are highlighted at the end.

# Arguments

- `buf::IO`: Buffer receiving the row.
- `line::AbstractString`: Line to write.
- `line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}}`: First printable column
    and width of each search match of the line, or `nothing`.
- `line_active_match::Int`: Index of the active search match in the line, or `0`.
- `highlight::String`: Escape sequence that decorates the search matches.
- `active_highlight::String`: Escape sequence that decorates the active search match.
- `start_column::Int`: First scrolled printable column.
- `num_columns::Int`: Number of scrolled columns, or a negative number for every column.
- `frozen_columns_at_beginning::Int`: Number of leading columns written before the scrolled
    ones.
- `visual_line::Bool`: Whether the row is a visual row.
    (**Default**: `false`)
- `visual_line_background::String`: SGR parameters of the background of a visual row.
    (**Default**: `""`)
"""
function _draw_line_view!(
    buf::IO,
    line::AbstractString,
    line_search_matches::Union{Nothing, Vector{Tuple{Int, Int}}},
    line_active_match::Int,
    highlight::String,
    active_highlight::String,
    start_column::Int,
    num_columns::Int,
    frozen_columns_at_beginning::Int,
    visual_line::Bool = false,
    visual_line_background::String = "",
)
    line_str = string(line)

    # == Frozen Columns ====================================================================

    if frozen_columns_at_beginning > 0
        left, _ = split_string(line_str, frozen_columns_at_beginning)

        # A visual row fills the frozen columns, so that the background covers them.
        if visual_line
            w = printable_textwidth(left)

            if w < frozen_columns_at_beginning
                left = string(left, " "^(frozen_columns_at_beginning - w))
            end

            left = replace_default_background(left, visual_line_background)
        end

        if !isnothing(line_search_matches)
            left = highlight_search(
                left,
                line_search_matches;
                active_highlight = active_highlight,
                active_match = line_active_match,
                highlight = highlight,
                min_column = 1,
                max_column = frozen_columns_at_beginning,
                start_column = 1,
            )
        end

        write(buf, left)
        write(buf, _SGR_RESET)
    end

    # == Scrolled Columns ==================================================================

    # The decorations of the cropped left part are collapsed into one sequence, so that the
    # visible part starts with the right attributes.
    left, line_str = split_string(line_str, start_column - 1)
    left_ansi = String(parse_decoration(get_decorations(left)))

    if num_columns >= 0
        # A visual row fills the view, so that the background covers it.
        if visual_line
            w = printable_textwidth(line_str)

            if w < num_columns
                line_str = line_str * " "^(num_columns - w)
            end
        end

        line_str, right = split_string(line_str, num_columns)

        # The decorations of the cropped right part are collapsed too, so that the terminal
        # state after the row is the one after the whole line.
        right_ansi = String(parse_decoration(get_decorations(right)))
        cropped_chars = printable_textwidth(right)
        line_str = string(left_ansi, line_str, right_ansi)

        if visual_line
            line_str = replace_default_background(line_str, visual_line_background)
        end
    else
        cropped_chars = 0
        line_str = string(left_ansi, line_str)
    end

    if !isnothing(line_search_matches)
        line_str = highlight_search(
            line_str,
            line_search_matches;
            active_highlight = active_highlight,
            active_match = line_active_match,
            highlight = highlight,
            start_column = start_column,
            min_column = start_column,
            max_column = num_columns < 0 ? 0 : start_column + num_columns - 1,
        )
    end

    write(buf, line_str)

    return cropped_chars
end
