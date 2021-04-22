# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to searching text.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _find_matches(lines::Vector{String}, regex::Regex)

Find all matches of `regex` in `lines`. The return value will be a vector of
`NTuple{4, Int}` with the match in the format `(line, column, width, active)`.

"""
function _find_matches(lines::Vector{T}, regex::Regex) where T<:AbstractString
    matches = NTuple{4, Int}[]

    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    active = 1

    # For each line, find matches based on regex.
    for i = 1:length(lines)
        # We need to filter the escape sequences from the line before searching.
        # TODO: Should we maintain a version of the input without the escape to
        # improve performance?

        line = String(*(split(lines[i], regex_ansi)...))

        matches_i = eachmatch(regex, line)

        for m in matches_i
            # `m.offset` contains the byte in which the match starts. However,
            # we need to obtain the character. Hence, it is necessary to compute
            # the text width from the beginning to the offset.
            push!(matches,
                  (i, textwidth(line[1:m.offset]), textwidth(m.match), active))
            active = 0
        end
    end

    return matches
end

function _activate_next_match!(matches::Vector{NTuple{4, Int}})
    num_matches = length(matches)

    for i = 1:length(matches)
        m = matches[i]

        if m[4] == 1
            # Deactivate the current match.
            matches[i] = (m[1], m[2], m[3], 0)

            # Activate the next match.
            new_i = i == num_matches ? 1 : (i + 1)

            m = matches[new_i]
            matches[new_i] = (m[1], m[2], m[3], 1)

            return nothing
        end
    end

    # If we arrived here, then no match is active. Thus, activate the first
    # element.
    if num_matches > 1
        m = matches[i]
        matches[i] = (m[1], m[2], m[3], 1)
    end

    return nothing
end
