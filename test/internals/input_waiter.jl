## Description #############################################################################
#
# Tests for the waiter of the input and of the display size.
#
############################################################################################

"""
    ResizableOutput

Represent an output stream whose display size can change while it is used.

# Fields

- `data::Vector{UInt8}`: Bytes written to the stream.
- `size::Tuple{Int, Int}`: Display size reported by the stream.
"""
mutable struct ResizableOutput <: IO
    data::Vector{UInt8}
    size::Tuple{Int, Int}
end

"""
    ResizableOutput(size::Tuple{Int, Int}) -> ResizableOutput

Create an empty output stream that reports the display size `size`.

# Arguments

- `size::Tuple{Int, Int}`: Initial display size.
"""
ResizableOutput(size::Tuple{Int, Int}) = ResizableOutput(UInt8[], size)

"""
    Base.displaysize(io::ResizableOutput) -> Tuple{Int, Int}

Return the current display size of `io`.

# Arguments

- `io::ResizableOutput`: Output stream to inspect.
"""
Base.displaysize(io::ResizableOutput) = io.size

"""
    Base.write(io::ResizableOutput, byte::UInt8) -> Int

Append `byte` to the bytes written to `io`.

# Arguments

- `io::ResizableOutput`: Output stream to update.
- `byte::UInt8`: Byte to write.
"""
Base.write(io::ResizableOutput, byte::UInt8) = (push!(io.data, byte); 1)

"""
    Base.unsafe_write(io::ResizableOutput, pointer::Ptr{UInt8}, count::UInt) -> UInt

Append the `count` bytes at `pointer` to the bytes written to `io`.

# Arguments

- `io::ResizableOutput`: Output stream to update.
- `pointer::Ptr{UInt8}`: Pointer to the source bytes.
- `count::UInt`: Number of bytes to write.
"""
function Base.unsafe_write(io::ResizableOutput, pointer::Ptr{UInt8}, count::UInt)
    append!(io.data, unsafe_wrap(Vector{UInt8}, pointer, Int(count)))
    return count
end

"""
    _output_text(io::ResizableOutput) -> String

Return everything written to `io` so far.

# Arguments

- `io::ResizableOutput`: Output stream to inspect.
"""
_output_text(io::ResizableOutput) = String(copy(io.data))

"""
    _linked_pipe() -> Pipe

Create a pipe whose write end, `in`, feeds its read end, `out`.
"""
function _linked_pipe()
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    return pipe
end

"""
    _fetch_within(task::Task, seconds::Real) -> Any

Return the result of `task`, throwing an error if it does not finish within `seconds`.

# Arguments

- `task::Task`: Task to wait for.
- `seconds::Real`: Maximum time to wait [s].
"""
function _fetch_within(task::Task, seconds::Real)
    timedwait(() -> istaskdone(task), seconds) == :ok || error("The task did not finish.")
    return fetch(task)
end

"""
    _create_waiter_pagerd(stream::IO, output::ResizableOutput) -> TerminalPager.Pager

Create a pager that reads `stream` and writes to `output`, with a waiter polling the display
size of `output` every 10 ms.

# Arguments

- `stream::IO`: Input stream of the pager.
- `output::ResizableOutput`: Output stream of the pager.
"""
function _create_waiter_pagerd(stream::IO, output::ResizableOutput)
    term = REPL.Terminals.TTYTerminal("", stream, output, output)
    input = TerminalPager.PagerInput(stream)
    input.waiter = TerminalPager._create_input_waiter(stream, output; interval = 0.01)

    return TerminalPager.Pager(;
        buf = IOContext(IOBuffer(), :color => false),
        display_size = displaysize(output),
        input = input,
        num_lines = 1,
        term = term,
        text_layout = TerminalPager.TextViewLayout(["x"]),
    )
end

@testset "Input Waiter" begin
    pipe = _linked_pipe()
    output = ResizableOutput((10, 40))
    pagerd = _create_waiter_pagerd(pipe.out, output)
    input = pagerd.input
    waiter = input.waiter

    try
        # The wait lasts until a keystroke arrives, which is left to the pager task.
        task = @async TerminalPager._wait_for_input!(pagerd)
        sleep(0.05)
        @test !istaskdone(task)
        write(pipe.in, "j")
        @test _fetch_within(task, 5) === true
        @test !waiter.armed
        @test TerminalPager._read_keystroke!(input).value == "j"

        # A buffered keystroke is read without releasing the reader task.
        write(pipe.in, "ab")
        @test _fetch_within(@async(TerminalPager._wait_for_input!(pagerd)), 5) === true
        @test TerminalPager._read_keystroke!(input).value == "a"
        @test TerminalPager._wait_for_input!(pagerd)
        @test !waiter.armed
        @test TerminalPager._read_keystroke!(input).value == "b"

        # A change of the display size ends the wait without a keystroke.
        task = @async TerminalPager._wait_for_input!(pagerd)
        sleep(0.05)
        output.size = (20, 50)
        @test _fetch_within(task, 5) === false
        @test waiter.armed

        # A keystroke that arrives while the screen is repainted is reported by the next
        # wait.
        TerminalPager._update_display_size!(pagerd)
        @test pagerd.display_size == (20, 50)
        write(pipe.in, "k")
        @test _fetch_within(@async(TerminalPager._wait_for_input!(pagerd)), 5) === true
        @test TerminalPager._read_keystroke!(input).value == "k"
    finally
        TerminalPager._close_input_waiter!(input)
    end

    # Closing the waiter stops its timer and its reader task.
    @test isnothing(input.waiter)
    @test !isopen(waiter.timer)
    @test timedwait(() -> istaskdone(waiter.reader), 5.0) == :ok

    # Without a waiter, the keystroke is read directly.
    @test TerminalPager._wait_for_input!(pagerd)

    close(pipe)
end

@testset "Input Waiter Closed While Waiting" begin
    # A reader task that waits for the input when the waiter is closed exits after the next
    # byte arrives, and it leaves that byte to whoever reads the stream next.
    pipe = _linked_pipe()
    output = ResizableOutput((10, 40))
    pagerd = _create_waiter_pagerd(pipe.out, output)
    waiter = pagerd.input.waiter

    task = @async TerminalPager._wait_for_input!(pagerd)
    sleep(0.05)
    output.size = (11, 40)
    @test _fetch_within(task, 5) === false

    TerminalPager._close_input_waiter!(pagerd.input)
    sleep(0.05)
    @test !istaskdone(waiter.reader)

    write(pipe.in, "q")
    @test timedwait(() -> istaskdone(waiter.reader), 5.0) == :ok
    @test read(pipe.out, UInt8) == UInt8('q')

    close(pipe)
end

@testset "Default Input Waiter" begin
    # Only a terminal can be resized, so other streams are read directly, and no task or
    # timer is started for them.
    term = REPL.Terminals.TTYTerminal("", IOBuffer(), IOBuffer(), IOBuffer())
    @test isnothing(TerminalPager._default_input_waiter(term))
end

@testset "Repaint After a Resize" begin
    # The pager used to block while reading the input, so a resized terminal was repainted
    # only after the next keystroke.
    pipe = _linked_pipe()
    output = ResizableOutput((10, 30))
    term = REPL.Terminals.TTYTerminal("", pipe.out, output, output)
    input = TerminalPager.PagerInput(pipe.out)
    waiters = TerminalPager.InputWaiter[]

    factory = _ -> begin
        waiter = TerminalPager._create_input_waiter(pipe.out, output; interval = 0.01)
        push!(waiters, waiter)
        return waiter
    end

    session = @async TerminalPager._pager!(
        term,
        join(("line $i" for i in 1:50), '\n');
        input = input,
        use_alternate_screen_buffer = false,
        _waiter_factory = factory,
    )

    # Return a function telling whether the pager wrote `text`.
    wrote(text) = () -> occursin(text, _output_text(output))

    try
        @test timedwait(wrote("line 9"), 5.0) == :ok
        @test !wrote("line 19")()

        output.size = (20, 30)
        @test timedwait(wrote("line 19"), 5.0) == :ok

        # The prompt is moved to the new last row as well.
        write(pipe.in, "/")
        @test timedwait(wrote("\e[20;1H\e[0K\e[?25h/"), 5.0) == :ok
        output.size = (25, 30)
        @test timedwait(wrote("\e[25;1H\e[0K\e[?25h/"), 5.0) == :ok
        @test wrote("line 24")()

        # A lone ESC is read as the key only when no other byte follows it at once.
        write(pipe.in, "\e")
        sleep(0.2)

        # The help session shares the waiter of its parent.
        write(pipe.in, "?")
        @test timedwait(wrote("TerminalPager.jl"), 5.0) == :ok
        write(pipe.in, "q")
        write(pipe.in, "q")
        @test isnothing(_fetch_within(session, 5))
    finally
        istaskdone(session) || close(pipe)
    end

    # The session closed the only waiter it created.
    @test length(waiters) == 1
    @test isnothing(input.waiter)
    @test timedwait(() -> istaskdone(only(waiters).reader), 5.0) == :ok

    close(pipe)
end
