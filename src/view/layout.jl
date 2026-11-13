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

The lines of the layout are the ones that are shown, in which the tabs are expanded and the
characters and the escape sequences that would move the cursor or change the terminal are
removed. See [`_displayed_line`](@ref).

# Fields

- `lines::Vector{String}`: Lines of the text as they are shown.
- `printable_widths::Vector{Int}`: Printable width of each line.
- `plain_ascii::BitVector`: Whether each line has only printable ASCII characters, in which
    case its width is its number of bytes and it has no escape sequence.
- `decorations::Vector{Decoration}`: Decoration state in effect before each line,
    accumulated from the beginning of the text.
- `ends_decorated::BitVector`: Whether a decoration is still in effect after each line, in
    which case it must be closed at the end of the row that shows the line.
- `originals::Vector{String}`: Lines of the text as they were received, which are the ones
    that are copied, edited, and saved. A line that is shown as it was received is the same
    object in both vectors.
"""
struct ViewLayout <: AbstractVector{String}
    lines::Vector{String}
    printable_widths::Vector{Int}
    plain_ascii::BitVector
    decorations::Vector{Decoration}
    ends_decorated::BitVector
    originals::Vector{String}
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
    originals = Vector{String}(undef, num_lines)
    printable_widths = Vector{Int}(undef, num_lines)
    plain_ascii = falses(num_lines)
    decorations = Vector{Decoration}(undef, num_lines)
    ends_decorated = falses(num_lines)
    state = Decoration()

    # Whether `state` has a decoration in effect.
    decorated = false

    for (i, input_line) in enumerate(input_lines)
        line = String(input_line)
        originals[i] = line
        decorations[i] = state

        # A line with only printable ASCII characters is shown as it is. For the other
        # ones, the line that is shown can be different.
        _is_plain_ascii(line) || (line = _displayed_line(line))
        lines[i] = line

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

    return ViewLayout(
        lines, printable_widths, plain_ascii, decorations, ends_decorated, originals
    )
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
        source.originals[rows],
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

# Number of columns between two tab stops.
const _TAB_WIDTH = 8

"""
    _displayed_line(line::String) -> String

Return `line` as it is shown by the pager, which is `line` itself if nothing must be
changed:

- A tab is replaced by the blanks up to the next tab stop, which are `_TAB_WIDTH` columns
    apart.
- The other control characters, like the carriage return of a text with CRLF line endings,
    are removed.
- The escape sequences are removed, except the ones that decorate the text: the SGR
    sequences and the hyperlinks (OSC 8).

The terminal would handle those characters and sequences by moving the cursor, erasing
text, or changing its own state, whereas the pager must know the column of every character
it writes. Otherwise, the rows are wider than expected and wrap, or they are overwritten.

# Arguments

- `line::String`: Line of the text.
"""
function _displayed_line(line::String)
    last_index = ncodeunits(line)

    # Fast path: almost every line has no control character but the ones of its SGR
    # sequences, in which case it is shown as it is.
    _needs_cleaning(line) || return line

    buf = IOBuffer(; sizehint = last_index + 2 * _TAB_WIDTH)

    # Number of printable columns written so far, which defines the next tab stop.
    column = 0
    index = 1

    while index <= last_index
        byte = codeunit(line, index)

        if byte == 0x1b
            sequence_end = _escape_sequence_end(line, index)

            # An escape character that does not begin a complete sequence is removed alone.
            if sequence_end == 0
                index += 1
                continue
            end

            _is_decoration_sequence(line, index, sequence_end) &&
                write(buf, SubString(line, index, sequence_end))

            index = sequence_end + 1

        elseif byte == UInt8('\t')
            num_blanks = _TAB_WIDTH - column % _TAB_WIDTH
            _write_blanks(buf, num_blanks)
            column += num_blanks
            index += 1

        elseif (byte < 0x20) || (byte == 0x7f)
            index += 1

        else
            c = line[index]
            write(buf, c)
            column += textwidth(c)
            index = nextind(line, index)
        end
    end

    return String(take!(buf))
end

"""
    _needs_cleaning(line::String) -> Bool

Return whether `line` has something that [`_displayed_line`](@ref) changes: a control
character other than the escape, or an escape sequence that is not a decoration.

# Arguments

- `line::String`: Line of the text.
"""
function _needs_cleaning(line::String)
    last_index = ncodeunits(line)
    index = 1

    while index <= last_index
        byte = codeunit(line, index)

        if byte == 0x1b
            sequence_end = _escape_sequence_end(line, index)
            _is_decoration_sequence(line, index, sequence_end) || return true
            index = sequence_end + 1
        elseif (byte < 0x20) || (byte == 0x7f)
            return true
        else
            index += 1
        end
    end

    return false
end

"""
    _escape_sequence_end(line::String, index::Int) -> Int

Return the byte index of the last character of the escape sequence of `line` that begins
with the escape character at the byte index `index`, or `0` if the sequence is not
complete. The sequences are the control sequences (CSI), the operating system commands (OSC)
terminated by BEL or by ST, and the ones with two characters.

# Arguments

- `line::String`: Line of the text.
- `index::Int`: Byte index of an escape character.
"""
function _escape_sequence_end(line::String, index::Int)
    last_index = ncodeunits(line)
    index < last_index || return 0

    introducer = codeunit(line, index + 1)
    i = index + 2

    if introducer == UInt8('[')
        # Parameter characters, intermediate characters, and one final character.
        while (i <= last_index) && (0x30 <= codeunit(line, i) <= 0x3f)
            i += 1
        end

        while (i <= last_index) && (0x20 <= codeunit(line, i) <= 0x2f)
            i += 1
        end

        return ((i <= last_index) && (0x40 <= codeunit(line, i) <= 0x7e)) ? i : 0

    elseif introducer == UInt8(']')
        # The command ends at BEL or at ST, which is an escape character followed by a
        # backslash. It cannot have any other control character.
        while i <= last_index
            byte = codeunit(line, i)
            byte == 0x07 && return i

            if byte == 0x1b
                has_terminator = (i < last_index) && (codeunit(line, i + 1) == UInt8('\\'))
                return has_terminator ? i + 1 : 0
            end

            ((byte < 0x20) || (byte == 0x7f)) && return 0
            i += 1
        end

        return 0
    end

    return (0x40 <= introducer <= 0x5f) ? index + 1 : 0
end

"""
    _is_decoration_sequence(line::String, first_index::Int, last_index::Int) -> Bool

Return whether the escape sequence of `line` from the byte index `first_index` to
`last_index` decorates the text, that is, whether it is an SGR sequence or a hyperlink
(OSC 8). It is `false` if `last_index` is `0`, which means that the sequence is not
complete.

# Arguments

- `line::String`: Line of the text.
- `first_index::Int`: Byte index of the escape character of the sequence.
- `last_index::Int`: Byte index of the last character of the sequence, or `0`.
"""
function _is_decoration_sequence(line::String, first_index::Int, last_index::Int)
    last_index == 0 && return false
    introducer = codeunit(line, first_index + 1)

    if introducer == UInt8('[')
        # An SGR sequence ends with `m`, and its parameters are not private.
        codeunit(line, last_index) == UInt8('m') || return false
        return !(UInt8('<') <= codeunit(line, first_index + 2) <= UInt8('?'))
    end

    # A hyperlink begins with `\e]8;;`.
    return (introducer == UInt8(']')) &&
           (last_index >= first_index + 5) &&
           (codeunit(line, first_index + 2) == UInt8('8')) &&
           (codeunit(line, first_index + 3) == UInt8(';')) &&
           (codeunit(line, first_index + 4) == UInt8(';'))
end
