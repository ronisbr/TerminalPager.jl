using BenchmarkTools

include("reporting.jl")

suite = BenchmarkGroup()
suite["smoke"]["addition"] = @benchmark 1 + 1 samples = 1 evals = 1

suite_io = IOBuffer()
render_benchmark_report(suite_io, suite; color = false)
suite_output = String(take!(suite_io))
@assert occursin("TerminalPager Benchmark Suite", suite_output)
@assert occursin("addition", suite_output)
@assert !occursin('\e', suite_output)

fresh_io = IOBuffer()
fresh_samples = [(
    compiled_modules = "no",
    sample = 1,
    load_time = 1.0,
    layout_time = 0.01,
    config_time = 0.001,
    first_view_time = 0.0001,
    first_redraw_time = 0.00005,
    repeated_view_time = 0.00001,
),]
render_fresh_process_report(fresh_io, fresh_samples; color = false)
fresh_output = String(take!(fresh_io))
@assert occursin("Fresh-Process", fresh_output)
@assert occursin("First Redraw", fresh_output)
@assert occursin("Repeated View", fresh_output)
@assert !occursin('\e', fresh_output)

println("Benchmark reporting smoke check passed.")
