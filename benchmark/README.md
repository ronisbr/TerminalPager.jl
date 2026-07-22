# Benchmarks

The benchmarks use a separate environment so that BenchmarkTools is not a runtime dependency.
Until StringManipulation 0.4.6 is registered, run from the package root in a disposable
environment that develops the verified worktree first:

```sh
environment=$(mktemp -d)
julia --project="$environment" -e '
    using Pkg
    Pkg.develop(path=".slim/worktrees/stringmanipulation-viewport")
    Pkg.develop(path=pwd())
    Pkg.add("BenchmarkTools")
'
julia --project="$environment" benchmark/benchmarks.jl
```

The suite covers preference and session configuration access, representative view widths,
ordered search-index construction and navigation, and yank text assembly without clipboard
access.

The search movement case alternates between the first and last of 100,000 matches for 100
calls. Divide its reported time by 100 for per-call latency. The construction group compares
the complete `_find_matches!` candidate against the previous search-and-count path. The 8 MiB
yank group compares the prior retained-vector implementation with streaming assembly.

To measure fresh-process behavior with and without compiled modules, run:

```sh
julia --project="$environment" benchmark/fresh_process.jl
```

Set `BENCHMARK_SAMPLES` to control the number of processes per configuration. Each process
reports package load, `TextViewLayout` construction, `DisplayConfig` construction, first
`_view!`, and second `_view!` separately. The worker inherits the driver's active project,
so run it from the disposable environment that develops both TerminalPager and the verified
StringManipulation worktree.

The input group separates pure ASCII/CSI decoder costs from one buffered-key state access.
The coalescing group compares 100 navigation keys with 100 sequential `_view!` calls against
the same monotonic burst viewed once at its final state. It does not include terminal redraws.
The auto-fit benchmark measures pure preflight latency; tests exercise the public fitting path
with hooks proving config, input, terminal, and raw-mode construction are skipped.

Standalone Escape is intentionally resolved promptly: one already-buffered byte is tried,
but an arbitrarily delayed `ESC` followed later by `[B` cannot be treated atomically without
an asynchronous reader or operating-system polling. Once `ESC [` is buffered, the decoder
retains it until the final CSI byte arrives.
