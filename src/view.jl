# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions that creates a view of the string on the IO.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _view!(pagerd::Pager)

Write the view of pager `pagerd` to the view buffer.

"""
function _view!(pagerd::Pager)
    # Get the available display size.
    rows, cols = _get_pager_display_size(pagerd)

    # Get the necessary variables.
    @unpack start_row, start_col, lines, num_lines, active_search_match_id,
            search_matches, buf, freeze_columns, freeze_rows, draw_ruler = pagerd

    # Make sure that the argument values are correct.
    start_row < 1 && (start_row = 1)
    start_col < 1 && (start_col = 1)

    # Printed lines.
    num_printed_lines = 0

    # Regex that matches ANSI escape characters.
    regex_ansi = r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"

    # Indicate whether a line has been cropped.
    lines_cropped = 0

    # Indicate if all columns were displayed.
    columns_cropped = 0

    # Get the active search match.
    active_search_match = if active_search_match_id == 0
        (0, 0, 0)
    else
        search_matches[active_search_match_id]
    end

    # Assemble the vector with the lines to be printed.
    if freeze_rows > 0
        freeze_rows > rows && (freeze_rows = rows)
        start_row ≤ freeze_rows && (start_row = freeze_rows + 1)

        lines_indices = vcat(1:freeze_rows, start_row:num_lines)
    else
        lines_indices = collect(start_row:num_lines)
    end

    # Store the last decoration applied to a line. It is required to draw the
    # ruler without interfering with the line decoration.
    last_decoration = ""

    for i ∈ lines_indices
        # If `i` is larger than `num_lines`, then it means that the user
        # requested to freeze more lines than we currently have.
        i > num_lines && break

        line = lines[i]

        # Check if we need to draw the ruler.
        if draw_ruler
            write(buf, _reset_crayon)
            _draw_vertical_ruler!(buf, i, num_lines)
            write(buf, last_decoration)
        end

        # Get all search matches in this line.
        matches_i = filter(x -> x[1] == i, search_matches)

        # Split the lines into escape sequence and text.
        line_tokens, decoration, cropped_chars_i = _printing_recipe(
            line,
            start_col,
            cols,
            matches_i,
            active_search_match,
            freeze_columns
        )

        columns_cropped = max(columns_cropped, cropped_chars_i)

        printable_chars = 0

        # Print the line.
        for j = 1:length(line_tokens)
            last_decoration = string(decoration[j])
            write(buf, last_decoration)
            write(buf, line_tokens[j])
        end

        # Check if we have a last decoration to apply.
        if length(line_tokens) < length(decoration)
            last_decoration = string(decoration[end])
            write(buf, last_decoration)
        end

        write(buf, '\n')
        num_printed_lines += 1

        if num_printed_lines ≥ rows
            lines_cropped = num_lines - (rows - freeze_rows) - (start_row - 1)
            break
        end
    end

    # Write the information to the sturcture.
    @pack! pagerd = lines_cropped, columns_cropped

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end
