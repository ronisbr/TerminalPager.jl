## Description #############################################################################
#
# Tests for the incremental redraw.
#
############################################################################################

############################################################################################
#                                       Test Harness                                       #
############################################################################################

"""
    RedrawSink

Terminal output stream that records everything written to it and counts the bytes.

# Fields

- `data::IOBuffer`: Everything written to the stream.
- `bytes::Int`: Number of bytes written.
- `writes::Int`: Number of write calls.
- `color::Bool`: Value reported for the `:color` IO property.
"""
mutable struct RedrawSink <: IO
    data::IOBuffer
    bytes::Int
    writes::Int
    color::Bool
end

# The buffer is pre-grown, so that its own reallocation is not attributed to the redraw when
# measuring allocations.
RedrawSink(; color::Bool = false) =
    RedrawSink(IOBuffer(; sizehint = 1 << 22), 0, 0, color)

function Base.write(sink::RedrawSink, byte::UInt8)
    sink.bytes += 1
    sink.writes += 1
    return write(sink.data, byte)
end

function Base.unsafe_write(sink::RedrawSink, p::Ptr{UInt8}, n::UInt)
    sink.bytes += Int(n)
    sink.writes += 1
    return unsafe_write(sink.data, p, n)
end

Base.get(sink::RedrawSink, key::Symbol, default) =
    key === :color ? sink.color : default

"""
    FailingSink

Terminal output stream that throws while the frame payload is flushed, but accepts the short
cursor sequences around it.
"""
struct FailingSink <: IO end

Base.write(::FailingSink, ::UInt8) = 1

function Base.unsafe_write(::FailingSink, ::Ptr{UInt8}, n::UInt)
    n > 16 && error("write failed")
    return Int(n)
end

Base.get(::FailingSink, ::Symbol, default) = default

"""
    _take_output!(sink::RedrawSink) -> String

Return and clear everything written to `sink`, resetting its counters.

# Arguments

- `sink::RedrawSink`: Stream to drain.
"""
function _take_output!(sink::RedrawSink)
    output = String(take!(sink.data))
    sink.bytes = 0
    sink.writes = 0
    return output
end

"""
    _create_redraw_pagerd(lines::Vector{String}; display_size::NTuple{2, Int} = (10, 20),
        color::Bool = false) -> TerminalPager.Pager

Create a pager whose terminal output is a `RedrawSink`.

# Arguments

- `lines::Vector{String}`: Pager text, one entry per line.

# Keywords

- `display_size::NTuple{2, Int}`: Terminal rows and columns.
    (**Default**: `(10, 20)`)
- `color::Bool`: Render the view with ANSI escape sequences.
    (**Default**: `false`)
"""
function _create_redraw_pagerd(
    lines::Vector{String};
    display_size::NTuple{2, Int} = (10, 20),
    color::Bool = false,
)
    sink = RedrawSink(; color = color)
    input = IOBuffer()
    term = REPL.Terminals.TTYTerminal("", input, sink, sink)
    text_layout = TerminalPager.TextViewLayout(lines)

    return TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => color),
        display_size = display_size,
        input = TerminalPager.PagerInput(input),
        num_lines = length(text_layout),
        term = term,
        text_layout = text_layout,
    )
end

"""
    _paint!(pagerd::TerminalPager.Pager) -> String

Render and redraw `pagerd`, returning the bytes sent to the terminal.

# Arguments

- `pagerd::TerminalPager.Pager`: Pager state to paint.
"""
function _paint!(pagerd::TerminalPager.Pager)
    TerminalPager._view!(pagerd)
    TerminalPager._redraw!(pagerd)
    return _take_output!(pagerd.term.out_stream)
end

"""
    _emulate!(screen::Vector{String}, str::AbstractString) -> Vector{String}

Apply the terminal output `str` to `screen`.

This understands only the sequences the redraw path emits: `\\e[i;jH`, `\\e[0K`, `\\e[2J`,
SGR sequences, carriage returns, and line feeds.

# Arguments

- `screen::Vector{String}`: Emulated screen rows, updated in place.
- `str::AbstractString`: Bytes written to the terminal.
"""
function _emulate!(screen::Vector{String}, str::AbstractString)
    row = 1
    column = 1

    """
        _overwrite(line::String, column::Int, text::AbstractString) -> String

    Return `line` with `text` written at `column`, padding with spaces if necessary.
    """
    function _overwrite(line::String, column::Int, text::AbstractString)
        prefix = if length(line) >= column - 1
            first(line, column - 1)
        else
            line * ' '^(column - 1 - length(line))
        end
        suffix = length(line) > column - 1 + length(text) ?
            last(line, length(line) - (column - 1 + length(text))) : ""
        return prefix * text * suffix
    end

    i = firstindex(str)

    while i <= lastindex(str)
        character = str[i]

        if character == '\e'
            # A CSI sequence is `\e[`, the parameter bytes, and one final byte. Notice that we
            # must not use an anchored regular expression here, because `^` anchors to the
            # beginning of the string and not to the search offset.
            i + 1 <= lastindex(str) && str[i + 1] == '[' || (i = nextind(str, i); continue)

            k = i + 2
            while (k <= lastindex(str)) && (str[k] in "0123456789;?")
                k += 1
            end

            k > lastindex(str) && break

            parameters = str[(i + 2):(k - 1)]
            final = str[k]

            if final == 'H'
                parts = split(parameters, ';')
                row = isempty(parts[1]) ? 1 : parse(Int, parts[1])
                column = (length(parts) > 1) && !isempty(parts[2]) ? parse(Int, parts[2]) : 1

            elseif final == 'K'
                # Erase from the cursor through the end of the line.
                line = screen[row]
                screen[row] = length(line) >= column - 1 ? first(line, column - 1) : line

            elseif final == 'J'
                fill!(screen, "")
                row = 1
                column = 1
            end

            # Every other sequence (SGR, cursor visibility) does not move the cursor nor
            # change the text, so it is simply dropped.
            i = k + 1

        elseif character == '\r'
            column = 1
            i = nextind(str, i)

        elseif character == '\n'
            row += 1
            i = nextind(str, i)

        else
            j = i

            while (j <= lastindex(str)) && !(str[j] in ('\e', '\r', '\n'))
                j = nextind(str, j)
            end

            text = str[i:prevind(str, j)]
            screen[row] = _overwrite(screen[row], column, text)
            column += length(text)
            i = j
        end
    end

    return screen
end

############################################################################################
#                                    Allocation Loops                                      #
############################################################################################

# These must be top-level functions, otherwise `@allocated` measures the uncompiled version.

_loop_redraw(pagerd, n) = (for _ in 1:n
    TerminalPager._redraw!(pagerd)
end)

_loop_redraw_cmd_line(pagerd, n) = (for _ in 1:n
    TerminalPager._redraw_cmd_line!(pagerd)
end)

############################################################################################
#                                          Tests                                           #
############################################################################################

@testset "First Frame" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
    output = _paint!(pagerd)

    @test occursin("\e[?25l", output)
    @test occursin("\e[?25h", output)
    @test occursin("\e[1;1H", output)

    for i in 1:5
        @test occursin("line $i", output)
    end

    # The frame has 5 rows, and the display can show `10 - 1 = 9`. Hence, the four remaining
    # rows must be cleared.
    for i in 6:9
        @test occursin("\e[$i;1H", output)
    end

    @test pagerd.redraw == false
    @test pagerd.frame_cache.valid == true
    @test pagerd.frame_cache.num_rows == 5
end

@testset "Unchanged Frame" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
    _paint!(pagerd)

    # Nothing changed, so the redraw must not touch the terminal at all. Notice that this is
    # also what makes the cursor stop flickering when a keystroke does not move the view.
    @test isempty(_paint!(pagerd))
    @test pagerd.term.out_stream.writes == 0
    @test pagerd.redraw == false
end

@testset "Minimal Frame Difference" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    _paint!(pagerd)

    # Moving the visual line changes exactly two rows.
    TerminalPager._pager_key_process!(pagerd, TerminalPager.Keystroke(; value = "j"))
    output = _paint!(pagerd)

    # Rows 1 and 2 are adjacent, so they are painted as a single run with one cursor
    # movement followed by a carriage return and a line feed.
    @test length(collect(eachmatch(r"\e\[[0-9]+;1H", output))) == 1
    @test occursin("\r\n", output)
    @test length(output) < 200

    # A row that did not change must not be repainted.
    @test !occursin("line 4", output)
    @test occursin("line 1", output)
    @test occursin("line 2", output)
end

@testset "Shrinking Frame" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:8]; display_size = (10, 20))
    _paint!(pagerd)
    @test pagerd.frame_cache.num_rows == 8

    # Now show fewer rows by scrolling to the end.
    pagerd.start_row = 6
    output = _paint!(pagerd)

    @test pagerd.frame_cache.num_rows == 3

    # The rows that were painted before must be cleared, and no others.
    for i in 4:8
        @test occursin("\e[$i;1H", output)
    end
    @test !occursin("\e[9;1H", output)

    # Painting the same short frame again must clear nothing.
    TerminalPager._request_redraw!(pagerd)
    @test isempty(_paint!(pagerd))
end

@testset "Frame Invalidation" begin
    # A resize must force a full repaint, both when the terminal grows and when it shrinks.
    for new_size in ((14, 20), (6, 20))
        pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
        _paint!(pagerd)
        @test pagerd.frame_cache.valid == true

        pagerd.display_size = new_size
        TerminalPager._invalidate_frame!(pagerd)
        output = _paint!(pagerd)

        @test occursin("line 1", output)
        @test pagerd.frame_cache.valid == true
    end

    # `_update_display_size!` must invalidate the snapshot itself.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
    _paint!(pagerd)
    pagerd.display_size = (99, 99)
    TerminalPager._update_display_size!(pagerd)
    @test pagerd.frame_cache.valid == false
    @test pagerd.redraw == true

    # The nested pager opened by `:help` repaints the whole screen.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
    pagerd.features = [:help]
    _paint!(pagerd)
    pagerd.input = TerminalPager.PagerInput(IOBuffer("q"))
    pagerd.term = REPL.Terminals.TTYTerminal(
        "", pagerd.input.stream, pagerd.term.out_stream, pagerd.term.err_stream
    )
    pagerd.event = :help
    TerminalPager._pager_event_process!(pagerd)
    @test pagerd.frame_cache.valid == false

    # A failure while flushing must not leave a snapshot describing a half-painted screen.
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:5])
    _paint!(pagerd)
    pagerd.start_row = 2
    TerminalPager._view!(pagerd)
    failing = FailingSink()
    pagerd.term = REPL.Terminals.TTYTerminal("", pagerd.input.stream, failing, failing)
    @test_throws ErrorException TerminalPager._redraw!(pagerd)
    @test pagerd.frame_cache.valid == false
end

@testset "Incremental Redraw Equivalence" begin
    # This is the regression guard for the incremental redraw: driving two identical pagers
    # through the same actions, one always repainting everything and one painting only the
    # rows that changed, must leave byte-identical screens.
    lines = vcat(
        ["\e[3$(i % 8)mrow $i " * repeat("x", 30) * "\e[0m" for i in 1:40],
        ["short", "", "α界 wide", repeat("y", 60)],
    )
    actions = Union{String, Symbol}[
        "j", "j", "j", "k", "G", "g", "l", "l", "h", "\$", "0",
        :toggle_visual_mode, "j", :select_visual_mode_line, "j",
        :select_visual_mode_line, "k", :toggle_ruler, "j", "G", "g",
        :toggle_ruler, :toggle_visual_mode, "j",
    ]
    display_size = (12, 24)

    screens = map((false, true)) do incremental
        pagerd = _create_redraw_pagerd(lines; display_size = display_size, color = true)
        pagerd.features = [:help, :change_freeze, :visual_mode]
        pagerd.show_ruler = true
        screen = fill("", display_size[1] - 1)

        for action in actions
            if action isa Symbol
                pagerd.event = action
                TerminalPager._pager_event_process!(pagerd)
            else
                TerminalPager._pager_key_process!(
                    pagerd, TerminalPager.Keystroke(; value = action)
                )
            end

            TerminalPager._view!(pagerd)
            incremental || (pagerd.frame_cache.valid = false)
            TerminalPager._redraw!(pagerd)
            _emulate!(screen, _take_output!(pagerd.term.out_stream))
        end

        return screen
    end

    @test screens[1] == screens[2]

    # A sanity check on the harness itself: the emulated screen must show the text.
    @test any(line -> occursin("row", line), screens[2])
end

@testset "Redraw Allocations" begin
    pagerd = _create_redraw_pagerd(
        ["line $i " * repeat("x", 40) for i in 1:200]; display_size = (26, 80), color = true
    )
    pagerd.show_ruler = true
    TerminalPager._view!(pagerd)

    # Warm everything up and grow the reusable buffers.
    _loop_redraw(pagerd, 100)
    _loop_redraw_cmd_line(pagerd, 100)

    # An unchanged frame must not allocate at all.
    @test (@allocated _loop_redraw(pagerd, 500)) == 0

    # A changed frame must not allocate either, since every buffer is reused.
    pagerd.start_row = 5
    TerminalPager._view!(pagerd)
    TerminalPager._redraw!(pagerd)
    pagerd.start_row = 6
    TerminalPager._view!(pagerd)
    @test (@allocated TerminalPager._redraw!(pagerd)) < 512

    # The command line is constant except for the numbers in it.
    @test (@allocated _loop_redraw_cmd_line(pagerd, 500)) == 0

    # Every frame reaches the terminal in a single write. Otherwise, tearing is visible.
    _take_output!(pagerd.term.out_stream)
    pagerd.start_row = 20
    TerminalPager._view!(pagerd)
    TerminalPager._redraw!(pagerd)
    TerminalPager._redraw_cmd_line!(pagerd)

    # One write to hide the cursor, one for the frame, one to show it, and one for the
    # command line.
    @test pagerd.term.out_stream.writes == 4
end

@testset "Visual Mode Buffers" begin
    pagerd = _create_redraw_pagerd(["line $i" for i in 1:8]; display_size = (10, 20))
    pagerd.features = [:visual_mode]
    pagerd.visual_mode = true
    pagerd.visual_mode_line = 2
    append!(pagerd.visual_mode_selected_lines, [4, 6])

    TerminalPager._view!(pagerd)

    # The active line comes first, so that it keeps its own background.
    @test pagerd.visual_lines == [2, 4, 6]
    @test pagerd.visual_line_backgrounds == [
        pagerd.display_config.visual_mode_active_line_background,
        pagerd.display_config.visual_mode_line_background,
        pagerd.display_config.visual_mode_line_background,
    ]

    # The buffers must be reused instead of reallocated at every frame.
    lines_buffer = pagerd.visual_lines
    backgrounds_buffer = pagerd.visual_line_backgrounds
    pagerd.visual_mode_line = 3
    TerminalPager._view!(pagerd)

    @test pagerd.visual_lines === lines_buffer
    @test pagerd.visual_line_backgrounds === backgrounds_buffer
    @test pagerd.visual_lines == [3, 4, 6]

    # Leaving visual mode must not leave stale entries behind.
    pagerd.visual_mode = false
    TerminalPager._view!(pagerd)
    pagerd.visual_mode = true
    empty!(pagerd.visual_mode_selected_lines)
    TerminalPager._view!(pagerd)
    @test pagerd.visual_lines == [3]
end

@testset "Frame Byte Access" begin
    # `_frame_bytes` reads `IOBuffer` internals, which changed between Julia versions. This
    # must fail here rather than as corrupted output.
    io = IOBuffer()

    for text in ("", "a", "hello world", repeat("x", 10_000), "αβγ")
        truncate(io, 0)
        seekstart(io)
        write(io, text)

        data, num_bytes = TerminalPager._frame_bytes(io)
        @test num_bytes == ncodeunits(text)
        @test String(UInt8[data[i] for i in 1:num_bytes]) == text
    end

    # The storage must survive the truncate/seekstart reuse cycle.
    for _ in 1:200
        truncate(io, 0)
        seekstart(io)
        write(io, "cycle")
        data, num_bytes = TerminalPager._frame_bytes(io)
        @test num_bytes == 5
        @test String(UInt8[data[i] for i in 1:num_bytes]) == "cycle"
    end
end

@testset "Frame Row Scan" begin
    frame_cache = TerminalPager.FrameCache()

    """
        _scan(text::String, max_rows::Int) -> Vector{String}

    Return the rows `_scan_frame_rows!` finds in `text`.
    """
    function _scan(text::String, max_rows::Int)
        data = Vector{UInt8}(text)
        num_rows = TerminalPager._scan_frame_rows!(
            frame_cache, data, length(data), max_rows
        )
        return [
            String(data[frame_cache.new_first[i]:frame_cache.new_last[i]]) for i in 1:num_rows
        ]
    end

    # The rows must match `split(str, '\n')`, which is how the frame used to be split.
    for text in ("a\nb\nc", "a\nb\nc\n", "a", "", "\n\n", "\na\n")
        @test _scan(text, 100) == split(text, '\n')
    end

    # The scan must stop at the number of rows the display can show.
    @test _scan("a\nb\nc\nd", 2) == ["a", "b"]
end
