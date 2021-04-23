# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to searching text.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function reset_highlighting()
    _default_search_highlighting[0] = Decoration(foreground = "30",
                                                 background = "47")
    _default_search_highlighting[1] = Decoration(foreground = "30",
                                                 background = "43")
end
reset_highlighting()

"""
    _change_active_match!(pagerd::Pager, forward::Bool = true)

Change the active matches in `pagerd`. If `forward` is `true`, then the search
is performed forward. Otherwise, it is performed backwards.

"""
function _change_active_match!(pagerd::Pager, forward::Bool = true)
    @unpack search_matches = pagerd

    num_matches = length(search_matches)

    for i = 1:num_matches
        m = search_matches[i]

        if m[4] == 1
            # Deactivate the current match.
            search_matches[i] = (m[1], m[2], m[3], 0)

            # Activate the next match according to the user preference.
            if forward
                new_i = i == num_matches ? 1 : (i + 1)
            else
                new_i = i == 1 ? num_matches : (i - 1)
            end

            m = search_matches[new_i]
            search_matches[new_i] = (m[1], m[2], m[3], 1)

            return nothing
        end
    end

    # If we arrived here, then no match is active. Thus, activate the first
    # element.
    if num_matches > 1
        m = search_matches[i]
        search_matches[i] = (m[1], m[2], m[3], 1)
    end

    return nothing
end

"""
    _find_matches!(pagerd::Pager, regex::Regex)

Find all matches of `regex` in the text of the pager `pager`. The vector with
the matches will be written to `pagerd`.

"""
function _find_matches!(pagerd::Pager, regex::Regex)
    @unpack lines, num_lines, search_matches = pagerd

    empty!(search_matches)

    # Regex to remove the ANSI escape sequence.
    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    active = 1

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
                  (i, textwidth(line[1:m.offset]), textwidth(m.match), active))
            active = 0
        end
    end

    return nothing
end
