## Description #############################################################################
#
# Functions that wait for the input of a pager session or for a change of the terminal
# display size, whichever comes first. Without them, the pager blocks while reading the
# input, and a resized terminal is only repainted after the next keystroke.
#
############################################################################################

"""
    _create_input_waiter(stream::IO, out::IO; interval::Float64 = 0.1) -> InputWaiter

Create a waiter for the input of `stream` and for the changes of the display size of `out`,
starting its reader task and its timer. The waiter must be closed with
[`_close_input_waiter!`](@ref).

# Arguments

- `stream::IO`: Input stream of the pager session.
- `out::IO`: Output stream whose display size is polled.

# Keywords

- `interval::Float64`: Number of seconds between two queries of the display size [s].
    (**Default**: `0.1`)
"""
function _create_input_waiter(stream::IO, out::IO; interval::Float64 = 0.1)
    waiter = InputWaiter()
    waiter.reader = @async _run_input_waiter_reader(waiter, stream)

    # The timer keeps its own copy of the last display size, so that it shares nothing with
    # the pager task but the event. Notice that its callback can run on another thread.
    last_size = Ref(displaysize(out)::Tuple{Int, Int})

    waiter.timer = Timer(interval; interval = interval) do _
        size = try
            displaysize(out)::Tuple{Int, Int}
        catch
            # A terminal that can no longer be queried has nothing to report. The session
            # notices it when it writes to the terminal.
            return nothing
        end

        if size != last_size[]
            last_size[] = size
            notify(waiter.wake)
        end

        return nothing
    end

    return waiter
end

"""
    _default_input_waiter(term::REPL.Terminals.TTYTerminal) -> Union{Nothing, InputWaiter}

Create a waiter for the input and the display size of `term` if both of its streams are
terminals, or return `nothing` so that the input is read directly.

# Arguments

- `term::REPL.Terminals.TTYTerminal`: Terminal of the pager session.
"""
function _default_input_waiter(@nospecialize(term::REPL.Terminals.TTYTerminal))
    in_stream = term.in_stream
    out_stream = term.out_stream

    # Only a terminal can be resized. Other streams, such as the ones of the tests and of
    # the precompile workload, are read directly, so that no task or timer is started for
    # them.
    (in_stream isa Base.TTY) && (out_stream isa Base.TTY) || return nothing

    # On Windows, the display size of a pseudo terminal, such as the one of mintty, is
    # obtained by running `stty`, which would spawn a process at every query of the timer.
    @static if Sys.iswindows()
        Base.ispty(out_stream) && return nothing
    end

    return _create_input_waiter(in_stream, out_stream)
end

"""
    _close_input_waiter!(input::PagerInput) -> Nothing

Close the waiter of `input`, if any, stopping its timer and its reader task, and remove it
from `input`.

# Arguments

- `input::PagerInput`: Input state whose waiter is closed.
"""
function _close_input_waiter!(input::PagerInput)
    waiter = input.waiter
    isnothing(waiter) && return nothing

    input.waiter = nothing
    @atomic waiter.closed = true
    close(waiter.timer)

    # A reader waiting to be released exits at once. A reader waiting for the input exits
    # after the next byte arrives, and it never consumes that byte.
    notify(waiter.release)

    return nothing
end

"""
    _wait_for_input!(pagerd::Pager) -> Bool

Wait until the input of `pagerd` has a keystroke to read, returning `true`, or until the
display size of its terminal differs from the one recorded in `pagerd`, returning `false`.
Without a waiter in the input, return `true` at once, so that the keystroke is read
directly.

# Arguments

- `pagerd::Pager`: Pager state whose input and terminal are watched.
"""
function _wait_for_input!(pagerd::Pager)
    input = pagerd.input
    waiter = input.waiter
    isnothing(waiter) && return true

    # The reader task is released to wait for the next input only when nothing is buffered.
    # It stays released after a change of the display size, so that the input it sees
    # meanwhile is reported by the next call.
    if !waiter.armed
        _has_buffered_input(input) && return true
        waiter.armed = true
        notify(waiter.release)
    end

    out = pagerd.term.out_stream

    # The conditions are checked again after every notification, so that a notification
    # that arrived before this call is not lost.
    while true
        if @atomic waiter.input_seen
            @atomic waiter.input_seen = false
            waiter.armed = false
            return true
        end

        displaysize(out)::Tuple{Int, Int} != pagerd.display_size && return false
        wait(waiter.wake)
    end
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _run_input_waiter_reader(waiter::InputWaiter, stream::IO) -> Nothing

Run the reader task of `waiter`: whenever it is released, wait for the input of `stream`
without consuming it, and report it through `waiter`. Return when `waiter` is closed or when
`stream` ends.

# Arguments

- `waiter::InputWaiter`: Waiter that releases the task and receives the reports.
- `stream::IO`: Input stream to watch.
"""
function _run_input_waiter_reader(waiter::InputWaiter, stream::IO)
    while true
        wait(waiter.release)
        (@atomic waiter.closed) && return nothing

        # `eof` returns when a byte arrives or when the stream ends, without consuming any
        # byte. An error is reported as input as well, so that the pager task reads the
        # stream and throws it as it did without the waiter.
        at_end = try
            eof(stream)
        catch
            true
        end

        @atomic waiter.input_seen = true
        notify(waiter.wake)

        at_end && return nothing
    end
end
