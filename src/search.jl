# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to searching text.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

const _search_highlighting = Dict{Bool, Decoration}(
    false => Decoration(foreground = "30", background = "47"),
    true  => Decoration(foreground = "30", background = "43")
)

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

# Change the active matches in `pagerd`. If `forward` is `true`, then the search
# is performed forward. Otherwise, it is performed backwards.
function _change_active_match!(pagerd::Pager, forward::Bool = true)
    search_matches         = pagerd.search_matches
    active_search_match_id = pagerd.active_search_match_id

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

    pagerd.active_search_match_id = active_search_match_id

    return nothing
end

# Find all matches of `regex` in the text of the pager `pager`. The vector with
# the matches will be written to `pagerd`.
function _find_matches!(pagerd::Pager, regex::Regex)
    pagerd.search_matches = string_search_per_line(pagerd.lines, regex)
    return nothing
end

# Move the view of the pager `pagerd` to ensure that the current highlighted
# match is inside it.
function _move_view_to_match!(pagerd::Pager)
    # Unpack.
    active_search_match_id = pagerd.active_search_match_id
    frozen_columns         = pagerd.frozen_columns
    frozen_rows            = pagerd.frozen_rows
    search_matches         = pagerd.search_matches
    show_ruler             = pagerd.show_ruler
    start_column           = pagerd.start_column
    start_row              = pagerd.start_row
    title_rows             = pagerd.title_rows

    rows, cols = _get_pager_display_size(pagerd)

    # If we show the ruler, the amount of available columns to draw data must be
    # reduced to take into account its width.
    if show_ruler
        ruler_spacing = floor(Int, pagerd.num_lines |> abs |> log10) + 4
        cols -= ruler_spacing
    end

    # Compute the last row and columns that is displayed.
    end_row = (start_row - 1) + (rows - frozen_rows)
    end_col = start_column + (cols - frozen_columns)

    # Get the active match.
    hl_i = active_search_match_id
    hl_i == 0 && return nothing

    # The search matches are a dictionary in which the key is the line with a
    # match. Hence, we need to order the keys to count the matches and find the
    # information about the active match.
    #
    # TODO: Can it be improved?
    lines = search_matches |> keys |> collect |> sort

    # Information about the active match.
    hl_line    = 0
    hl_col_beg = 0
    hl_col_end = 0

    # Search what is the current active match.
    i = 0
    for l in lines
        Δ = length(search_matches[l])

        if i + Δ ≥ hl_i
            j = hl_i - i

            match      = search_matches[l][j]
            hl_line    = l
            hl_col_beg = match[1]
            hl_col_end = hl_col_beg + match[2] - 1
            break
        end

        i += Δ
    end

    # Check if the highlight row is visible.
    if (hl_line < start_row)
        start_row = max(hl_line, frozen_rows + 1)
    elseif hl_line > end_row
        start_row = (hl_line + 1) - (rows - frozen_rows)
    end

    # If the highlight is outsidde the title rows, then we can move the view to
    # display it.
    if title_rows < hl_line
        # Check if the highlight column is visible.
        if hl_col_beg < start_column
            start_column = hl_col_beg
        elseif hl_col_end > end_col
            start_column = (hl_col_end + 1) - (cols - frozen_columns)
        end
    end

    pagerd.start_column = start_column
    pagerd.start_row    = start_row

    return nothing
end

# Quit search mode of pager `pagerd`.
function _quit_search!(pagerd::Pager)
    empty!(pagerd.search_matches)
    pagerd.active_search_match_id = 0
    return nothing
end
