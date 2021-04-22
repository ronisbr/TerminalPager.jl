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
    _is_reset(d) && return "$(CSI)0m"

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
    _print_recipe(str::AbstractString, start_char::Int, max_chars::Int, highlight_matches::Vector{NTuple{3, Int}})

Create a printing recipe of the line `str`. The recipe is composed of:

* A vector with the strings;
* A vector with objects of type `Decoration` describing the decoration of each
  string.

This function also return the number of cropped characters in this line.

"""
function _printing_recipe(str::AbstractString,
                          start_char::Int,
                          max_chars::Int,
                          highlight_matches::Vector{NTuple{3, Int}})

    # Current state.
    decoration = Decoration()

    # Vector containing the decorations.
    d = Vector{Decoration}(undef, 0)

    # Vetor containing the strings.
    s = Vector{String}(undef, 0)

    # Initial state for the state machine.
    state = :string

    # Indicate that we reached end of line.
    eol = false

    # Variables to handle highlighting.
    hl_state = :normal
    hl_i = 0
    old_decoration = Decoration()

    # Find the index of the first highlight that can be applied in this line.
    for i = 1:length(highlight_matches)
        m_beg = highlight_matches[i][2]
        m_end = m_beg + highlight_matches[i][3]

        if start_char ≤ m_beg ≤ (start_char + max_chars)
            hl_i = i
            break
        elseif (start_char > m_beg) && (m_end ≤ (start_char + max_chars))
            hl_i = i
            hl_state = :highlight
            decoration = Decoration(reversed = true)
        end
    end

    hl_beg = hl_i ≠ 0 ? highlight_matches[hl_i][2] : 0
    hl_end = hl_i ≠ 0 ? hl_beg + highlight_matches[hl_i][3] - 1 : 0

    # Current string.
    str_i = ""

    # Number of processed characters in the string.
    num_processed_chars = 0

    # Current escape sequence code.
    code = ""

    # Make sure the parameters have correct values.
    start_char < 1 && (start_char = 1)

    # Compute the maximum number of processed chars.
    Δchars = max_chars ≤ 0 ? typemax(Int) : max_chars + (start_char - 1)

    # Variable to compute the number of cropped chars.
    cropped_chars = 0

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
                (start_char ≤ num_processed_chars + 1 ≤ Δchars) &&
                !isempty(str_i)

                push!(s, str_i)
                push!(d, decoration)
                str_i = ""
            end

            continue
        end

        # If we are not in the state `:escape_seq`, then just add the character
        # to the string.
        if state == :string
            cw = textwidth(c)

            # If this character matches the beginning of highlight, we need to
            # flush the string until now and start a new segment.
            if (hl_state == :normal) && (num_processed_chars + cw == hl_beg)
                hl_state = :highlight

                push!(s, str_i)
                push!(d, decoration)
                str_i = ""

                old_decoration = decoration
                decoration = Decoration(reversed = true)
            end

            if (start_char ≤ num_processed_chars + cw ≤ Δchars)
                str_i *= string(c)
            end

            num_processed_chars += cw

            if (hl_state == :highlight) && (num_processed_chars == hl_end)
                # Find the next applicable highlight.
                hl_i += 1
                hl_beg = hl_end = 0

                while hl_i ≤ length(highlight_matches)
                    hl_beg = highlight_matches[hl_i][2]
                    hl_end = hl_beg + highlight_matches[hl_i][3] - 1

                    if hl_beg > num_processed_chars
                        hl_state = :normal
                        break
                    elseif hl_end > num_processed_chars
                        break
                    end
                end

                # Only flush the string and decoration if the new state is
                # `normal` or if there is not any other highlight. This is
                # necessary to account for overlaping matches.
                if (hl_state == :normal) || (hl_i > length(highlight_matches))
                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""
                    decoration = old_decoration
                end
            end

            # Check if we are in the final character to be printed.
            if num_processed_chars ≥ Δchars
                if !eol
                    push!(s, str_i)
                    push!(d, decoration)
                    str_i = ""
                    eol = true

                    cropped_chars += num_processed_chars - Δchars
                else
                    cropped_chars += cw
                end
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

            else
                state = :string
                code = ""
            end
        end
    end

    if !isempty(str_i)
        push!(s, str_i)
        push!(d, decoration)
    elseif cropped_chars > 0
        push!(d, decoration)
    end

    return s, d, cropped_chars
end

################################################################################
#                              Private functions
################################################################################

function _parse_ansi_code(decoration::Decoration, code::String)
    tokens = split(code, ';')

    i = 1
    while i ≤ length(tokens)
        code_i = tryparse(Int, tokens[i], base = 10)

        if code_i == 0
            decoration = Decoration()

        elseif code_i == 1
            decoration = Decoration(decoration; bold = true)

        elseif code_i == 4
            decoration = Decoration(decoration; underline  = true)

        elseif code_i == 7
            decoration = Decoration(decoration; reversed = true)

        elseif code_i == 22
            decoration = Decoration(decoration; bold = false)

        elseif code_i == 24
            decoration = Decoration(decoration; underline = false)

        elseif code_i == 27
            decoration = Decoration(decoration; reversed = false)

        elseif 30 <= code_i <= 37
            decoration = Decoration(decoration; foreground = "$code_i")

        # 256-color support for foreground.
        elseif code_i == 38
            # In this case, we can have an extended color code. To check this,
            # we must have at least two more codes.
            if i+2 ≤ length(tokens)
                code_i_1 = tryparse(Int, tokens[i+1], base = 10)
                code_i_2 = tryparse(Int, tokens[i+2], base = 10)

                if code_i_1 == 5
                    decoration = Decoration(decoration;
                                            foreground = "38;5;$code_i_2")
                end

                i += 2
            end

        elseif code_i == 39
            decoration = Decoration(decoration; foreground = "39")

        elseif 40 <= code_i <= 47
            decoration = Decoration(decoration; background = "$code_i")

        # 256-color support for background.
        elseif code_i == 48
            # In this case, we can have an extended color code. To check this,
            # we must have at least two more codes.
            if i+2 ≤ length(tokens)
                code_i_1 = tryparse(Int, tokens[i+1], base = 10)
                code_i_2 = tryparse(Int, tokens[i+2], base = 10)

                if code_i_1 == 5
                    decoration = Decoration(decoration;
                                            background = "48;5;$code_i_2")
                end

                i += 2
            end

        elseif code_i == 49
            decoration = Decoration(decoration; background = "49")

        # Bright foreground colors defined by Aixterm.
        elseif 90 <= code_i <= 97
            decoration = Decoration(decoration; foreground = "$code_i")

        # Bright background colors defined by Aixterm.
        elseif 100 <= code_i <= 107
            decoration = Decoration(decoration; background = "$code_i")
        end

        i += 1
    end

    return decoration
end

_is_reset(d::Decoration) = d === Decoration()

