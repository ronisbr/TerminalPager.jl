## Description #############################################################################
#
# Functions related to searching text.
#
############################################################################################

"""
    _change_active_match!(pagerd::Pager, forward::Bool = true) -> Nothing

Change the active match forward when `forward` is `true` and backward otherwise.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `forward::Bool`: Whether to select the next match instead of the previous match.
    (**Default**: `true`)
"""
function _change_active_match!(pagerd::Pager, forward::Bool = true)
    active_search_match_id = pagerd.active_search_match_id
    num_matches = pagerd.num_matches

    if num_matches != 0
        # Activate the next match according to the user preference.
        if forward
            active_search_match_id += 1
        else
            active_search_match_id -= 1
        end

        if active_search_match_id > num_matches
            active_search_match_id = 1
        elseif active_search_match_id < 1
            active_search_match_id = num_matches
        end
    end

    pagerd.active_search_match_id = active_search_match_id

    return nothing
end

"""
    _find_matches!(pagerd::Pager, regex::Regex) -> Nothing

Find every match of `regex` and store the search metadata in `pagerd`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `regex::Regex`: Regular expression to search for.
"""
function _find_matches!(pagerd::Pager, regex::Regex)
    search_matches = string_search_per_line(pagerd.text_layout, regex)
    ordered_search_matches = _ordered_search_matches(search_matches, pagerd.num_lines)
    num_matches = length(ordered_search_matches)

    pagerd.search_matches = search_matches
    pagerd.ordered_search_matches = ordered_search_matches
    pagerd.num_matches = num_matches

    # Start the navigation just before the first match at or after the top of the current view,
    # so that the following `_change_active_match!` selects it. Otherwise, searching always
    # jumped back to the top of the text, unlike `less`. If every match is above the view, we
    # fall back to the first one.
    first_id = findfirst(m -> m.line >= pagerd.start_row, ordered_search_matches)
    pagerd.active_search_match_id = isnothing(first_id) ? 0 : first_id - 1

    return nothing
end

"""
    _ordered_search_matches(search_matches::SearchMatches, num_lines::Int) ->
        Vector{SearchMatch}

Build search-navigation metadata in document and within-line order.

# Arguments

- `search_matches::SearchMatches`: Search matches grouped by source line.
- `num_lines::Int`: Number of source lines to traverse.
"""
function _ordered_search_matches(search_matches::SearchMatches, num_lines::Int)
    ordered_matches = SearchMatch[]
    isempty(search_matches) && return ordered_matches

    sizehint!(ordered_matches, sum(length, values(search_matches); init = 0))

    # Matches are usually sparse, in which case sorting the lines that actually have one is much
    # cheaper than probing the dictionary once per line of the text: finding two matches in a
    # text with one million lines used to require one million hash lookups. When almost every
    # line matches, however, walking the lines in order avoids the sort entirely.
    if 8 * length(search_matches) >= num_lines
        for line in 1:num_lines
            matches = get(search_matches, line, nothing)
            isnothing(matches) && continue
            _push_line_matches!(ordered_matches, line, matches)
        end
    else
        for line in sort!(collect(keys(search_matches)))
            line <= num_lines || continue
            _push_line_matches!(ordered_matches, line, search_matches[line])
        end
    end

    return ordered_matches
end

"""
    _push_line_matches!(ordered_matches::Vector{SearchMatch}, line::Int,
        matches::Vector{Tuple{Int, Int}}) -> Nothing

Append every match of one source line, in within-line order.

# Arguments

- `ordered_matches::Vector{SearchMatch}`: Vector to append to.
- `line::Int`: One-based source line index.
- `matches::Vector{Tuple{Int, Int}}`: Column and width of each match in the line.
"""
function _push_line_matches!(
    ordered_matches::Vector{SearchMatch}, line::Int, matches::Vector{Tuple{Int, Int}}
)
    @inbounds for index_in_line in eachindex(matches)
        column, width = matches[index_in_line]
        push!(ordered_matches, SearchMatch(line, index_in_line, column, width))
    end

    return nothing
end

"""
    _try_regex(str::AbstractString) -> Union{Nothing, Regex}

Compile `str` into a regular expression, returning `nothing` if it is not valid.

# Arguments

- `str::AbstractString`: Pattern typed by the user.
"""
function _try_regex(str::AbstractString)
    # PCRE throws when the pattern is malformed, e.g. when the user types `/[`. There is no
    # `tryparse(Regex, ...)` in Base, so we must catch the error here. Otherwise, it escapes
    # the pager main loop and tears down the session.
    return try
        Regex(str)
    catch
        nothing
    end
end

"""
    _move_view_to_match!(pagerd::Pager) -> Nothing

Move the viewport so that the active search match is visible.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _move_view_to_match!(pagerd::Pager)
    # Unpack.
    active_search_match_id = pagerd.active_search_match_id
    frozen_columns = pagerd.frozen_columns
    frozen_rows = pagerd.frozen_rows
    ordered_search_matches = pagerd.ordered_search_matches
    show_ruler = pagerd.show_ruler
    start_column = pagerd.start_column
    start_row = pagerd.start_row
    title_rows = pagerd.title_rows

    rows, cols = _get_pager_display_size(pagerd)

    # If we show the ruler, the amount of available columns to draw data must be reduced to
    # take into account its width.
    if show_ruler
        cols -= _ruler_width(pagerd.num_lines)
    end

    # Compute the last row and column that is displayed. Both are inclusive: `end_col` used to
    # be the first column past the viewport, so a match ending exactly at the right edge was
    # considered visible and the view never scrolled to it.
    end_row = (start_row - 1) + (rows - frozen_rows)
    end_col = (start_column - 1) + (cols - frozen_columns)

    # Get the active match.
    hl_i = active_search_match_id
    hl_i == 0 && return nothing

    match = ordered_search_matches[hl_i]
    hl_line = match.line
    hl_col_beg = match.column

    # A zero-width match, for example the one produced by `r"^"`, would otherwise have an end
    # column before its start column.
    hl_col_end = hl_col_beg + max(match.width, 1) - 1

    # Check if the highlight row is visible.
    if (hl_line < start_row)
        start_row = max(hl_line, frozen_rows + 1)
    elseif hl_line > end_row
        start_row = (hl_line + 1) - (rows - frozen_rows)
    end

    # If the highlight is outside the title rows, we can move the view to display it.
    if title_rows < hl_line
        # Check if the highlight column is visible.
        if hl_col_beg < start_column
            start_column = hl_col_beg
        elseif hl_col_end > end_col
            start_column = (hl_col_end + 1) - (cols - frozen_columns)
        end
    end

    pagerd.start_column = start_column
    pagerd.start_row = start_row

    return nothing
end

"""
    _quit_search!(pagerd::Pager) -> Nothing

Clear all search state in `pagerd`.

# Arguments

- `pagerd::Pager`: Pager state to clear.
"""
function _quit_search!(pagerd::Pager)
    empty!(pagerd.search_matches)
    empty!(pagerd.ordered_search_matches)
    pagerd.num_matches = 0
    pagerd.active_search_match_id = 0
    return nothing
end
