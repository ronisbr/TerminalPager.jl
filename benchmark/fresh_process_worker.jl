using REPL

load_time = @elapsed Base.eval(Main, :(using TerminalPager))
lines = ["short αβγ", "second line"]
layout_time = @elapsed text_layout = TerminalPager.TextViewLayout(lines)
config_time = @elapsed config = TerminalPager._display_config()

# The frame must not reach the real terminal, otherwise this worker would corrupt the report
# assembled by the parent process.
sink = IOContext(IOBuffer(), :color => true, :displaysize => (25, 80))
term = REPL.Terminals.TTYTerminal("", stdin, sink, sink)
io = IOBuffer()
pagerd = TerminalPager.Pager(;
    term = term,
    buf = IOContext(io, :color => true),
    display_config = config,
    display_size = (25, 80),
    num_lines = 2,
    text_layout = text_layout,
)

first_view_time = @elapsed TerminalPager._view!(pagerd)
first_redraw_time = @elapsed begin
    TerminalPager._redraw!(pagerd)
    TerminalPager._redraw_cmd_line!(pagerd)
end
second_view_time = @elapsed TerminalPager._view!(pagerd)

timings = (
    load_time,
    layout_time,
    config_time,
    first_view_time,
    first_redraw_time,
    second_view_time,
)
println(join(timings, '\t'))
