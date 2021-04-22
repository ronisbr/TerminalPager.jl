# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions that creates a view of the string on the IO.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _view(io::IO, tokens::Vector{T} where T<:AbstractString, screen_size::NTuple{2,Int}, start_row::Int, start_col::Int)

Show a view of `tokens` in `io` considering the screen size `screen_size` and
the start row and column `start_row` and `start_col`.

"""
function _view(io::IO,
               tokens::Vector{T} where T<:AbstractString,
               screen_size::NTuple{2,Int},
               search_matches::Vector{NTuple{4, Int}},
               start_row::Int,
               start_col::Int)

    # Get the available display size.
    rows, cols = screen_size

    # Make sure that the argument values are correct.
    start_row < 1 && (start_row = 1)
    start_col ≤ 1 && (start_col = 1)

    # Printed lines.
    num_printed_lines = 0

    # Regex that matches ANSI escape characters.
    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    # Indicate whether a line has been cropped.
    lines_cropped = 0

    # Indicate if all columns were displayed.
    columns_cropped = 0

    for i = start_row:length(tokens)
        line = tokens[i]

        # Get all search matches in this line.
        highlight_matches_i = filter(x -> x[1] == i, search_matches)

        # Split the lines into escape sequence and text.
        line_tokens, decoration, cropped_chars_i =
            _printing_recipe(line, start_col, cols, highlight_matches_i)

        columns_cropped = max(columns_cropped, cropped_chars_i)

        printable_chars = 0

        # Print the line.
        for j = 1:length(line_tokens)
            write(io, string(decoration[j]))
            write(io, line_tokens[j])
        end

        # Check if we have a last decoration to apply.
        if length(line_tokens) < length(decoration)
            write(io, string(decoration[end]))
        end

        write(io, '\n')
        num_printed_lines += 1

        if num_printed_lines ≥ rows
            lines_cropped = length(tokens) - rows - (start_row - 1)
            break
        end
    end

    return lines_cropped, columns_cropped
end
