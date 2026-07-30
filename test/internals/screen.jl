## Description #############################################################################
#
# Tests for the escape sequence writers.
#
############################################################################################

"""
    _seq(f::Function, args...) -> String

Return the escape sequence `f` writes for `args`.

# Arguments

- `f::Function`: Escape sequence writer.
- `args...`: Arguments forwarded to `f`.
"""
function _seq(f::Function, args...)
    io = IOBuffer()
    n = f(io, args...)
    str = String(take!(io))
    @test n == ncodeunits(str)
    return str
end

@testset "Escape Sequences" begin
    @test _seq(TerminalPager._clear_to_eol) == "\e[0K"
    @test _seq(TerminalPager._hide_cursor) == "\e[?25l"
    @test _seq(TerminalPager._show_cursor) == "\e[?25h"
    @test _seq(TerminalPager._save_cursor) == "\e[s"
    @test _seq(TerminalPager._restore_cursor) == "\e[u"
    @test _seq(TerminalPager._turn_on_alternate_screen_buffer) == "\e[?1049h"
    @test _seq(TerminalPager._turn_off_alternate_screen_buffer) == "\e[?1049l"
    @test _seq(TerminalPager._turn_on_cursor_key_mode) == "\e[?1h"
    @test _seq(TerminalPager._turn_off_cursor_key_mode) == "\e[?1l"

    # Cursor movements are assembled from precomputed pieces. Hence, we must check the values
    # around the cache boundaries.
    max_row = TerminalPager._MAX_CACHED_ROW
    max_decimal = TerminalPager._MAX_CACHED_DECIMAL

    for i in (1, 2, 9, 10, max_row, max_row + 1, max_decimal, max_decimal + 1, 12345)
        @test _seq(TerminalPager._move_cursor, i, 1) == "\e[$i;1H"
        @test _seq(TerminalPager._move_cursor, 5, i) == "\e[5;$(i)H"
    end

    @test _seq(TerminalPager._move_cursor, 12, 34) == "\e[12;34H"
    @test _seq(TerminalPager._cursor_back) == "\e[1D"
    @test _seq(TerminalPager._cursor_forward) == "\e[1C"
    @test _seq(TerminalPager._cursor_back, 7) == "\e[7D"
    @test _seq(TerminalPager._cursor_forward, 1000) == "\e[1000C"

    for n in (0, 1, 9, 10, 99, 100, max_decimal, max_decimal + 1, typemax(Int))
        @test _seq(TerminalPager._write_decimal, n) == string(n)
    end

    # A negative value must not index the cache.
    @test _seq(TerminalPager._write_decimal, -5) == "-5"

    # `_clear_screen` must overwrite every display line by default, and use a single escape
    # sequence when `newlines` is requested.
    io = IOContext(IOBuffer(), :displaysize => (3, 10))
    TerminalPager._clear_screen(io)
    str = String(take!(io.io))
    @test str == "\e[1;1H\e[0K\e[2;1H\e[0K\e[3;1H\e[0K\e[1;1H"

    TerminalPager._clear_screen(io; newlines = true)
    @test String(take!(io.io)) == "\e[2J\e[1;1H"
end

############################################################################################
#                              Escape Sequence Allocation Loops                             #
############################################################################################

# These loops must be top-level functions. `@allocated` over a loop written inside a
# `@testset` measures the uncompiled, dynamically dispatched version and always reports
# spurious allocations.

_loop_clear_to_eol(io, n) = (for _ in 1:n
    TerminalPager._clear_to_eol(io)
end)
_loop_hide_cursor(io, n) = (for _ in 1:n
    TerminalPager._hide_cursor(io)
end)
_loop_show_cursor(io, n) = (for _ in 1:n
    TerminalPager._show_cursor(io)
end)
_loop_move_cursor_bol(io, n) = (for _ in 1:n
    TerminalPager._move_cursor(io, 12, 1)
end)
_loop_move_cursor(io, n) = (for _ in 1:n
    TerminalPager._move_cursor(io, 12, 34)
end)
_loop_cursor_back(io, n) = (for _ in 1:n
    TerminalPager._cursor_back(io, 1)
end)
_loop_cursor_forward(io, n) = (for _ in 1:n
    TerminalPager._cursor_forward(io, 1)
end)
_loop_write_decimal(io, n) = (for _ in 1:n
    TerminalPager._write_decimal(io, 42)
end)

"""
    _allocated_per_call(loop::Function, io::IOBuffer) -> Float64

Return the bytes `loop` allocates per iteration, after warming it up.

# Arguments

- `loop::Function`: Function writing an escape sequence `n` times.
- `io::IOBuffer`: Pre-grown output buffer, so that its own growth is not measured.
"""
function _allocated_per_call(loop::Function, io::IOBuffer)
    loop(io, 200)
    truncate(io, 0)
    seekstart(io)

    allocated = @allocated loop(io, 5000)

    truncate(io, 0)
    seekstart(io)

    return allocated / 5000
end

@testset "Escape Sequence Allocations" begin
    # The redraw path writes these sequences once per screen row. Building them with string
    # interpolation allocated roughly 640 bytes per cursor movement.
    io = IOBuffer(; sizehint = 1 << 20)

    for loop in (
        _loop_clear_to_eol,
        _loop_hide_cursor,
        _loop_show_cursor,
        _loop_move_cursor_bol,
        _loop_move_cursor,
        _loop_cursor_back,
        _loop_cursor_forward,
        _loop_write_decimal,
    )
        @test _allocated_per_call(loop, io) == 0
    end

    # Guard against reintroducing the interpolated form.
    source = read(joinpath(pkgdir(TerminalPager), "src", "screen.jl"), String)
    @test !occursin("\$(CSI)\$(", source)
end
