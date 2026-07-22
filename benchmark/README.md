# Benchmarks

The benchmarks use a dedicated environment, so BenchmarkTools and PrettyTables are not
production runtime dependencies. From the package root, instantiate that environment and run
the suite:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=benchmark benchmark/benchmarks.jl
```

The suite report is a stable, flattened table. It groups each benchmark path and shows median,
minimum, memory, allocations, samples, and evaluations per sample. Times and memory use
adaptive units for easier scanning.

The search movement case alternates between the first and last of 100,000 matches for 100
calls. Divide its reported time by 100 for per-call latency. The construction group compares
the complete `_find_matches!` candidate against the previous search-and-count path. The 8 MiB
yank group compares the prior retained-vector implementation with streaming assembly.

To measure fresh-process behavior with and without compiled modules, run:

```sh
julia --project=benchmark benchmark/fresh_process.jl
```

Set `BENCHMARK_SAMPLES` to control the number of processes per configuration. Each process
is retained as a row in one table, with package load, `TextViewLayout` construction,
`DisplayConfig` construction, first `_view!`, and repeated `_view!` shown separately.

For a fast no-color rendering check without running the full suite:

```sh
julia --project=benchmark benchmark/reporting_smoke.jl
```

The input group separates pure ASCII/CSI decoder costs from one buffered-key state access.
The coalescing group compares 100 navigation keys with 100 sequential `_view!` calls against
the same monotonic burst viewed once at its final state. It does not include terminal redraws.
The auto-fit benchmark measures pure preflight latency; tests exercise the public fitting path
with hooks proving config, input, terminal, and raw-mode construction are skipped.

Standalone Escape is intentionally resolved promptly: one already-buffered byte is tried,
but an arbitrarily delayed `ESC` followed later by `[B` cannot be treated atomically without
an asynchronous reader or operating-system polling. Once `ESC [` is buffered, the decoder
retains it until the final CSI byte arrives.
