using REPL

load_time = @elapsed Base.eval(Main, :(using TerminalPager))
lines = ["short αβγ", "second line"]
layout_time = @elapsed text_layout = TerminalPager.TextViewLayout(lines)
config_time = @elapsed config = TerminalPager._display_config()

term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
io = IOBuffer()
pagerd = TerminalPager.Pager(
    term = term,
    buf = IOContext(io, :color => true),
    display_config = config,
    display_size = (25, 80),
    num_lines = 2,
    text_layout = text_layout,
)

first_view_time = @elapsed TerminalPager._view!(pagerd)
truncate(pagerd.buf.io, 0)
seekstart(pagerd.buf.io)
second_view_time = @elapsed TerminalPager._view!(pagerd)

timings = (load_time, layout_time, config_time, first_view_time, second_view_time)
println(join(timings, '\t'))
