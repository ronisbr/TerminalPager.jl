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
    rows = pagerd.display_size[1] - 1
    cols = pagerd.display_size[2]

    # Get the necessary variables.
    @unpack start_row, start_col, lines, num_lines, active_search_match_id,
            search_matches, buf, freeze_columns = pagerd

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
    active_search_match =
        active_search_match_id == 0 ? nothing : search_matches[active_search_match_id]

    for i = start_row:num_lines
        line = lines[i]

        # Get all search matches in this line.
        matches_i = filter(x -> x[1] == i, search_matches)

        # Split the lines into escape sequence and text.
        line_tokens, decoration, cropped_chars_i =
            _printing_recipe(line,
                             start_col,
                             cols,
                             matches_i,
                             active_search_match,
                             freeze_columns)

        columns_cropped = max(columns_cropped, cropped_chars_i)

        printable_chars = 0

        # Print the line.
        for j = 1:length(line_tokens)
            write(buf, string(decoration[j]))
            write(buf, line_tokens[j])
        end

        # Check if we have a last decoration to apply.
        if length(line_tokens) < length(decoration)
            write(buf, string(decoration[end]))
        end

        write(buf, '\n')
        num_printed_lines += 1

        if num_printed_lines ≥ rows
            lines_cropped = num_lines - rows - (start_row - 1)
            break
        end
    end

    # Write the information to the sturcture.
    @pack! pagerd = lines_cropped, columns_cropped

    # Since we modified the `buf`, we need to request redraw.
    _request_redraw!(pagerd)

    return nothing
end
