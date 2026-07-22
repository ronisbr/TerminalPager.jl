"""
    run_fresh_process_benchmarks() -> Nothing

Measure package load, layout/config construction, and first/second views in fresh processes.
"""
function run_fresh_process_benchmarks()
    samples = parse(Int, get(ENV, "BENCHMARK_SAMPLES", "3"))
    worker = joinpath(@__DIR__, "fresh_process_worker.jl")
    project = dirname(Base.active_project())

    for compiled_modules in ("yes", "no")
        println("compiled modules: $compiled_modules")
        for sample in 1:samples
            command = `$(Base.julia_cmd()) --startup-file=no --project=$project \
                --compiled-modules=$compiled_modules $worker`
            values = split(strip(read(command, String)), '\t')
            println(
                "sample $sample: load=$(values[1]) s, layout=$(values[2]) s, " *
                "config=$(values[3]) s, first_view=$(values[4]) s, " *
                "second_view=$(values[5]) s",
            )
        end
    end

    return nothing
end

run_fresh_process_benchmarks()
