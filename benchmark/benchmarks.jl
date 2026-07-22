using BenchmarkTools
using REPL
using TerminalPager

const SUITE = BenchmarkGroup()

"""
    make_pager(
        lines::AbstractVector{<:AbstractString};
        display_size::Tuple{Int, Int} = (25, 80),
    ) -> TerminalPager.Pager

Construct a pager suitable for noninteractive benchmarks.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Provide the text lines to display.

# Keywords

- `display_size::Tuple{Int, Int}`: Set the simulated terminal height and width.
"""
function make_pager(
    lines;
    display_size = (25, 80),
)
    benchmark_output = IOContext(stdout, :displaysize => display_size)
    term = REPL.Terminals.TTYTerminal("", stdin, benchmark_output, stderr)
    io = IOBuffer()
    buf = IOContext(io, :color => true)
    text_layout = TerminalPager.TextViewLayout(lines)
    return TerminalPager.Pager(
        term = term,
        buf = buf,
        display_config = TerminalPager._display_config(),
        display_size = display_size,
        num_lines = length(text_layout),
        text_layout = text_layout,
    )
end

"""
    benchmark_decode(
        prefix::Vector{UInt8},
        toggle::Threads.Atomic{UInt8},
    ) -> Tuple{Symbol, Union{Nothing, TerminalPager.Keystroke}, Int}

Decode a runtime-mutated prefix behind a noinline inference barrier.

# Arguments

- `prefix::Vector{UInt8}`: Provide the mutable encoded keystroke prefix.
- `toggle::Threads.Atomic{UInt8}`: Provide the atomic bit used to defeat constant
  propagation.
"""
Base.@noinline function benchmark_decode(
    prefix,
    toggle,
)
    original_byte = prefix[end]
    toggle_byte = Threads.atomic_xor!(toggle, UInt8(1)) & UInt8(1)
    prefix[end] = original_byte ⊻ toggle_byte
    key = TerminalPager._decode_keystroke(Base.inferencebarrier(prefix))
    prefix[end] = original_byte
    return key
end

"""
    benchmark_move_to_match!(
        pagerd::TerminalPager.Pager,
        match_ids::AbstractVector{<:Integer},
    ) -> Int

Repeatedly move through the search index and return the resulting viewport coordinates.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager whose active match and viewport to
  update.
- `match_ids::AbstractVector{<:Integer}`: Provide the ordered match identifiers to visit.
"""
Base.@noinline function benchmark_move_to_match!(
    pagerd,
    match_ids,
)
    checksum = 0
    for match_id in match_ids
        pagerd.active_search_match_id = match_id
        TerminalPager._move_view_to_match!(pagerd)
        checksum += pagerd.start_row + pagerd.start_column
    end
    return checksum
end

"""
    baseline_find_matches(
        text_layout::TerminalPager.TextViewLayout,
        regex::Regex,
    ) -> Tuple{TerminalPager.SearchMatches, Int}

Run the previous search-and-count construction path without ordered navigation metadata.

# Arguments

- `text_layout::TerminalPager.TextViewLayout`: Provide the prepared text layout to search.
- `regex::Regex`: Provide the regular expression to match.
"""
function baseline_find_matches(
    text_layout,
    regex,
)
    search_matches = TerminalPager.string_search_per_line(text_layout, regex)
    num_matches = sum(length, values(search_matches); init = 0)
    return search_matches, num_matches
end

"""
    retained_yank_assembly(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer},
    ) -> String

Assemble yank text using the retained cleaned-line vector from the previous candidate.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Provide the decorated source lines.
- `line_ids::AbstractVector{<:Integer}`: Provide the source line identifiers to assemble.
"""
function retained_yank_assembly(
    lines,
    line_ids,
)
    ids = sort!(unique!(collect(Int, line_ids)))
    selected_lines = [TerminalPager.remove_decorations(lines[id]) for id in ids]
    sizehint = sum(sizeof, selected_lines; init = 0) + length(selected_lines)
    buf = IOBuffer(sizehint = sizehint)
    for line in selected_lines
        write(buf, line, '\n')
    end
    return String(take!(buf))
end

"""
    process_navigation!(
        pagerd::TerminalPager.Pager,
        key::TerminalPager.Keystroke,
    ) -> Union{Nothing, Symbol}

Process one navigation key and update crop metrics as the production loop does.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update.
- `key::TerminalPager.Keystroke`: Provide the navigation keystroke to process.
"""
function process_navigation!(
    pagerd,
    key,
)
    old_row = pagerd.start_row
    old_column = pagerd.start_column
    action = TerminalPager._pager_key_process!(pagerd, key)
    TerminalPager._update_crop_after_action!(pagerd, old_row, old_column, action)
    return action
end

"""
    sequential_navigation_frame!(
        pagerd::TerminalPager.Pager,
        keys::AbstractVector{TerminalPager.Keystroke},
    ) -> Int

Process and render every key in a navigation burst.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update and render.
- `keys::AbstractVector{TerminalPager.Keystroke}`: Provide the navigation keystrokes to
  process.
"""
function sequential_navigation_frame!(
    pagerd,
    keys,
)
    for key in keys
        process_navigation!(pagerd, key)
        TerminalPager._view!(pagerd)
        take!(pagerd.buf.io)
    end
    return pagerd.start_row
end

"""
    coalesced_navigation_frame!(
        pagerd::TerminalPager.Pager,
        input_bytes::AbstractString,
        first_key::TerminalPager.Keystroke,
    ) -> Int

Process one coalesced burst and render only its final frame.

# Arguments

- `pagerd::TerminalPager.Pager`: Provide the pager state to update and render.
- `input_bytes::AbstractString`: Provide the buffered navigation input after the first key.
- `first_key::TerminalPager.Keystroke`: Provide the first navigation keystroke.
"""
function coalesced_navigation_frame!(
    pagerd,
    input_bytes,
    first_key,
)
    pagerd.input = TerminalPager.PagerInput(IOBuffer(input_bytes))
    action = process_navigation!(pagerd, first_key)
    count = TerminalPager._coalesce_navigation!(pagerd, action)
    TerminalPager._view!(pagerd)
    take!(pagerd.buf.io)
    return count
end

SUITE["preferences"] = BenchmarkGroup()
SUITE["preferences"]["access"] = @benchmarkable TerminalPager._get_preference(
    "active_search_decoration"
)
SUITE["preferences"]["session snapshot"] = @benchmarkable TerminalPager._display_config()

SUITE["input"] = BenchmarkGroup()
ascii_prefix = UInt8[UInt8('j')]
csi_prefix = collect(codeunits("\e[B"))
ascii_toggle = Threads.Atomic{UInt8}(0)
csi_toggle = Threads.Atomic{UInt8}(0)
SUITE["input"]["decode ASCII"] = @benchmarkable(
    benchmark_decode($ascii_prefix, $ascii_toggle),
    evals = 100
)
SUITE["input"]["decode CSI"] = @benchmarkable(
    benchmark_decode($csi_prefix, $csi_toggle),
    evals = 100
)
SUITE["input"]["single buffered key"] = @benchmarkable(
    TerminalPager._try_read_keystroke!(input),
    setup = (input = TerminalPager.PagerInput(IOBuffer("j"))),
    evals = 1
)

short_lines = ["row $i: αβγ " * repeat("text ", 30) for i in 1:100]
SUITE["view"] = BenchmarkGroup()
SUITE["layout"] = BenchmarkGroup()
layout_lines = ["row $i αβγ " * repeat("text ", 30) for i in 1:1_000]
SUITE["layout"]["construction"] = @benchmarkable TerminalPager.TextViewLayout($layout_lines)

SUITE["prepared view"] = BenchmarkGroup()
SUITE["prepared view"]["first view"] = @benchmarkable(
    TerminalPager._view!(pager),
    setup = (pager = make_pager($short_lines; display_size = (25, 80))),
    evals = 1
)
prepared_pager = make_pager(short_lines; display_size = (25, 80))
TerminalPager._view!(prepared_pager)
take!(prepared_pager.buf.io)
SUITE["prepared view"]["repeated view"] = @benchmarkable(
    TerminalPager._view!($prepared_pager),
    setup = begin
        truncate($prepared_pager.buf.io, 0)
        seekstart($prepared_pager.buf.io)
    end
)
SUITE["prepared view"]["layout + first view"] = @benchmarkable(
    begin
        pager = make_pager($short_lines; display_size = (25, 80))
        TerminalPager._view!(pager)
    end,
    evals = 1
)
short_pager = make_pager(["short αβγ", "second line"]; display_size = (25, 80))
SUITE["view"]["short"] = @benchmarkable TerminalPager._view!($short_pager) setup = (
    truncate($short_pager.buf.io, 0);
    seekstart($short_pager.buf.io)
)
for width in (40, 80, 160)
    pagerd = make_pager(short_lines; display_size = (25, width))
    SUITE["view"]["width $width"] = @benchmarkable TerminalPager._view!($pagerd) setup = (
        truncate($pagerd.buf.io, 0);
        seekstart($pagerd.buf.io)
    )
end

large_matches = TerminalPager.SearchMatches(
    i => [(1, 1)] for i in Iterators.reverse(1:100_000)
)
ordered_matches = TerminalPager._ordered_search_matches(large_matches, 100_000)
search_pager = make_pager(fill("x", 100_000); display_size = (25, 80))
search_pager.search_matches = large_matches
search_pager.ordered_search_matches = ordered_matches
search_pager.num_matches = length(ordered_matches)
search_pager.active_search_match_id = 50_000
movement_ids = [isodd(i) ? 1 : 100_000 for i in 1:100]
search_lines = fill("x", 100_000)
search_layout = TerminalPager.TextViewLayout(search_lines)
search_regex = r"x"
construction_pager = make_pager(search_lines; display_size = (25, 80))

SUITE["search"] = BenchmarkGroup()
SUITE["search"]["index 100k"] = @benchmarkable TerminalPager._ordered_search_matches(
    $large_matches,
    100_000
)
SUITE["search"]["baseline construction 100k"] = @benchmarkable baseline_find_matches(
    $search_layout,
    $search_regex
)

SUITE["wide prepared view"] = BenchmarkGroup()
for source_width in (100, 10_000, 100_000)
    positions = (("column 1", 1), ("midpoint", max(1, source_width ÷ 2)))
    for (position, start_column) in positions
        wide_pager = make_pager([repeat("x", source_width)]; display_size = (5, 80))
        wide_pager.start_column = start_column
        label = "width $source_width / $position"
        SUITE["wide prepared view"][label] = @benchmarkable(
            TerminalPager._view!($wide_pager),
            setup = begin
                truncate($wide_pager.buf.io, 0)
                seekstart($wide_pager.buf.io)
            end
        )
    end
end
SUITE["search"]["candidate construction 100k"] = @benchmarkable(
    TerminalPager._find_matches!($construction_pager, $search_regex),
    evals = 1
)
SUITE["search"]["far movement 100k (100 calls; report per call)"] = @benchmarkable(
    benchmark_move_to_match!($search_pager, $movement_ids),
    setup = begin
        $search_pager.start_row = 1
        $search_pager.start_column = 1
    end,
    evals = 1
)

yank_lines = ["\e[31mrow $i αβγ\e[0m" for i in 1:10_000]
yank_ids = collect(10_000:-2:1)
SUITE["yank assembly 10k"] = @benchmarkable TerminalPager._assemble_yank_text(
    $yank_lines,
    $yank_ids
)

large_yank_lines = [
    "\e[3$(i)m" * repeat(string(Char(Int('a') + i - 1)), 1024^2 - 9) * "\e[0m"
    for i in 1:8
]
large_yank_ids = collect(8:-1:1)
SUITE["yank 8 MiB"] = BenchmarkGroup()
SUITE["yank 8 MiB"]["retained-vector baseline"] = @benchmarkable retained_yank_assembly(
    $large_yank_lines,
    $large_yank_ids
)
SUITE["yank 8 MiB"]["streaming candidate"] = @benchmarkable(
    TerminalPager._assemble_yank_text($large_yank_lines, $large_yank_ids),
    evals = 1
)

SUITE["coalescing"] = BenchmarkGroup()
burst_lines = ["row $i α " * repeat("x", 40) for i in 1:500]
burst_keys = fill(TerminalPager.Keystroke(value = "j"), 100)
burst_input = repeat("j", 99)
sequential_pager = make_pager(burst_lines; display_size = (25, 80))
coalesced_pager = make_pager(burst_lines; display_size = (25, 80))
TerminalPager._view!(sequential_pager)
TerminalPager._view!(coalesced_pager)
take!(sequential_pager.buf.io)
take!(coalesced_pager.buf.io)
SUITE["coalescing"]["100 keys / 100 views"] = @benchmarkable(
    sequential_navigation_frame!($sequential_pager, $burst_keys),
    setup = begin
        $sequential_pager.start_row = 1
        $sequential_pager.cropped_lines = 476
    end,
    evals = 1
)
SUITE["coalescing"]["100 keys / final frame"] = @benchmarkable(
    coalesced_navigation_frame!(
        $coalesced_pager,
        $burst_input,
        TerminalPager.Keystroke(value = "j")
    ),
    setup = begin
        $coalesced_pager.start_row = 1
        $coalesced_pager.cropped_lines = 476
    end,
    evals = 1
)

auto_fit_lines = ["short α", "second line"]
SUITE["auto fit"] = @benchmarkable TerminalPager._pager_content_fits(
    $auto_fit_lines,
    (25, 80)
)

if abspath(PROGRAM_FILE) == @__FILE__
    display(run(SUITE; seconds = 1))
end
