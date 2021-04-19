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

        # Split the lines into escape sequence and text.
        ansi        = collect(eachmatch(regex_ansi, line))
        line_tokens = String.(split(line, regex_ansi))

        # Number of printed columns.
        num_printed_cols = 0

        # Number of virtual columns analyzed.
        num_virtual_cols = 0

        # Indicate that we reached the requested column.
        initial_cropping = true

        # Print the text between ANSI escape sequences.
        for j = 1:length(line_tokens)
            token_width = textwidth(line_tokens[j])

            # We need to find the requested start column.
            if initial_cropping
                if (num_virtual_cols + token_width) < start_col
                    num_virtual_cols += token_width
                    j ≤ length(ansi) && write(io, ansi[j].match)
                    continue
                else
                    line_str = _crop_str(line_tokens[j], start_col - num_virtual_cols)
                    line_width = textwidth(line_str)
                    initial_cropping = false
                end
            else
                line_str = line_tokens[j]
                line_width = token_width
            end

            Δ = cols - num_printed_cols

            # Check if we need to crop the line.
            if Δ < line_width
                Δ > 0 && write(io, _crop_str(line_str, 1, Δ))

                # In this case, we must apply all remaining regexes.
                for k = j:length(ansi)
                    write(io, ansi[k].match)
                end

                columns_cropped = max(columns_cropped, line_width - Δ)
                break
            else
                write(io, line_str)
                j == length(line_tokens) && break
                num_printed_cols += line_width
                write(io, ansi[j].match)
            end
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
