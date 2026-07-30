## Description #############################################################################
#
# Tests for shared pager input, pure decoding, and navigation coalescing.
#
############################################################################################

"""
    ControlledInput

Represent an input stream with controllable lookahead and read failures.

# Fields

- `data::Vector{UInt8}`: Store the bytes available to the stream.
- `position::Int`: Track the next byte to read.
- `advertised::Int`: Track the number of bytes advertised as available.
- `reads::Int`: Count completed byte reads.
- `unsupported::Bool`: Indicate whether lookahead throws an unsupported error.
- `strict::Bool`: Reject reads of bytes that were not advertised when `true`.
- `fail_read::Bool`: Force byte reads to fail when `true`.
"""
mutable struct ControlledInput <: IO
    data::Vector{UInt8}
    position::Int
    advertised::Int
    reads::Int
    unsupported::Bool
    strict::Bool
    fail_read::Bool
end

"""
    ControlledInput(
        data::Union{AbstractString, AbstractVector{UInt8}};
        advertised::Int = 0,
        unsupported::Bool = false,
        strict::Bool = true,
        fail_read::Bool = false,
    ) -> ControlledInput

Construct an input stream with controllable lookahead and read failures.

# Arguments

- `data::Union{AbstractString, AbstractVector{UInt8}}`: Provide the input bytes.

# Keywords

- `advertised::Int`: Set the initial number of advertised bytes.
    (**Default**: `0`)
- `unsupported::Bool`: Make lookahead unsupported.
    (**Default**: `false`)
- `strict::Bool`: Require each read byte to be advertised.
    (**Default**: `true`)
- `fail_read::Bool`: Make byte reads fail.
    (**Default**: `false`)
"""

ControlledInput(
    data; advertised = 0, unsupported = false, strict = true, fail_read = false
) = ControlledInput(
    data isa AbstractString ? collect(codeunits(data)) : collect(UInt8, data),
    1,
    advertised,
    0,
    unsupported,
    strict,
    fail_read,
)

"""
    Base.bytesavailable(io::ControlledInput) -> Int

Return the number of advertised bytes remaining in the controlled input.

# Arguments

- `io::ControlledInput`: Provide the controlled input to inspect.
"""
function Base.bytesavailable(io::ControlledInput)
    io.unsupported && throw(ArgumentError("lookahead unsupported"))
    return min(io.advertised, length(io.data) - io.position + 1)
end

"""
    Base.read(io::ControlledInput, byte_type::Type{UInt8}) -> UInt8

Read one advertised byte from the controlled input.

# Arguments

- `io::ControlledInput`: Provide the controlled input to read.
- `byte_type::Type{UInt8}`: Select an unsigned byte read.
"""
function Base.read(io::ControlledInput, ::Type{UInt8})
    io.strict && io.advertised <= 0 && error("unadvertised read")
    io.fail_read && error("controlled read failure")
    io.position > length(io.data) && throw(EOFError())
    byte = io.data[io.position]
    io.position += 1
    io.reads += 1
    io.advertised = max(0, io.advertised - 1)
    return byte
end

"""
    RecordingOutput

Represent an output stream that records writes and fails on selected text.

# Fields

- `data::IOBuffer`: Store bytes written to the stream.
- `fail_on::String`: Select text that triggers a controlled failure.
- `failed::Bool`: Record whether the controlled failure has occurred.
"""
mutable struct RecordingOutput <: IO
    data::IOBuffer
    fail_on::String
    failed::Bool
end

"""
    Base.displaysize(output::RecordingOutput) -> Tuple{Int, Int}

Return the fixed display size used by output restoration tests.

# Arguments

- `output::RecordingOutput`: Provide the recording output queried for its display size.
"""
Base.displaysize(::RecordingOutput) = (10, 40)

"""
    Base.write(io::RecordingOutput, bytes::Vector{UInt8}) -> Int

Write bytes to the recording output and trigger its configured failure.

# Arguments

- `io::RecordingOutput`: Provide the recording output to update.
- `bytes::Vector{UInt8}`: Provide the bytes to write.
"""
function Base.write(io::RecordingOutput, bytes::Vector{UInt8})
    text = String(copy(bytes))
    written = write(io.data, bytes)
    if !io.failed && occursin(io.fail_on, text)
        io.failed = true
        throw(ErrorException("controlled output failure"))
    end
    return written
end

"""
    Base.write(io::RecordingOutput, byte::UInt8) -> Int

Write one byte to the recording output.

# Arguments

- `io::RecordingOutput`: Provide the recording output to update.
- `byte::UInt8`: Provide the byte to write.
"""
Base.write(io::RecordingOutput, byte::UInt8) = write(io, UInt8[byte])

"""
    Base.unsafe_write(
        io::RecordingOutput,
        pointer::Ptr{UInt8},
        count::UInt,
    ) -> UInt

Copy bytes from a pointer into the recording output.

# Arguments

- `io::RecordingOutput`: Provide the recording output to update.
- `pointer::Ptr{UInt8}`: Provide the pointer to the source bytes.
- `count::UInt`: Provide the number of bytes to copy.
"""
function Base.unsafe_write(io::RecordingOutput, pointer::Ptr{UInt8}, count::UInt)
    bytes = copy(unsafe_wrap(Vector{UInt8}, pointer, Int(count)))
    write(io, bytes)
    return count
end

"""
    key_fields(key::TerminalPager.Keystroke) -> Tuple{String, Bool, Bool, Bool}

Return the decoded value and modifier fields of a keystroke.

# Arguments

- `key::TerminalPager.Keystroke`: Provide the keystroke to inspect.
"""
key_fields(key) = (key.value, key.alt, key.ctrl, key.shift)

@testset "Pure Keystroke Decoder" begin
    for (code, expected) in TerminalPager.keycodes
        bytes = collect(codeunits(code))
        status, key, _ = TerminalPager._decode_keystroke(bytes)
        @test status == :complete
        @test key_fields(key) == key_fields(expected)

        for prefix_length in 1:(length(bytes) - 1)
            prefix = bytes[1:prefix_length]
            status, key, _ = TerminalPager._decode_keystroke(prefix)
            if haskey(TerminalPager.keycodes, String(prefix))
                @test status == :complete
                @test !isnothing(key)
            else
                @test status == :incomplete
                @test isnothing(key)
            end
        end
    end

    for (byte, value) in (
        (0x04, "<eot>"),
        (0x09, "<tab>"),
        (0x0a, "<enter>"),
        (0x0d, "<enter>"),
        (0x15, "<shiftin>"),
        (0x7f, "<backspace>"),
        (UInt8('a'), "a"),
    )
        status, key, _ = TerminalPager._decode_keystroke(UInt8[byte])
        @test status == :complete
        @test key.value == value
    end

    for character in ('¢', '€', '😀')
        bytes = collect(codeunits(string(character)))
        for prefix_length in 1:(length(bytes) - 1)
            @test first(TerminalPager._decode_keystroke(bytes[1:prefix_length])) ==
                :incomplete
        end
        status, key, _ = TerminalPager._decode_keystroke(bytes)
        @test status == :complete
        @test key.value == string(character)
    end

    for bytes in (
        UInt8[0x80],
        UInt8[0xc0, 0x80],
        UInt8[0xe0, 0x80, 0x80],
        UInt8[0xed, 0xa0, 0x80],
        UInt8[0xf4, 0x90, 0x80, 0x80],
        UInt8[0xf5],
    )
        status, key, _ = TerminalPager._decode_keystroke(bytes)
        @test status == :complete
        @test key.value == "<undefined>"
    end

    @test first(TerminalPager._decode_keystroke(collect(codeunits("\e[")))) == :incomplete
    status, key, _ = TerminalPager._decode_keystroke(collect(codeunits("\e[99X")))
    @test status == :complete
    @test key.value == "<undefined>"
    status, key, _ = TerminalPager._decode_keystroke(fill(UInt8('x'), 32))
    @test status == :complete
    @test key.value == "<undefined>"

    status, key, consumed = TerminalPager._decode_keystroke(collect(codeunits("\e[Bq")))
    @test status == :complete
    @test key.value == "<down>"
    @test consumed == 3

    for scalar in ("q", "é", "界", "😀")
        status, key, consumed = TerminalPager._decode_keystroke(
            collect(codeunits("\e" * scalar * "X"))
        )
        @test status == :complete
        @test key.value == scalar
        @test key.alt
        @test consumed == sizeof(scalar) + 1
    end

    status, key, consumed = TerminalPager._decode_keystroke(UInt8[0x1b, 0xf5, 0x58])
    @test status == :complete
    @test key.value == "<undefined>"
    @test consumed == 2
    @test first(TerminalPager._decode_keystroke(UInt8[0x1b, 0xe2])) == :incomplete
end

@testset "Controlled Shared Input" begin
    stream = ControlledInput("a"; advertised = 0)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test stream.reads == 0

    stream.advertised = 1
    key = TerminalPager._try_read_keystroke!(input)
    @test key.value == "a"
    @test stream.reads == 1

    stream = ControlledInput("\e"; advertised = 1)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test input.prefix == UInt8[0x1b]
    @test TerminalPager._read_keystroke!(input).value == "<esc>"

    stream = ControlledInput("\eq"; advertised = 2)
    input = TerminalPager.PagerInput(stream)
    key = TerminalPager._try_read_keystroke!(input)
    @test key.value == "q"
    @test key.alt

    input = TerminalPager.PagerInput(IOBuffer())
    input.prefix = collect(codeunits("ab"))
    @test TerminalPager._read_keystroke!(input).value == "a"
    @test input.prefix == UInt8[UInt8('b')]
    @test TerminalPager._read_keystroke!(input).value == "b"

    input.prefix = collect(codeunits("\e[Bq"))
    @test TerminalPager._read_keystroke!(input).value == "<down>"
    @test input.prefix == UInt8[UInt8('q')]
    @test TerminalPager._read_keystroke!(input).value == "q"

    input.prefix = UInt8[0x1b]
    input.pending = TerminalPager.Keystroke(; value = "pending")
    @test TerminalPager._read_keystroke!(input).value == "pending"
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test input.prefix == UInt8[0x1b]

    alt_utf8 = "\e😀X"
    stream = ControlledInput(alt_utf8; advertised = sizeof(alt_utf8))
    input = TerminalPager.PagerInput(stream)
    key = TerminalPager._try_read_keystroke!(input)
    @test key.value == "😀"
    @test key.alt
    @test stream.advertised == 1
    @test TerminalPager._try_read_keystroke!(input).value == "X"

    stream = ControlledInput(UInt8[0x1b, 0xe2]; advertised = 2)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test input.prefix == UInt8[0x1b, 0xe2]

    stream = ControlledInput("x"; advertised = 1, fail_read = true)
    input = TerminalPager.PagerInput(stream)
    @test_throws ErrorException TerminalPager._try_read_keystroke!(input)
    @test input.can_lookahead

    stream = ControlledInput("a"; unsupported = true)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test !input.can_lookahead
    @test stream.reads == 0

    stream = ControlledInput("\e[B"; advertised = 2)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    @test input.prefix == collect(codeunits("\e["))
    stream.advertised = 1
    @test TerminalPager._try_read_keystroke!(input).value == "<down>"
    @test stream.reads == 3

    stream = ControlledInput("€"; advertised = 2)
    input = TerminalPager.PagerInput(stream)
    @test isnothing(TerminalPager._try_read_keystroke!(input))
    stream.advertised = 1
    @test TerminalPager._try_read_keystroke!(input).value == "€"

    stream = ControlledInput("abcd"; advertised = 4)
    input = TerminalPager.PagerInput(stream)
    @test TerminalPager._try_read_keystroke!(input).value == "a"
    @test stream.reads == 1
    @test stream.advertised == 3

    input.pending = TerminalPager.Keystroke(; value = "pending")
    @test TerminalPager._read_keystroke!(input).value == "pending"
    @test stream.reads == 1

    @test TerminalPager._jlgetch(IOBuffer("\e[B")).value == "<down>"
    @test TerminalPager._jlgetch(IOBuffer("\e")).value == "<esc>"
end

"""
    process_with_crop!(
        pagerd::TerminalPager.Pager,
        key::TerminalPager.Keystroke,
    ) -> Union{Nothing, Symbol}

Process one key and update the pager crop metrics.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update.
- `key::TerminalPager.Keystroke`: Provide the keystroke to process.
"""
function process_with_crop!(pagerd, key)
    old_row = pagerd.start_row
    old_column = pagerd.start_column
    action = TerminalPager._pager_key_process!(pagerd, key)
    TerminalPager._update_crop_after_action!(pagerd, old_row, old_column, action)
    return action
end

"""
    coalesce_navigation!(
        pagerd::TerminalPager.Pager,
        action::Union{Nothing, Symbol};
        max_actions::Int = 128,
        max_ns::UInt64 = UInt64(4_000_000),
    ) -> Int

Coalesce buffered navigation while retaining the pager's fixed test display size.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update.
- `action::Union{Nothing, Symbol}`: Provide the first candidate navigation action.

# Keywords

- `max_actions::Int`: Limit the number of navigation actions in one batch.
    (**Default**: `128`)
- `max_ns::UInt64`: Limit the nanoseconds spent collecting one batch.
    (**Default**: `UInt64(4_000_000)`)
"""
function coalesce_navigation!(pagerd, action; kwargs...)
    return TerminalPager._coalesce_navigation!(
        pagerd, action; display_size_function = _ -> pagerd.display_size, kwargs...
    )
end

"""
    process_and_view!(
        pagerd::TerminalPager.Pager,
        key::TerminalPager.Keystroke,
    ) -> Tuple{Union{Nothing, Symbol}, String}

Process one key and return its action with the rendered frame.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update and render.
- `key::TerminalPager.Keystroke`: Provide the keystroke to process.
"""
function process_and_view!(pagerd, key)
    action = process_with_crop!(pagerd, key)
    TerminalPager._view!(pagerd)
    frame = String(take!(pagerd.buf.io))
    return action, frame
end

"""
    drain_batched_views!(
        pagerd::TerminalPager.Pager,
        first_key::TerminalPager.Keystroke,
    ) -> Tuple{Vector{String}, Vector{Int}}

Drain buffered navigation into rendered frames and batch counts.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update and render.
- `first_key::TerminalPager.Keystroke`: Provide the first buffered keystroke.
"""
function drain_batched_views!(pagerd, first_key)
    key = first_key
    frames = String[]
    counts = Int[]
    while !isnothing(key)
        action = process_with_crop!(pagerd, key)
        push!(counts, coalesce_navigation!(pagerd, action))
        TerminalPager._view!(pagerd)
        push!(frames, String(take!(pagerd.buf.io)))
        key = TerminalPager._try_read_keystroke!(pagerd.input)
    end
    return frames, counts
end

"""
    assert_sequential_equivalent(
        lines::AbstractVector{<:AbstractString},
        display_size::Tuple{Int, Int},
        start_row::Int,
        start_column::Int,
        input::AbstractString,
    ) -> Nothing

Assert that sequential and coalesced navigation produce equivalent final states.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Provide the source lines to display.
- `display_size::Tuple{Int, Int}`: Provide the simulated terminal dimensions.
- `start_row::Int`: Provide the initial viewport row.
- `start_column::Int`: Provide the initial viewport column.
- `input::AbstractString`: Provide the navigation input to compare.
"""
function assert_sequential_equivalent(lines, display_size, start_row, start_column, input)
    sequential = _create_pagerd(join(lines, '\n'))
    batched = _create_pagerd(join(lines, '\n'))
    for pager in (sequential, batched)
        pager.display_size = display_size
        pager.start_row = start_row
        pager.start_column = start_column
        TerminalPager._view!(pager)
        take!(pager.buf.io)
    end

    keys = [TerminalPager.Keystroke(; value = string(character)) for character in input]
    sequential_frames = [last(process_and_view!(sequential, key)) for key in keys]
    batched.input = TerminalPager.PagerInput(IOBuffer(input[2:end]))
    batched_frames, _ = drain_batched_views!(batched, keys[1])

    @test batched.start_row == sequential.start_row
    @test batched.start_column == sequential.start_column
    @test batched.cropped_lines == sequential.cropped_lines
    @test batched.cropped_columns == sequential.cropped_columns
    @test batched_frames[end] == sequential_frames[end]
    return nothing
end

@testset "Navigation Coalescing" begin
    stream = ControlledInput("jjqX"; advertised = 4)
    pagerd = _create_pagerd(join(fill("line", 100), '\n'))
    pagerd.input = TerminalPager.PagerInput(stream)
    pagerd.display_size = (10, 20)
    pagerd.cropped_lines = 91

    first_key = TerminalPager._try_read_keystroke!(pagerd.input)
    first_action = process_with_crop!(pagerd, first_key)
    @test coalesce_navigation!(pagerd, first_action) == 2
    @test pagerd.start_row == 3
    @test pagerd.cropped_lines == 89
    @test pagerd.input.pending.value == "q"
    @test stream.position == 4
    @test TerminalPager._read_keystroke!(pagerd.input).value == "q"
    @test stream.position == 4
    @test TerminalPager._try_read_keystroke!(pagerd.input).value == "X"

    # Opposite directions and home/end remain sequentially equivalent.
    keys = [TerminalPager.Keystroke(; value = value) for value in ("j", "j", "k", "G", "g")]
    sequential = _create_pagerd(join(fill("line", 100), '\n'))
    batched = _create_pagerd(join(fill("line", 100), '\n'))
    for pager in (sequential, batched)
        pager.display_size = (10, 20)
        pager.cropped_lines = 91
    end
    sequential_frames = [last(process_and_view!(sequential, key)) for key in keys]
    batched.input = TerminalPager.PagerInput(IOBuffer("jkGg"))
    batched_frames, counts = drain_batched_views!(batched, keys[1])
    @test counts == [2, 1, 1, 1]
    @test batched.start_row == sequential.start_row
    @test batched.cropped_lines == sequential.cropped_lines
    @test batched_frames[end] == sequential_frames[end]

    # Other-axis input is retained as a boundary.
    batched.input = TerminalPager.PagerInput(IOBuffer("jl"))
    first_action = process_with_crop!(batched, TerminalPager.Keystroke(; value = "j"))
    @test coalesce_navigation!(batched, first_action) == 2
    @test batched.input.pending.value == "l"

    # Custom bindings are classified by action rather than physical key.
    old_binding = get(TerminalPager._KEYBINDINGS, ("z", false, false, false), nothing)
    try
        TerminalPager._KEYBINDINGS[("z", false, false, false)] = :fastdown
        @test TerminalPager._pager_action(TerminalPager.Keystroke(; value = "z")) ==
            :fastdown
        @test TerminalPager._navigation_axis(:fastdown) == :vertical
    finally
        if isnothing(old_binding)
            delete!(TerminalPager._KEYBINDINGS, ("z", false, false, false))
        else
            TerminalPager._KEYBINDINGS[("z", false, false, false)] = old_binding
        end
    end

    limit_stream = ControlledInput(repeat("j", 200); advertised = 200)
    limited = _create_pagerd(join(fill("line", 300), '\n'))
    limited.input = TerminalPager.PagerInput(limit_stream)
    limited.display_size = (10, 20)
    limited.cropped_lines = 291
    first_action = process_with_crop!(
        limited, TerminalPager._try_read_keystroke!(limited.input)
    )
    @test coalesce_navigation!(limited, first_action) == 128
    @test limit_stream.reads == 128

    deadline_stream = ControlledInput("jj"; advertised = 2)
    deadline = _create_pagerd(join(fill("line", 20), '\n'))
    deadline.input = TerminalPager.PagerInput(deadline_stream)
    first_action = process_with_crop!(
        deadline, TerminalPager._try_read_keystroke!(deadline.input)
    )
    @test coalesce_navigation!(deadline, first_action; max_ns = UInt64(0)) == 1
    @test deadline_stream.reads == 1

    # Rich rendered state remains identical after sequential and batched movement.
    rich_lines = [
        isodd(i) ? "\e[31mrow $i α界\e[0m" : "row $i " * repeat("x", i % 11) for i in 1:60
    ]
    sequential = _create_pagerd(join(rich_lines, '\n'))
    batched = _create_pagerd(join(rich_lines, '\n'))
    for pager in (sequential, batched)
        pager.display_size = (12, 24)
        pager.frozen_rows = 1
        pager.frozen_columns = 1
        pager.title_rows = 1
        pager.show_ruler = true
        pager.visual_mode = true
        pager.start_row = 2
        pager.start_column = 2
        TerminalPager._find_matches!(pager, r"row")
        TerminalPager._view!(pager)
        take!(pager.buf.io)
    end
    rich_keys = [TerminalPager.Keystroke(; value = value) for value in ("j", "j", "k")]
    rich_sequential_frames = [last(process_and_view!(sequential, key)) for key in rich_keys]
    batched.input = TerminalPager.PagerInput(IOBuffer("jk"))
    batched_layout = batched.text_layout
    rich_batched_frames, counts = drain_batched_views!(batched, rich_keys[1])
    @test counts == [2, 1]
    @test rich_batched_frames[end] == rich_sequential_frames[end]
    @test batched.text_layout === batched_layout

    horizontal_keys = [
        TerminalPager.Keystroke(; value = value) for value in ("l", "l", "h", "\$", "0")
    ]
    sequential = _create_pagerd(repeat("wide α界 ", 20))
    batched = _create_pagerd(repeat("wide α界 ", 20))
    for pager in (sequential, batched)
        pager.display_size = (10, 20)
        pager.start_column = 10
        pager.frozen_columns = 2
        pager.cropped_columns = 80
    end
    horizontal_frames = [
        last(process_and_view!(sequential, key)) for key in horizontal_keys
    ]
    batched.input = TerminalPager.PagerInput(IOBuffer("lh\$0"))
    batched_frames, counts = drain_batched_views!(batched, horizontal_keys[1])
    @test counts == [2, 1, 1, 1]
    @test batched.start_column == sequential.start_column
    @test batched.cropped_columns == sequential.cropped_columns
    @test batched_frames[end] == horizontal_frames[end]

    geometry_stream = ControlledInput("jj"; advertised = 2)
    geometry = _create_pagerd(join(fill("line", 20), '\n'))
    geometry.input = TerminalPager.PagerInput(geometry_stream)
    first_key = TerminalPager._try_read_keystroke!(geometry.input)
    first_action = process_with_crop!(geometry, first_key)
    @test TerminalPager._coalesce_navigation!(
        geometry,
        first_action;
        display_size_function = _ ->
            (geometry.display_size[1] + 1, geometry.display_size[2]),
    ) == 1
    @test geometry_stream.reads == 1

    # On a real terminal, the display size is a `TIOCGWINSZ` system call. It must be queried
    # once per burst, not once per coalesced action, otherwise it consumes a noticeable part of
    # the time budget and reduces how many keystrokes can be coalesced.
    size_queries = 0
    counting = _create_pagerd(join(fill("line", 200), '\n'))
    counting.input = TerminalPager.PagerInput(
        ControlledInput(repeat("j", 40); advertised = 40)
    )
    counting.cropped_lines = 180
    counting_key = TerminalPager._try_read_keystroke!(counting.input)
    counting_action = process_with_crop!(counting, counting_key)
    coalesced = TerminalPager._coalesce_navigation!(
        counting,
        counting_action;
        display_size_function = stream -> begin
            size_queries += 1
            return counting.display_size
        end,
    )

    @test coalesced > 1
    @test size_queries == 1

    # Stale viewport positions at short-line and enlarged-display edges use a real view
    # after every reference action.
    assert_sequential_equivalent(
        ["short", "\e[31mwide α界 $(repeat("x", 40))\e[0m"], (8, 20), 1, 45, "lh"
    )
    assert_sequential_equivalent(fill("row α", 8), (20, 30), 8, 1, "jk")
end

@testset "Shared Modal and Nested Input" begin
    command_input = IOBuffer("query\n")
    command_output = IOBuffer()
    command_term = REPL.Terminals.TTYTerminal(
        "", command_input, command_output, command_output
    )
    text_layout = TerminalPager.TextViewLayout(["x", "y"])
    pagerd = TerminalPager.Pager(;
        term = command_term,
        buf = IOContext(IOBuffer(), :color => false),
        input = TerminalPager.PagerInput(command_input),
        display_size = (10, 40),
        num_lines = 2,
        text_layout = text_layout,
    )
    @test TerminalPager._read_cmd!(pagerd) == "query"
    @test pagerd.input.stream === pagerd.term.in_stream

    help_input = IOBuffer("q")
    help_output = IOBuffer()
    help_term = REPL.Terminals.TTYTerminal("", help_input, help_output, help_output)
    pagerd.term = help_term
    pagerd.input = TerminalPager.PagerInput(help_input)
    help_layout = pagerd.text_layout
    TerminalPager._help!(pagerd)
    @test position(help_input) == 1
    @test pagerd.text_layout === help_layout
    @test collect(pagerd.text_layout) == ["x", "y"]

    """
        set_modal_input!(
            pager::TerminalPager.Pager,
            text::AbstractString,
        ) -> IOBuffer

    Replace a pager's terminal and shared input with modal test input.

    # Arguments

    - `pager::TerminalPager.Pager`: Provide the pager state to update.
    - `text::AbstractString`: Provide the replacement modal input.
    """
    function set_modal_input!(pager, text)
        stream = IOBuffer(text)
        output = IOBuffer()
        pager.term = REPL.Terminals.TTYTerminal("", stream, output, output)
        pager.input = TerminalPager.PagerInput(stream)
        return stream
    end

    set_modal_input!(pagerd, "x\n")
    pagerd.event = :search
    @test TerminalPager._pager_event_process!(pagerd)
    @test pagerd.mode == :searching

    set_modal_input!(pagerd, "1\n2\n")
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test (pagerd.frozen_rows, pagerd.frozen_columns) == (1, 2)

    set_modal_input!(pagerd, "bad\nx")
    pagerd.event = :change_freeze
    @test TerminalPager._pager_event_process!(pagerd)
    @test isnothing(pagerd.input.pending)

    set_modal_input!(pagerd, "bad\nx")
    pagerd.event = :change_title_rows
    @test TerminalPager._pager_event_process!(pagerd)
    @test isnothing(pagerd.input.pending)

    wrong_input = TerminalPager.PagerInput(IOBuffer("q"))
    @test_throws ArgumentError TerminalPager._pager!(
        pagerd.term, "help"; input = wrong_input
    )
end

@testset "Auto-Fit and Terminal Restoration" begin
    fit_lines = ["short", "α"]
    fit_layout = TerminalPager.TextViewLayout(fit_lines)
    @test @inferred(TerminalPager._pager_content_fits(fit_lines, (5, 20)))
    @test @inferred(TerminalPager._pager_content_fits(fit_layout, (5, 20)))
    @test TerminalPager._pager_content_fits(fit_layout, (5, 20)) ==
        TerminalPager._pager_content_fits(fit_lines, (5, 20))
    for (lines, display_size) in ((["too wide"], (5, 3)), (fill("x", 4), (5, 20)))
        layout = TerminalPager.TextViewLayout(lines)
        @test TerminalPager._pager_content_fits(layout, display_size) ==
            TerminalPager._pager_content_fits(lines, display_size) ==
            false
    end

    old_stdout = stdout
    output_buffer = IOBuffer()
    fit_output = IOContext(output_buffer, :displaysize => (10, 40), :color => false)
    hook_calls = Symbol[]
    try
        Base.eval(:(stdout = $fit_output))
        TerminalPager.pager(
            "fits";
            auto = true,
            _display_config_loader = () -> push!(hook_calls, :config),
            _input_factory = stream -> push!(hook_calls, :input),
            _layout_factory = lines -> push!(hook_calls, :layout),
            _terminal_factory = () -> push!(hook_calls, :terminal),
            _raw_runner = (f, terminal) -> push!(hook_calls, :raw),
        )
    finally
        Base.eval(:(stdout = $old_stdout))
    end
    @test String(take!(output_buffer)) == "fits"
    @test isempty(hook_calls)

    layout_calls = Ref(0)
    pager_input = IOBuffer("q")
    pager_output = IOContext(IOBuffer(), :displaysize => (8, 30), :color => false)
    pager_term = REPL.Terminals.TTYTerminal("", pager_input, pager_output, pager_output)
    auto_fit_stdout = IOContext(IOBuffer(), :displaysize => (8, 30), :color => false)
    try
        Base.eval(:(stdout = $auto_fit_stdout))
        TerminalPager._pager(
            join(fill("long line", 40), '\n');
            auto = true,
            _display_config_loader = TerminalPager.DisplayConfig,
            _input_factory = stream -> TerminalPager.PagerInput(pager_input),
            _layout_factory = lines -> begin
                layout_calls[] += 1
                return TerminalPager.TextViewLayout(lines)
            end,
            _terminal_factory = () -> pager_term,
            _raw_runner = (f, terminal) -> f(),
        )
    finally
        Base.eval(:(stdout = $old_stdout))
    end
    @test layout_calls[] == 1

    raw_transitions = Bool[]
    @test_throws ErrorException TerminalPager._with_raw_mode(
        () -> error("raw callback failure"),
        :terminal;
        raw_function = (terminal, enabled) -> push!(raw_transitions, enabled),
    )
    @test raw_transitions == [true, false]

    empty!(raw_transitions)
    @test_throws ErrorException TerminalPager._with_raw_mode(
        () -> nothing,
        :terminal;
        raw_function = (terminal, enabled) -> begin
            push!(raw_transitions, enabled)
            enabled && error("raw activation failure")
        end,
    )
    @test raw_transitions == [true, false]

    output = RecordingOutput(IOBuffer(), "\e[?1h", false)
    input_stream = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input_stream, output, output)
    @test_throws ErrorException TerminalPager._pager!(
        term, "long"; input = TerminalPager.PagerInput(input_stream)
    )
    @test occursin("\e[?1l", String(take!(output.data)))

    output = RecordingOutput(IOBuffer(), "\e[?1049h", false)
    input_stream = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input_stream, output, output)
    @test_throws ErrorException TerminalPager._pager!(
        term,
        "long";
        input = TerminalPager.PagerInput(input_stream),
        use_alternate_screen_buffer = true,
    )
    activation_output = String(take!(output.data))
    @test occursin("\e[?1049l", activation_output)
    @test occursin("\e[?1l", activation_output)

    output = RecordingOutput(IOBuffer(), "\e[2J", false)
    input_stream = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input_stream, output, output)
    @test_throws ErrorException TerminalPager._pager!(
        term, "long"; input = TerminalPager.PagerInput(input_stream)
    )
    @test occursin("\e[?1h", String(take!(output.data)))

    output = RecordingOutput(IOBuffer(), "\e[?25l", false)
    input_stream = IOBuffer("q")
    term = REPL.Terminals.TTYTerminal("", input_stream, output, output)
    @test_throws ErrorException TerminalPager._pager!(
        term,
        "long";
        input = TerminalPager.PagerInput(input_stream),
        use_alternate_screen_buffer = true,
    )
    restored_output = String(take!(output.data))
    @test occursin("\e[?25h", restored_output)
    alternate_off = findfirst("\e[?1049l", restored_output)
    cursor_key_off = findfirst("\e[?1l", restored_output)
    @test !isnothing(alternate_off)
    @test !isnothing(cursor_key_off)
    if !isnothing(alternate_off) && !isnothing(cursor_key_off)
        @test first(alternate_off) < first(cursor_key_off)
    end

    failing_input = ControlledInput("q"; advertised = 1, fail_read = true)
    output = RecordingOutput(IOBuffer(), "never-match", false)
    term = REPL.Terminals.TTYTerminal("", failing_input, output, output)
    @test_throws ErrorException TerminalPager._pager!(
        term,
        "long";
        input = TerminalPager.PagerInput(failing_input),
        use_alternate_screen_buffer = true,
    )
    failure_output = String(take!(output.data))
    @test occursin("\e[?1049l", failure_output)
    @test occursin("\e[?1l", failure_output)
end
