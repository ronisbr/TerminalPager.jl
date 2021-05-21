# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to searching text.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    reset_highlighting()

Reset the search highlighting to the default one.

"""
function reset_highlighting()
    _search_highlighting[false] = Decoration(
        foreground = "30",
        background = "47"
    )

    _search_highlighting[true] = Decoration(
        foreground = "30",
        background = "43"
    )

    return nothing
end

"""
    _change_active_match!(pagerd::Pager, forward::Bool = true)

Change the active matches in `pagerd`. If `forward` is `true`, then the search
is performed forward. Otherwise, it is performed backwards.

"""
function _change_active_match!(pagerd::Pager, forward::Bool = true)
    @unpack search_matches, active_search_match_id = pagerd

    num_matches = length(search_matches)

    if num_matches == 0
        active_number_match = 0
    else
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

    @pack! pagerd = active_search_match_id

    return nothing
end

"""
    _find_matches!(pagerd::Pager, regex::Regex)

Find all matches of `regex` in the text of the pager `pager`. The vector with
the matches will be written to `pagerd`.

"""
function _find_matches!(pagerd::Pager, regex::Regex)
    @unpack lines, num_lines, search_matches = pagerd

    # Reset the previous search.
    empty!(search_matches)
    pagerd.active_search_match_id = 0

    # Regex to remove the ANSI escape sequence.
    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    # For each line, find matches based on regex.
    for i = 1:num_lines
        # We need to filter the escape sequences from the line before searching.
        # TODO: Should we maintain a version of the input without the escape to
        # improve performance?

        line = String(*(split(lines[i], regex_ansi)...))

        matches_i = eachmatch(regex, line)

        for m in matches_i
            # `m.offset` contains the byte in which the match starts. However,
            # we need to obtain the character. Hence, it is necessary to compute
            # the text width from the beginning to the offset.
            push!(search_matches,
                  (i, textwidth(line[1:m.offset]), textwidth(m.match))
            )
        end
    end

    return nothing
end

"""
    _move_view_to_match!(pagerd::Pager)

Move the view of the pager `pagerd` to ensure that the current highlighted match
is inside it.

"""
function _move_view_to_match!(pagerd::Pager)
    @unpack display_size, num_lines, start_row, start_col, search_matches,
            active_search_match_id, freeze_rows, freeze_columns = pagerd

    # Compute the last row and columns that is displayed.
    end_row = (start_row - 1) + (display_size[1] - 1 - freeze_rows)
    end_col = start_col + (display_size[2] - freeze_columns)

    # Get the active match.
    hl_i = active_search_match_id
    hl_i == 0 && return nothing

    # Get the position of the highlight.
    m = search_matches[hl_i]
    hl_line = m[1]
    hl_col_beg = m[2]
    hl_col_end = hl_col_beg + m[3] - 1

    # Check if the highlight row is visible.
    if (freeze_rows < hl_line) && (hl_line < start_row)
        start_row = max(hl_line, freeze_rows + 1)
    elseif hl_line > end_row
        start_row = (hl_line + 1) - (display_size[1] - 1 - freeze_rows)
    end

    # Check if the highlight column is visible
    if hl_col_beg < start_col
        start_col = hl_col_beg
    elseif hl_col_end > end_col
        start_col = (hl_col_end + 1) - (display_size[2] - freeze_columns)
    end

    @pack! pagerd = start_row, start_col

    return nothing
end

"""
    _quit_search!(pagerd::Pager)

Quit search mode of pager `pagerd`.

"""
function _quit_search!(pagerd::Pager)
    empty!(pagerd.search_matches)
    pagerd.active_search_match_id = 0
    return nothing
end
