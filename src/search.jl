# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to searching text.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _find_matches(tokens::Vector{String}, regex::Regex)

Find all matches of `regex` in `tokens`. The return value will be a vector of
`NT0uple{3, Int}` with the match in the format `(line, column, width)`.

"""
function _find_matches(tokens::Vector{T}, regex::Regex) where T<:AbstractString
    matches = NTuple{3, Int}[]

    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    # For each line, find matches based on regex.
    for i = 1:length(tokens)
        # We need to filter the escape sequences from the line before searching.
        # TODO: Should we maintain a version of the input without the escape to
        # improve performance?

        line = String(*(split(tokens[i], regex_ansi)...))

        matches_i = eachmatch(regex, line)

        for m in matches_i
            # `m.offset` contains the byte in which the match starts. However,
            # we need to obtain the character. Hence, it is necessary to compute
            # the text width from the beginning to the offset.
            push!(matches, (i, textwidth(line[1:m.offset]), textwidth(m.match)))
        end
    end

    return matches
end
