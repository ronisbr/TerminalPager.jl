## Description #############################################################################
#
# Layout of the text shown by the pager: the lines together with what the renderer needs to
# know about each one of them.
#
############################################################################################

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
- `ends_decorated::BitVector`: Whether a decoration is still in effect after each line, in
    which case it must be closed at the end of the row that shows the line.
"""
struct ViewLayout <: AbstractVector{String}
    lines::Vector{String}
    printable_widths::Vector{Int}
    plain_ascii::BitVector
    decorations::Vector{Decoration}
    ends_decorated::BitVector
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
    ends_decorated = falses(num_lines)
    state = Decoration()

    # Whether `state` has a decoration in effect.
    decorated = false

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
                state = update_decoration(state, line)
                decorated = !isempty(_carried_decoration(state))
            end
        end

        ends_decorated[i] = decorated
    end

    return ViewLayout(lines, printable_widths, plain_ascii, decorations, ends_decorated)
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
        source.ends_decorated[rows],
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

"""
    _carried_decoration(decoration::Decoration) -> String

Return the escape sequences that put the terminal in the state of `decoration`, the
decoration in effect before a line, or an empty string if nothing is in effect: the
attributes that are turned on, the colors that are not the default ones, and the hyperlink
that is open.

A row is not always written after the row above it. Hence, a decoration that begins in a
previous line must be written again at the beginning of each row it reaches.

# Arguments

- `decoration::Decoration`: Decoration state before a line.
"""
function _carried_decoration(decoration::Decoration)
    # The attributes that were turned off and the default colors are not carried. Notice
    # that the hyperlink is handled apart because the state only tells that it changed,
    # which is also true after it was closed.
    kept = drop_inactive_properties(decoration)

    sgr = String(
        Decoration(
            kept.foreground,
            kept.background,
            kept.bold,
            kept.faint,
            kept.italic,
            kept.reversed,
            kept.underline,
            kept.strikethrough,
            false,
            "",
            false,
        ),
    )

    isempty(kept.hyperlink_url) && return sgr

    return string(_HYPERLINK_OPEN, kept.hyperlink_url, _HYPERLINK_END, sgr)
end

"""
    _row_terminator(layout::ViewLayout, line::Int) -> String

Return the escape sequences that close the decoration still in effect after the row `line`
of `layout`, or an empty string if there is none. They are written at the end of the row, so
that the decoration does not reach the ruler, the scrollbar, nor the rows painted after it.

# Arguments

- `layout::ViewLayout`: Layout of the text.
- `line::Int`: Row of the layout.
"""
function _row_terminator(layout::ViewLayout, line::Int)
    layout.ends_decorated[line] || return ""

    # A reset does not close a hyperlink. Notice that the state after the line is computed
    # only for the rows that end with a decoration, which are few.
    state = update_decoration(layout.decorations[line], layout.lines[line])

    return isempty(state.hyperlink_url) ? _SGR_RESET : _HYPERLINK_CLOSE * _SGR_RESET
end
