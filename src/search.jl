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
    num_matches = length(pagerd.ordered_search_matches)

    if num_matches != 0
        # Activate the next match according to the user preference.
        if forward
            active_search_match_id += 1
        else
            active_search_match_id -= 1
        end

        # Wrapping around is announced, like `vim` does, because the jump is easy to miss.
        if active_search_match_id > num_matches
            active_search_match_id = 1
            _set_message!(pagerd, "Search wrapped to the top")
        elseif active_search_match_id < 1
            active_search_match_id = num_matches
            _set_message!(pagerd, "Search wrapped to the bottom")
        end
    end

    pagerd.active_search_match_id = active_search_match_id

    return nothing
end

# Column range of a search that is not restricted to a range of printable columns.
const _UNRESTRICTED_COLUMNS = 1:typemax(Int)

"""
    _parse_search_input(str::AbstractString) ->
        Union{Nothing, Tuple{String, UnitRange{Int}}}

Split the search input `str` into the pattern and the range of printable columns in which a
match must start. The range is written before the pattern as `@a:b `, `@a `, or `@:b `,
where a missing bound is open. Without a range, the whole input is the pattern and the range
is `_UNRESTRICTED_COLUMNS`. Return `nothing` if the range is invalid, that is, if it starts
before the first column or ends before it starts.

# Arguments

- `str::AbstractString`: Search input typed by the user.
"""
function _parse_search_input(str::AbstractString)
    m = match(r"^@(\d*)(?::(\d*))? (.*)$"s, str)
    isnothing(m) && return String(str), _UNRESTRICTED_COLUMNS

    first_str = m[1]
    last_str = m[2]
    (isempty(first_str) && (isnothing(last_str) || isempty(last_str))) &&
        return String(str), _UNRESTRICTED_COLUMNS

    # `parse` is qualified because **JuliaSyntax.jl** exports a function with the same name.
    first_column = isempty(first_str) ? 1 : Base.parse(Int, first_str)
    last_column = if isnothing(last_str) || isempty(last_str)
        typemax(Int)
    else
        Base.parse(Int, last_str)
    end
    ((first_column < 1) || (last_column < first_column)) && return nothing

    return String(m[3]), first_column:last_column
end

"""
    _find_matches!(pagerd::Pager, regex::Regex; kwargs...) -> Nothing

Find every match of `regex` and store the search metadata in `pagerd`, keeping only the
matches that start in the printable `columns`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `regex::Regex`: Regular expression to search for.

# Keywords

- `columns::UnitRange{Int}`: Printable columns in which a match must start.
    (**Default**: `_UNRESTRICTED_COLUMNS`)
"""
function _find_matches!(
    pagerd::Pager, regex::Regex; columns::UnitRange{Int} = _UNRESTRICTED_COLUMNS
)
    search_matches = string_search_per_line(pagerd.text_layout, regex)

    # The matches outside the columns are dropped from the highlighting dictionary too, so
    # that the view and the navigation agree. The dictionary is a fresh one.
    if columns != _UNRESTRICTED_COLUMNS
        filter!(search_matches) do (_, line_matches)
            filter!(m -> m[1] in columns, line_matches)
            return !isempty(line_matches)
        end
    end

    ordered_search_matches = _ordered_search_matches(search_matches, pagerd.num_lines)

    pagerd.search_matches = search_matches
    pagerd.ordered_search_matches = ordered_search_matches
    pagerd.search_columns = columns

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

The expression is case-insensitive unless `str` has an uppercase letter, which is the smart
case behavior of `less` and `vim`.

# Arguments

- `str::AbstractString`: Pattern typed by the user.

# Keywords

- `literal::Bool`: Match `str` as literal text instead of a regular expression.
    (**Default**: `false`)
"""
function _try_regex(str::AbstractString; literal::Bool = false)
    flags = any(isuppercase, str) ? "" : "i"
    pattern = literal ? _literal_pattern(str) : str

    # PCRE throws when the pattern is malformed, e.g. when the user types `/[`. There is no
    # `tryparse(Regex, ...)` in Base, so we must catch the error here. Otherwise, it escapes
    # the pager main loop and tears down the session.
    return try
        Regex(pattern, flags)
    catch
        nothing
    end
end

"""
    _literal_pattern(str::AbstractString) -> String

Return a regular expression matching `str` as literal text, quoting it with `\\Q` and
`\\E`. A `\\E` inside `str` ends the quote, so it is escaped and the quote is resumed.

# Arguments

- `str::AbstractString`: Text to match.
"""
function _literal_pattern(str::AbstractString)
    return "\\Q" * replace(str, "\\E" => "\\E\\\\E\\Q") * "\\E"
end

# Tag shown at the search prompt while the patterns are literal.
const _LITERAL_TAG = "[lit]"

"""
    _toggle_literal_search!(pagerd::Pager, k::Keystroke) -> Bool

Toggle the literal search of `pagerd` if `k` is ALT-l and return whether it was.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `k::Keystroke`: Keystroke typed at the search prompt.
"""
function _toggle_literal_search!(pagerd::Pager, k::Keystroke)
    (k.alt && !k.ctrl && !k.shift && (k.value == "l")) || return false
    pagerd.literal_search = !pagerd.literal_search
    return true
end

# Texts up to this number of lines are searched while the pattern is typed. Above it, every
# keystroke would run the search over the whole text, so the search runs when the pattern is
# confirmed instead.
const _INCREMENTAL_SEARCH_MAX_LINES = 100_000

"""
    _search!(pagerd::Pager) -> Nothing

Prompt for a search pattern and highlight its matches in `pagerd`.

While the pattern is typed, the matches in a text with up to `_INCREMENTAL_SEARCH_MAX_LINES`
lines are previewed, and the prompt shows the active match. ALT-l toggles the literal search,
shown as `[lit]` and kept for the session. Cancelling the prompt, or leaving it empty, keeps
the search state and the viewport from before it. An invalid pattern reports an error.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _search!(pagerd::Pager)
    saved = _search_state(pagerd)
    incremental = pagerd.num_lines <= _INCREMENTAL_SEARCH_MAX_LINES
    previewed = Ref("")
    previewed_literal = Ref(pagerd.literal_search)

    on_change = if incremental
        pattern -> begin
            previewed[] = pattern
            previewed_literal[] = pagerd.literal_search
            _preview_search!(pagerd, pattern, saved)
        end
    else
        # The matches of a huge text are not previewed, but the literal tag is still shown.
        _ -> pagerd.literal_search ? _LITERAL_TAG : ""
    end

    on_key = k -> _toggle_literal_search!(pagerd, k)

    cmd_input = _read_cmd!(
        pagerd; history = _SEARCH_HISTORY, on_change = on_change, on_key = on_key
    )

    parsed = isnothing(cmd_input) ? nothing : _parse_search_input(cmd_input)

    if isnothing(cmd_input) || isempty(cmd_input)
        _restore_search_state!(pagerd, saved)
    elseif isnothing(parsed)
        _restore_search_state!(pagerd, saved)
        _set_message!(pagerd, "Invalid column range: $cmd_input"; kind = :error)
    elseif isempty(parsed[1])
        _restore_search_state!(pagerd, saved)
    else
        pattern, columns = parsed
        regex = _try_regex(pattern; literal = pagerd.literal_search)

        if isnothing(regex)
            _restore_search_state!(pagerd, saved)
            _set_message!(pagerd, "Invalid regex: $pattern"; kind = :error)
        else
            _push_history!(_SEARCH_HISTORY, cmd_input)

            # The preview already applied the confirmed pattern, unless the literal mode was
            # toggled after it.
            if !(
                incremental &&
                (previewed[] == cmd_input) &&
                (previewed_literal[] == pagerd.literal_search)
            )
                _restore_viewport!(pagerd, saved)
                _apply_search!(pagerd, regex, columns)
            end
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

"""
    _search_state(pagerd::Pager) -> NamedTuple

Return the search state and the viewport of `pagerd`, so that they can be restored.

# Arguments

- `pagerd::Pager`: Pager state to record.
"""
function _search_state(pagerd::Pager)
    return (
        search_matches = pagerd.search_matches,
        ordered_search_matches = pagerd.ordered_search_matches,
        active_search_match_id = pagerd.active_search_match_id,
        search_columns = pagerd.search_columns,
        start_row = pagerd.start_row,
        start_column = pagerd.start_column,
        mode = pagerd.mode,
    )
end

"""
    _restore_search_state!(pagerd::Pager, saved::NamedTuple) -> Nothing

Restore the search state and the viewport of `pagerd` recorded in `saved`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `saved::NamedTuple`: State returned by [`_search_state`](@ref).
"""
function _restore_search_state!(pagerd::Pager, saved::NamedTuple)
    pagerd.search_matches = saved.search_matches
    pagerd.ordered_search_matches = saved.ordered_search_matches
    pagerd.active_search_match_id = saved.active_search_match_id
    pagerd.search_columns = saved.search_columns
    pagerd.mode = saved.mode
    _restore_viewport!(pagerd, saved)
    return nothing
end

"""
    _restore_viewport!(pagerd::Pager, saved::NamedTuple) -> Nothing

Restore the viewport of `pagerd` recorded in `saved`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `saved::NamedTuple`: State returned by [`_search_state`](@ref).
"""
function _restore_viewport!(pagerd::Pager, saved::NamedTuple)
    pagerd.start_row = saved.start_row
    pagerd.start_column = saved.start_column
    return nothing
end

"""
    _apply_search!(pagerd::Pager, regex::Regex,
        columns::UnitRange{Int} = _UNRESTRICTED_COLUMNS) -> Nothing

Find the matches of `regex` starting in the printable `columns` of `pagerd`, activate the
first one at or after the top of the view, move the view to it, and enter the searching mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `regex::Regex`: Regular expression to search for.
- `columns::UnitRange{Int}`: Printable columns in which a match must start.
    (**Default**: `_UNRESTRICTED_COLUMNS`)
"""
function _apply_search!(
    pagerd::Pager, regex::Regex, columns::UnitRange{Int} = _UNRESTRICTED_COLUMNS
)
    _find_matches!(pagerd, regex; columns = columns)
    _change_active_match!(pagerd, true)
    _move_view_to_match!(pagerd)
    pagerd.mode = :searching
    return nothing
end

"""
    _preview_search!(pagerd::Pager, pattern::String, saved::NamedTuple) -> String

Show the matches of `pattern` while it is typed and return the status shown in the prompt.

The search always starts from the viewport recorded in `saved`, so that the preview does not
drift while the pattern is edited. An empty or invalid pattern restores `saved`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `pattern::String`: Pattern typed so far.
- `saved::NamedTuple`: State returned by [`_search_state`](@ref) before the prompt.
"""
function _preview_search!(pagerd::Pager, pattern::String, saved::NamedTuple)
    literal = pagerd.literal_search
    parsed = _parse_search_input(pattern)
    regex_pattern = isnothing(parsed) ? "" : parsed[1]
    regex = isempty(regex_pattern) ? nothing : _try_regex(regex_pattern; literal = literal)

    status = if isnothing(parsed)
        _restore_search_state!(pagerd, saved)
        "invalid range"
    elseif isnothing(regex)
        _restore_search_state!(pagerd, saved)
        isempty(regex_pattern) ? "" : "invalid regex"
    else
        _restore_viewport!(pagerd, saved)
        _apply_search!(pagerd, regex, parsed[2])
        num_matches = length(pagerd.ordered_search_matches)
        match_id = pagerd.active_search_match_id
        num_matches > 0 ? "match $match_id/$num_matches" : "no match"
    end

    # The literal tag comes first, so that the user sees why the pattern is not a regex.
    if literal
        status = isempty(status) ? _LITERAL_TAG : _LITERAL_TAG * " " * status
    end

    _view!(pagerd)
    _redraw!(pagerd)

    return status
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
        cols -= _ruler_width(pagerd)
    end

    # Compute the last row and column that is displayed. Both are inclusive: `end_col` used
    # to be the first column past the viewport, so a match ending one column past the right
    # edge was considered visible and the view never scrolled to it.
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

    # A match inside the frozen rows is always visible, so the view must not move
    # vertically for it. Otherwise, wrapping the search to such a match threw the view back
    # to the top of the text.
    if hl_line > frozen_rows
        # Check if the highlight row is visible.
        if hl_line < start_row
            start_row = hl_line
        elseif hl_line > end_row
            start_row = (hl_line + 1) - (rows - frozen_rows)
        end
    end

    # If the highlight is outside the title rows, we can move the view to display it. A
    # match that ends inside the frozen columns is always visible, so the view must not
    # move horizontally for it either.
    if (title_rows < hl_line) && (hl_col_end > frozen_columns)
        # Check if the highlight column is visible.
        if hl_col_beg < start_column
            # The first visible column must not be inside the frozen region. Otherwise, the
            # state and the screen disagree, and moving left becomes a no-op.
            start_column = max(hl_col_beg, frozen_columns + 1)
        elseif hl_col_end > end_col
            start_column = (hl_col_end + 1) - (cols - frozen_columns)
        end
    end

    pagerd.start_column = start_column
    pagerd.start_row = start_row

    return nothing
end

"""
    _move_to_match!(pagerd::Pager, forward::Bool) -> Nothing

Activate the next search match of `pagerd` if `forward` is `true`, or the previous one
otherwise, move the view to it, and request a redraw.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `forward::Bool`: Whether to activate the next match instead of the previous one.
"""
function _move_to_match!(pagerd::Pager, forward::Bool)
    _change_active_match!(pagerd, forward)
    _move_view_to_match!(pagerd)
    _request_redraw!(pagerd)
    return nothing
end

"""
    _quit_search!(pagerd::Pager) -> Nothing

Clear all search state in `pagerd`, leave the searching mode, and request a redraw.

# Arguments

- `pagerd::Pager`: Pager state to clear.
"""
function _quit_search!(pagerd::Pager)
    empty!(pagerd.search_matches)
    empty!(pagerd.ordered_search_matches)
    pagerd.active_search_match_id = 0
    pagerd.search_columns = _UNRESTRICTED_COLUMNS
    pagerd.mode = :view
    _request_redraw!(pagerd)
    return nothing
end
