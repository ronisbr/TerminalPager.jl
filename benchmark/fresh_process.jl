"""
    run_fresh_process_benchmarks() -> Nothing

Measure package load, layout/config construction, and first/second views in fresh processes.
"""
function run_fresh_process_benchmarks()
    samples = parse(Int, get(ENV, "BENCHMARK_SAMPLES", "3"))
    worker = joinpath(@__DIR__, "fresh_process_worker.jl")
    project = dirname(Base.active_project())
    results = NamedTuple[]

    for compiled_modules in ("yes", "no")
        for sample in 1:samples
            command = `$(Base.julia_cmd()) --startup-file=no --project=$project \
                --compiled-modules=$compiled_modules $worker`
            values = split(strip(read(command, String)), '\t')
            length(values) == 5 || error("Unexpected fresh-process worker output.")
            timings = parse.(Float64, values)
            push!(
                results,
                (
                    compiled_modules = compiled_modules,
                    sample = sample,
                    load_time = timings[1],
                    layout_time = timings[2],
                    config_time = timings[3],
                    first_view_time = timings[4],
                    repeated_view_time = timings[5],
                ),
            )
        end
    end

    render_fresh_process_report(stdout, results; color = get(stdout, :color, false))
    return nothing
end

include("reporting.jl")

run_fresh_process_benchmarks()
