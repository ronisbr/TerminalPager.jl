## Description #############################################################################
#
# Functions related to filtering the lines of the text with a regular expression.
#
############################################################################################

# Filter patterns confirmed in this session, from the oldest to the newest, recalled with
# the up and down keys at the filter prompt.
const _FILTER_HISTORY = String[]

"""
    _filter!(pagerd::Pager) -> Nothing

Prompt for a filter pattern and show only the lines of `pagerd` matching it, or the other
lines if the pattern starts with `!`.

While the pattern is typed, the view of a text with up to `_INCREMENTAL_SEARCH_MAX_LINES`
lines is previewed, and the prompt shows how many lines are visible. ALT-l toggles the
literal mode of the patterns, shared with the search. Cancelling the prompt keeps the filter
and the viewport from before it, an empty pattern clears the filter, and an invalid pattern
reports an error.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _filter!(pagerd::Pager)
    saved = _filter_state(pagerd)

    cmd_input, previewed = _prompt_pattern!(
        pagerd, length(pagerd.source_layout), "&", _FILTER_HISTORY
    ) do pattern
        _preview_filter!(pagerd, pattern, saved)
    end

    if isnothing(cmd_input)
        _restore_filter_state!(pagerd, saved)
    elseif isempty(cmd_input)
        _restore_filter_state!(pagerd, saved)
        _clear_filter!(pagerd)
    else
        pattern, inverted = _parse_filter(cmd_input)
        regex = _try_regex(pattern; literal = pagerd.literal_search)

        if isnothing(regex)
            _restore_filter_state!(pagerd, saved)
            _set_message!(pagerd, "Invalid regex: $pattern"; kind = :error)
        else
            _push_history!(_FILTER_HISTORY, cmd_input)

            # The preview already applied the confirmed pattern, unless the literal mode was
            # toggled after it or the filter failed, in which case the state before the
            # prompt was restored.
            if !previewed || (pagerd.filter_regex === saved.filter_regex)
                reason = _try_filter!(pagerd, regex, inverted, cmd_input, saved)
                isnothing(reason) ||
                    _set_message!(pagerd, "Regex error: $reason"; kind = :error)
            end
        end
    end

    _request_redraw!(pagerd)

    return nothing
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _parse_filter(str::AbstractString) -> Tuple{String, Bool}

Split the filter input `str` into the pattern and whether the filter is inverted, which is
told by a leading `!`. A leading `\\!` is a literal `!`.

# Arguments

- `str::AbstractString`: Filter input typed by the user.
"""
function _parse_filter(str::AbstractString)
    startswith(str, '!') && return String(str[2:end]), true
    startswith(str, "\\!") && return String(str[2:end]), false
    return String(str), false
end

"""
    _filter_rows(layout::ViewLayout, regex::Regex, inverted::Bool, kept_rows::Int) ->
        Vector{Int}

Return the lines of `layout` that are shown by the filter `regex`: the first `kept_rows`
lines, which are the frozen ones, and then the lines matching `regex` without their
decorations, or the other ones if `inverted` is `true`.

# Arguments

- `layout::ViewLayout`: Layout of every line of the text.
- `regex::Regex`: Regular expression of the filter.
- `inverted::Bool`: Hide the matching lines instead of showing them.
- `kept_rows::Int`: Number of leading lines that are always shown.
"""
function _filter_rows(layout::ViewLayout, regex::Regex, inverted::Bool, kept_rows::Int)
    num_lines = length(layout)
    rows = Int[]

    # The number of kept rows is selected by the user, so that it can be larger than the
    # number of lines.
    kept_rows = clamp(kept_rows, 0, num_lines)

    for l in 1:kept_rows
        push!(rows, l)
    end

    for l in (kept_rows + 1):num_lines
        line = layout.lines[l]

        # The decorations are removed only from the lines that have them.
        text = if layout.plain_ascii[l] || !(0x1b in codeunits(line))
            line
        else
            remove_decorations(line)
        end

        (occursin(regex, text) != inverted) && push!(rows, l)
    end

    return rows
end

"""
    _filter_state(pagerd::Pager) -> FilterState

Return the filter, the layout, the viewport, and the search state of `pagerd`, so that they
can be restored.

# Arguments

- `pagerd::Pager`: Pager state to record.
"""
function _filter_state(pagerd::Pager)
    return FilterState(
        pagerd.filter_regex,
        pagerd.filter_inverted,
        pagerd.filter_pattern,
        pagerd.text_layout,
        pagerd.row_to_line,
        pagerd.line_to_row,
        pagerd.num_lines,
        pagerd.text_width,
        pagerd.start_row,
        pagerd.start_column,
        pagerd.visual_mode_line,
        pagerd.search_matches,
        pagerd.ordered_search_matches,
        pagerd.active_search_match_id,
    )
end

"""
    _restore_filter_state!(pagerd::Pager, saved::FilterState) -> Nothing

Restore in `pagerd` the state recorded in `saved` by [`_filter_state`](@ref), and request a
full repaint.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `saved::FilterState`: State returned by [`_filter_state`](@ref).
"""
function _restore_filter_state!(pagerd::Pager, saved::FilterState)
    pagerd.filter_regex = saved.filter_regex
    pagerd.filter_inverted = saved.filter_inverted
    pagerd.filter_pattern = saved.filter_pattern
    pagerd.text_layout = saved.text_layout
    pagerd.row_to_line = saved.row_to_line
    pagerd.line_to_row = saved.line_to_row
    pagerd.num_lines = saved.num_lines
    pagerd.text_width = saved.text_width
    pagerd.start_row = saved.start_row
    pagerd.start_column = saved.start_column
    pagerd.visual_mode_line = saved.visual_mode_line
    pagerd.search_matches = saved.search_matches
    pagerd.ordered_search_matches = saved.ordered_search_matches
    pagerd.active_search_match_id = saved.active_search_match_id
    _reset_crop!(pagerd)
    _invalidate_frame!(pagerd)
    _request_redraw!(pagerd)
    return nothing
end

"""
    _apply_filter!(pagerd::Pager, regex::Regex, inverted::Bool, pattern::String) -> Nothing

Activate in `pagerd` the filter `regex`, typed as `pattern`, and rebuild the view, keeping
the top source line visible when it is not hidden.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `regex::Regex`: Regular expression of the filter.
- `inverted::Bool`: Hide the matching lines instead of showing them.
- `pattern::String`: Filter input typed by the user.
"""
function _apply_filter!(pagerd::Pager, regex::Regex, inverted::Bool, pattern::String)
    pagerd.filter_regex = regex
    pagerd.filter_inverted = inverted
    pagerd.filter_pattern = pattern
    _rebuild_view_layout!(pagerd)
    return nothing
end

"""
    _clear_filter!(pagerd::Pager) -> Nothing

Deactivate the filter of `pagerd` and rebuild the view with every line.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _clear_filter!(pagerd::Pager)
    pagerd.filter_regex = nothing
    pagerd.filter_inverted = false
    pagerd.filter_pattern = ""
    _rebuild_view_layout!(pagerd)
    return nothing
end

"""
    _try_filter!(
        pagerd::Pager,
        regex::Regex,
        inverted::Bool,
        pattern::String,
        saved::FilterState
    ) -> Union{Nothing, String}

Restore the state in `saved`, filter the lines of `pagerd` with `regex`, like
[`_apply_filter!`](@ref) does, and return `nothing`. If the regular expression cannot be
matched against the text, restore the state in `saved` again and return the reason.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `regex::Regex`: Regular expression of the filter.
- `inverted::Bool`: Whether the filter hides the matching lines.
- `pattern::String`: Input of the filter.
- `saved::FilterState`: State returned by [`_filter_state`](@ref) before the prompt.
"""
function _try_filter!(
    pagerd::Pager, regex::Regex, inverted::Bool, pattern::String, saved::FilterState
)
    _restore_filter_state!(pagerd, saved)

    try
        _apply_filter!(pagerd, regex, inverted, pattern)
    catch err
        reason = _regex_error(err)
        isnothing(reason) && rethrow()
        _restore_filter_state!(pagerd, saved)
        return reason
    end

    return nothing
end

"""
    _preview_filter!(pagerd::Pager, pattern::String, saved::FilterState) -> String

Show the lines selected by `pattern` while it is typed and return the status shown in the
prompt. The filter always starts from the state recorded in `saved`, so that the preview
does not drift while the pattern is edited. An empty or invalid pattern restores `saved`.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `pattern::String`: Pattern typed so far.
- `saved::FilterState`: State returned by [`_filter_state`](@ref) before the prompt.
"""
function _preview_filter!(pagerd::Pager, pattern::String, saved::FilterState)
    literal = pagerd.literal_search
    regex_pattern, inverted = _parse_filter(pattern)
    regex = isempty(regex_pattern) ? nothing : _try_regex(regex_pattern; literal = literal)

    status = if isnothing(regex)
        _restore_filter_state!(pagerd, saved)
        isempty(regex_pattern) ? "" : "invalid regex"
    elseif !isnothing(_try_filter!(pagerd, regex, inverted, pattern, saved))
        "regex error"
    else
        "$(pagerd.num_lines) of $(length(pagerd.source_layout)) lines"
    end

    _paint_view!(pagerd)

    return _literal_status(status, literal)
end
