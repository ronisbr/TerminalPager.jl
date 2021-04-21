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
               search_matches::Vector{NTuple{3, Int}},
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

        # Get all search matches in this line.
        matches_i = filter(x -> x[1] == i, search_matches)

        # Create the highlight recipe for the current line.
        highlight_recipe_i = _create_highlight_recipe(line_tokens,
                                                      ansi,
                                                      start_col,
                                                      cols,
                                                      matches_i)

        # Merge the line with printable characters.
        printable_line = *(line_tokens...)

        # Print the line.
        c_i = 0

        write(io, get(highlight_recipe_i, 0, ""))

        line_cropped = false

        for c in printable_line
            c_i += 1

            Δc_i = c_i - (start_col - 1)
            if 0 < Δc_i ≤ cols
                write(io, c)
                haskey(highlight_recipe_i, Δc_i) && write(io, highlight_recipe_i[Δc_i])

            elseif c_i - (start_col - 1) > cols
                columns_cropped =
                    max(columns_cropped,
                        textwidth(printable_line) - cols - (start_col - 1))
                line_cropped = true
                break

            end
        end

        if !line_cropped
            write(io, get(highlight_recipe_i, c_i, ""))
        else
            write(io, get(highlight_recipe_i, cols, ""))
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

"""
    _create_highlight_recipe(line_tokens::Vector{String}, ansi::Vector{RegexMatch}, start_col::Int, display_width::Int, search_matches::Vector{NTuple{3, Int}})

Create the highlight recipe of a line. The recipe is a dictionary in which the
keys are the column to apply the highlight in the value **after** the column
character. The key 0 means that the highlight must be applied to the beginning
of the line.

"""
function _create_highlight_recipe(line_tokens::Vector{String},
                                  ansi::Vector{RegexMatch},
                                  start_col::Int,
                                  display_width::Int,
                                  search_matches::Vector{NTuple{3, Int}})

    highlight_recipe = Dict{Int, String}()

    # Apply the line default highlight
    # ==========================================================================

    # Variable to check if the pass the initial cropping phase.
    initial_cropping = true

    # Number of ANSI escape sequences in this line.
    num_ansi = length(ansi)

    # Number of virtual columns analyzed.
    num_virtual_cols = 0

    # Number of printed columns.
    col = 0

    # Store the current ANSI escape sequence.
    current_ansi = ""

    for i = 1:length(line_tokens)
        token_width = textwidth(line_tokens[i])

        # We need to find the requested start column.
        if initial_cropping
            if (num_virtual_cols + token_width) < (start_col - 1)
                num_virtual_cols += token_width
                i ≤ num_ansi && (current_ansi *= ansi[i].match)
                continue
            else
                initial_cropping = false
                token_width = (num_virtual_cols + token_width) - (start_col - 1)
            end
        end

        # If the current token is 0, then just store the escape sequence.
        if token_width == 0
            i ≤ num_ansi && (current_ansi *= ansi[i].match)

            # Check if the display is larger enought to show the current token.
        elseif (col + token_width) < display_width
            # Before incrementing `col`, flush all accumulated escape sequence.
            if !isempty(current_ansi)
                highlight_recipe[col] = current_ansi
                current_ansi = ""
            end

            col += token_width
            i ≤ num_ansi && (current_ansi *= ansi[i].match)
        else
            # Flush all accumulated escape sequence.
            if !isempty(current_ansi)
                highlight_recipe[col] = current_ansi
                current_ansi = ""
            end

            for j = i:length(ansi)
                current_ansi *= ansi[j].match
            end

            highlight_recipe[display_width] = current_ansi
            current_ansi = ""

            break
        end

    end

    # Check if we have a final escape sequence.
    !isempty(current_ansi) && (highlight_recipe[col] = current_ansi)

    # Apply the search matches highlight
    # ==========================================================================

    for s in search_matches
        m_begin = s[2]
        m_end   = s[2] + s[3]

        # Check if the match is inside the viewable display.
        if (m_begin ≥ start_col) || (m_end ≤ display_width) ||
            (m_end - m_begin > display_width)

            # Notice that the highlight must be applied to the end of the
            # previous character.
            Δbegin = max(m_begin - (start_col - 1) - 1, 0)
            Δend   = min(m_end - (start_col - 1) - 1, display_width)

            current_ansi  = get(highlight_recipe, Δbegin, "")
            current_ansi *= "$(CSI)47;1m"
            highlight_recipe[Δbegin] = current_ansi

            current_ansi  = get(highlight_recipe, Δend, "")
            current_ansi *= "$(CSI)47;0m"
            highlight_recipe[Δend] = current_ansi
        end
    end

    return highlight_recipe
end
