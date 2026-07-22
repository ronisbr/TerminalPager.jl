using BenchmarkTools
using PrettyTables
using Printf
using Statistics

"""
    format_duration(nanoseconds::Real) -> String

Format a duration in nanoseconds using the most readable unit for a terminal report.
"""
function format_duration(nanoseconds::Real)
    units = ((1.0, "ns"), (1_000.0, "μs"), (1_000_000.0, "ms"), (1_000_000_000.0, "s"))
    scale, unit = first(units)
    for candidate in units
        nanoseconds >= candidate[1] || break
        scale, unit = candidate
    end

    value = nanoseconds / scale
    digits = if value < 10
        2
    elseif value < 100
        1
    else
        0
    end
    return @sprintf("%.*f %s", digits, value, unit)
end

"""
    format_bytes(bytes::Real) -> String

Format a byte count using binary units suited to memory measurements.
"""
function format_bytes(bytes::Real)
    units = ((1.0, "B"), (1024.0, "KiB"), (1024.0^2, "MiB"), (1024.0^3, "GiB"))
    scale, unit = first(units)
    for candidate in units
        bytes >= candidate[1] || break
        scale, unit = candidate
    end

    value = bytes / scale
    digits = if value < 10
        2
    elseif value < 100
        1
    else
        0
    end
    return @sprintf("%.*f %s", digits, value, unit)
end

"""
    format_count(count::Integer) -> String

Format an integer count with grouping for quick scanning.
"""
function format_count(count::Integer)
    return replace(string(count), r"(?<=\d)(?=(?:\d{3})+$)" => ",")
end

"""
    benchmark_report_rows(results) -> Vector{NamedTuple}

Flatten BenchmarkTools results into deterministic, display-ready benchmark rows.
"""
function benchmark_report_rows(results)
    rows = NamedTuple[]
    for (path, trial) in BenchmarkTools.leaves(results)
        trial isa BenchmarkTools.Trial || continue
        path_parts = string.(path)
        estimate = median(trial)
        fastest = minimum(trial)
        group = length(path_parts) > 1 ? join(path_parts[1:(end - 1)], " › ") : "—"
        push!(
            rows,
            (
                path = join(path_parts, "\u001f"),
                group = group,
                benchmark = last(path_parts),
                median = time(estimate),
                minimum = time(fastest),
                memory = memory(trial),
                allocations = allocs(trial),
                samples = length(trial),
                evals = params(trial).evals,
            ),
        )
    end
    sort!(rows; by = row -> row.path)
    return rows
end

"""
    _report_table(io, data; title, subtitle, labels, alignment, color) -> Nothing

Render a compact, uncropped Unicode text table with optional terminal color.
"""
function _report_table(io::IO, data; title, subtitle, labels, alignment, color)
    table_io = IOContext(io, :color => color)
    table_data = Matrix{String}(undef, length(data), length(labels))
    for (row_id, row) in enumerate(data)
        for column_id in eachindex(labels)
            table_data[row_id, column_id] = string(row[column_id])
        end
    end
    table_format = TextTableFormat(;
        borders = text_table_borders__unicode_rounded,
        horizontal_line_after_data_rows = true,
        vertical_lines_at_data_columns = :none,
    )
    table_style = if color
        TextTableStyle(;
            title = crayon"bold fg:cyan",
            first_line_column_label = crayon"bold",
            column_label = crayon"fg:dark_gray",
            table_border = crayon"fg:dark_gray",
        )
    else
        TextTableStyle(; table_border = crayon"default")
    end
    pretty_table(
        table_io,
        table_data;
        backend = :text,
        title = title,
        subtitle = subtitle,
        column_labels = labels,
        alignment = alignment,
        column_label_alignment = alignment,
        fit_table_in_display_horizontally = false,
        fit_table_in_display_vertically = false,
        style = table_style,
        table_format = table_format,
    )
    return nothing
end

"""
    render_benchmark_report(io, results; color = false) -> Nothing

Render flattened BenchmarkTools suite results to `io` with explicit color control.
"""
function render_benchmark_report(io::IO, results; color = false)
    rows = benchmark_report_rows(results)
    data = [
        (
            row.group,
            row.benchmark,
            format_duration(row.median),
            format_duration(row.minimum),
            format_bytes(row.memory),
            format_count(row.allocations),
            format_count(row.samples),
            format_count(row.evals),
        ) for row in rows
    ]
    _report_table(
        io,
        data;
        title = "TerminalPager Benchmark Suite",
        subtitle = "Median and fastest sample; allocations and memory are per evaluation.",
        labels = [
            "Group / Path",
            "Benchmark",
            "Median",
            "Minimum",
            "Memory",
            "Allocs",
            "Samples",
            "Evals / Sample",
        ],
        alignment = [:l, :l, :r, :r, :r, :r, :r, :r],
        color = color,
    )
    return nothing
end

"""
    render_fresh_process_report(io, samples; color = false) -> Nothing

Render fresh-process timing samples to `io` without dropping any measured process.
"""
function render_fresh_process_report(io::IO, samples; color = false)
    sorted_samples = collect(samples)
    sort!(sorted_samples; by = sample -> (sample.compiled_modules, sample.sample))
    data = [
        (
            sample.compiled_modules,
            format_count(sample.sample),
            format_duration(sample.load_time * 1_000_000_000),
            format_duration(sample.layout_time * 1_000_000_000),
            format_duration(sample.config_time * 1_000_000_000),
            format_duration(sample.first_view_time * 1_000_000_000),
            format_duration(sample.repeated_view_time * 1_000_000_000),
        ) for sample in sorted_samples
    ]
    _report_table(
        io,
        data;
        title = "TerminalPager Fresh-Process Benchmarks",
        subtitle = "Every row is one new Julia process.",
        labels = [
            "Compiled Modules",
            "Sample",
            "Package Load",
            "Layout",
            "Config",
            "First View",
            "Repeated View",
        ],
        alignment = [:l, :r, :r, :r, :r, :r, :r],
        color = color,
    )
    return nothing
end
