## Description #############################################################################
#
# Layout of the text shown by the pager: the lines together with what the renderer needs to
# know about each one of them.
#
############################################################################################

# This regex matches every ANSI escape sequence that defines a decoration. An OSC 8
# hyperlink is terminated by ST (`\e\\`) or BEL (`\a`), and its URL cannot contain control
# characters, so that a sequence that was never terminated does not consume the rest of the
# text.
const _ANSI_SEQUENCE_REGEX = Regex(
    raw"\x1B(?:]8;;[^\x00-\x1F\x7F]*(?:\x1B\\|\a)|[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
)

"""
    struct ViewLayout <: AbstractVector{String}

Store the lines of a text together with the information the renderer needs about each one of
them, so that a frame never measures or parses a line again.

The layout is a read-only vector of the lines: it can be indexed and iterated, but not
modified. A layout can also be derived from another one by selecting rows, in which case the
information of the selected lines is copied instead of computed again.

# Fields

- `lines::Vector{String}`: Lines of the text.
- `printable_widths::Vector{Int}`: Printable width of each line.
- `plain_ascii::BitVector`: Whether each line has only printable ASCII characters, in which
    case its width is its number of bytes and it has no escape sequence.
- `decorations::Vector{Decoration}`: Decoration state in effect before each line,
    accumulated from the beginning of the text.
"""
struct ViewLayout <: AbstractVector{String}
    lines::Vector{String}
    printable_widths::Vector{Int}
    plain_ascii::BitVector
    decorations::Vector{Decoration}
end

"""
    ViewLayout(input_lines::AbstractVector{<:AbstractString}) -> ViewLayout

Create the layout of the lines `input_lines`, measuring each one of them and accumulating
the decoration state in effect before it.

# Arguments

- `input_lines::AbstractVector{<:AbstractString}`: Lines of the text, which are copied.
"""
function ViewLayout(input_lines::AbstractVector{<:AbstractString})
    num_lines = length(input_lines)
    lines = Vector{String}(undef, num_lines)
    printable_widths = Vector{Int}(undef, num_lines)
    plain_ascii = falses(num_lines)
    decorations = Vector{Decoration}(undef, num_lines)
    state = Decoration()

    for (i, input_line) in enumerate(input_lines)
        line = String(input_line)
        lines[i] = line
        decorations[i] = state

        if _is_plain_ascii(line)
            # The width of a plain ASCII line is its number of bytes, and it has no escape
            # sequence that could change the decoration state.
            plain_ascii[i] = true
            printable_widths[i] = ncodeunits(line)
        else
            printable_widths[i] = printable_textwidth(line)

            # Only the lines with an escape byte can change the state. Notice that `0x1b`
            # cannot be part of a multi-byte UTF-8 sequence.
            if 0x1b in codeunits(line)
                for m in eachmatch(_ANSI_SEQUENCE_REGEX, line)
                    state = update_decoration(state, String(m.match))
                end
            end
        end
    end

    return ViewLayout(lines, printable_widths, plain_ascii, decorations)
end

"""
    ViewLayout(text::AbstractString) -> ViewLayout

Create the layout of the lines of `text`, which are separated by `'\\n'`.

# Arguments

- `text::AbstractString`: Text to lay out.
"""
ViewLayout(text::AbstractString) = ViewLayout(split(text, '\n'))

"""
    ViewLayout(source::ViewLayout, rows::AbstractVector{Int}) -> ViewLayout

Create the layout of the lines `rows` of `source`, in the order they are given, copying what
`source` knows about them instead of computing it again. The decoration state before a
selected line is the one before it in `source`, which includes the lines that were not
selected.

# Arguments

- `source::ViewLayout`: Layout the lines are taken from.
- `rows::AbstractVector{Int}`: Indices of the selected lines in `source`.
"""
function ViewLayout(source::ViewLayout, rows::AbstractVector{Int})
    checkbounds(source.lines, rows)

    return ViewLayout(
        source.lines[rows],
        source.printable_widths[rows],
        source.plain_ascii[rows],
        source.decorations[rows],
    )
end

Base.size(layout::ViewLayout) = (length(layout.lines),)
Base.IndexStyle(::Type{ViewLayout}) = IndexLinear()
Base.@propagate_inbounds Base.getindex(layout::ViewLayout, i::Int) = layout.lines[i]

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _is_plain_ascii(str::AbstractString) -> Bool

Return whether `str` has only printable ASCII characters, from the blank to the tilde.

The code units are checked instead of the characters because every byte of a multi-byte
UTF-8 sequence is greater than `0x7E`, so such a string is rejected without being decoded.

# Arguments

- `str::AbstractString`: String to check.
"""
_is_plain_ascii(str::AbstractString) = all(b -> 0x20 <= b <= 0x7E, codeunits(str))
