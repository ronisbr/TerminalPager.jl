# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to create a printing recipe for the lines.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Convert `Decotration` to string.
function convert(::Type{String}, d::Decoration)

    # Check if we have a reset.
    _is_default(d) && return ""
    d.reset && return "$(CSI)0m"

    str = ""
    str *= isempty(d.foreground) ? "" : "$(CSI)" * d.foreground * "m"
    str *= isempty(d.background) ? "" : "$(CSI)" * d.background * "m"
    str *= "$(CSI)" * (d.bold ? "1" : "22") * "m"
    str *= "$(CSI)" * (d.underline ? "4" : "24") * "m"
    str *= "$(CSI)" * (d.reversed ? "7" : "27") * "m"

    return str
end

string(d::Decoration) = convert(String, d)

"""
    _printing_recipe(str::AbstractString, start_char::Int, max_chars::Int, highlight_matches::SearchMatches, active_match::SearchMatch)

Create a printing recipe of the line `str`. The recipe is composed of:

* A vector with the strings;
* A vector with objects of type `Decoration` describing the decoration of each
  string.

This function also return the number of cropped characters in this line.

"""
function _printing_recipe(str::AbstractString,
                          start_char::Int,
                          max_chars::Int,
                          highlight_matches::SearchMatches,
                          active_match::SearchMatch,
                          freeze_columns::Int)

    # Current state.
    decoration::Decoration = Decoration()

    # Vector containing the decorations.
    d = Vector{Decoration}(undef, 0)

    # Vetor containing the strings.
    s = Vector{String}(undef, 0)

    # Initial state for the state machine.
    state = :string

    # Indicate that we reached end of line.
    eol = false

    # Variables to handle highlighting.
    num_highlights = length(highlight_matches)
    hl_state = :normal
    old_decoration::Decoration = Decoration()

    # Vectors with the beginning and end of the highlights.
    hl_beg = map(x->x[2], highlight_matches)
    hl_end = hl_beg .+ map(x->x[3] - 1, highlight_matches)
    hl_active_id = 0

    for i = 1:num_highlights
        highlight_matches[i] === active_match && (hl_active_id = i)
    end

    # Current string.
    str_i = ""

    # Inform that we have a new decoration.
    new_decoration = false

    # Number of processed characters in the string.
    num_processed_chars = 0

    # Number of printed characters in the display.
    num_printed_chars = 0

    # State of string processing.
    string_state = :initial_cropping

    # Current escape sequence code.
    code = ""

    # Make sure the parameters have correct values.
    start_char < 1 && (start_char = 1)

    # Variable to compute the number of cropped chars.
    cropped_chars = 0

    # Process the freeze columns.
    if freeze_columns > 0
        freeze_columns > max_chars && (freeze_columns = max_chars)
        start_char < freeze_columns && (start_char = freeze_columns)
        string_state = :freeze
    end

    for c in str
        # Check if we have a escape charater. In this case, change the state to
        # `:escape_seq`. We also need to add the string assembled so far to the
        # output vector.
        if c == '\e'
            state = :escape_seq_beg

            # If we are not highlighting somehting, we have at least one space
            # in the screen, and the current string is not empty, then we need
            # to flush the string and decoration to start a new segment.
            if (hl_state == :normal) &&
               ((string_state == :view) || (string_state == :freeze))&&
               !isempty(str_i)
                push!(s, str_i)
                push!(d, decoration)
                str_i = ""
                new_decoration = false
            end

            continue
        end

        # If we are not in the state `:escape_seq`, then just add the character
        # to the string.
        if state == :string
            cw = textwidth(c)

            # If this character matches the beginning of highlight, we need to
            # flush the string until now and start a new segment.
            if (hl_state == :normal)

                hl_id = 0

                for i = 1:num_highlights
                    hl_beg[i] == (num_processed_chars + cw) && (hl_id = i)
                end

                if hl_id > 0
                    hl_state = :highlight

                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""

                    old_decoration = decoration
                    decoration = _default_search_highlighting[hl_id == hl_active_id]
                end
            end

            num_processed_chars += cw

            # Check if we are in the freeze columns.
            if string_state == :freeze
                if num_printed_chars + cw > freeze_columns
                    string_state = :initial_cropping

                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""
                    new_decoration = false
                end
            end

            # Check if we finished the initial cropping with this character.
            if string_state == :initial_cropping
                num_processed_chars ≥ start_char && (string_state = :view)
            end

            # Check if we reached the final of the viewable area.
            if string_state == :view
                num_printed_chars + cw > max_chars && (string_state = :final_cropping)
            end

            if (string_state == :view) || (string_state == :freeze)
                str_i *= string(c)
                num_printed_chars += cw
            end

            if hl_state == :highlight
                hl_id = 0

                for i = 1:num_highlights
                    hl_end[i] == num_processed_chars && (hl_id = i)
                end

                # TODO: If there is a highlight that starts inside the old one,
                # we could save a push here.
                if hl_id > 0
                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""
                    decoration = old_decoration

                    # Add an empty segment to reset all formatting created by
                    # the highlight.
                    push!(s, "")
                    push!(d, Decoration(reset = true))

                    hl_state = :normal
                end
            end

            # Check if we are in the final character to be printed.
            if string_state == :final_cropping
                if !eol
                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""
                    eol = true
                end

                cropped_chars += cw
            end

        elseif state == :escape_seq_beg
            state = c == '[' ? :escape_seq : :string

        elseif state == :escape_seq
            if isdigit(c) || c == ';'
                code *= string(c)

            elseif c == 'm'
                state = :string

                if hl_state == :highlight
                    old_decoration = _parse_ansi_code(old_decoration, code)
                else
                    decoration = _parse_ansi_code(decoration, code)
                end

                code = ""
                new_decoration = true

            else
                state = :string
                code = ""
            end
        end
    end

    if !isempty(str_i)
        push!(s, str_i)
        push!(d, decoration)
    elseif new_decoration
        push!(d, decoration)
    end

    return s, d, cropped_chars
end

################################################################################
#                              Private functions
################################################################################

function _parse_ansi_code(decoration::Decoration, code::String)
    tokens = split(code, ';')

    # Unpack fields.
    @unpack foreground, background, bold, underline, reset, reversed, force =
            decoration

    # `reset` must not be copied to other decorations. Hence, we need to reset
    # it here.
    reset = false
    force = false

    i = 1
    while i ≤ length(tokens)
        code_i = tryparse(Int, tokens[i], base = 10)

        if code_i == 0
            # If we have a reset, neglect all the other configurations.
            return Decoration(reset = true)

        elseif code_i == 1
            bold = true

        elseif code_i == 4
            underline  = true

        elseif code_i == 7
            reversed = true

        elseif code_i == 22
            bold = false
            force = true

        elseif code_i == 24
            underline = false
            force = true

        elseif code_i == 27
            reversed = false
            force = true

        elseif 30 <= code_i <= 37
            foreground = "$code_i"

        # 256-color support for foreground.
        elseif code_i == 38
            # In this case, we can have an extended color code. To check this,
            # we must have at least two more codes.
            if i+2 ≤ length(tokens)
                code_i_1 = tryparse(Int, tokens[i+1], base = 10)
                code_i_2 = tryparse(Int, tokens[i+2], base = 10)

                if code_i_1 == 5
                    foreground = "38;5;$code_i_2"
                end

                i += 2
            end

        elseif code_i == 39
            foreground = "39"

        elseif 40 <= code_i <= 47
            background = "$code_i"

        # 256-color support for background.
        elseif code_i == 48
            # In this case, we can have an extended color code. To check this,
            # we must have at least two more codes.
            if i+2 ≤ length(tokens)
                code_i_1 = tryparse(Int, tokens[i+1], base = 10)
                code_i_2 = tryparse(Int, tokens[i+2], base = 10)

                if code_i_1 == 5
                    background = "48;5;$code_i_2"
                end

                i += 2
            end

        elseif code_i == 49
            background = "49"

        # Bright foreground colors defined by Aixterm.
        elseif 90 <= code_i <= 97
            foreground = "$code_i"

        # Bright background colors defined by Aixterm.
        elseif 100 <= code_i <= 107
            background = "$code_i"
        end

        i += 1
    end

    return Decoration(foreground,
                      background,
                      bold,
                      underline,
                      reset,
                      reversed,
                      force)
end

_is_default(d::Decoration) = d === Decoration()

