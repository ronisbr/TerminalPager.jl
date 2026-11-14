# AGENTS.md

## Package Structure

- `src/TerminalPager.jl` defines the module, public `pager` entry point, initialization hooks, and includes the implementation files.
- `src/input/` contains key-code, keybinding, and input handling.
- `src/pager/` contains the pager session, split by subject: the session and its options (`session.jl`), the state helpers (`state.jl`), the on-screen selection of the search columns (`columns.jl`), the key and event processing (`events.jl`), the frozen and title rows (`freeze.jl`), the positions and bookmarks (`position.jl`), the toggles (`toggles.jl`), the visual mode (`visual.jl`), and the copy, edit, and save commands (`yank.jl`).
- `src/view/` contains the layout of the text (`layout.jl`), the view renderer (`render.jl`), and the incremental redraw (`redraw.jl`); `src/view.jl` assembles the frame with the column ruler, the freeze guides, the highlighted search columns, and the scrollbar.
- `src/help.jl` contains the cheat sheet opened by `?`, generated from the table `_HELP_SECTIONS`. `src/extended_help.jl` contains the renderer and the session of the extended help opened by `H`, and `src/extended_help.md` contains its text, which is embedded when the package is precompiled. The text is written in GitHub Flavored Markdown, restricted to the blocks described in the docstring of `_manual_lines` and to the marks described in the docstring of `_help_atoms`, which the descriptions of `_HELP_SECTIONS` also use. Both screens share the style, the banner, the section titles, and the marked text in `src/help.jl`. A new feature must be described in both.
- `test/runtests.jl` is the test entry point; focused internal tests are in `test/internals/`.
- `ext/TerminalPagerAboutExt.jl` is the `About` weak-dependency extension registered as `TerminalPagerAboutExt` in `Project.toml`, and `ext/TerminalPagerDataFramesExt.jl` is the `DataFrames` one, registered as `TerminalPagerDataFramesExt`, which defines the pager recipe of data frames and has no tests.
- `docs/` is a Documenter environment with its own `Project.toml`, build script, and sources.
- `.github/workflows/ci.yml` tests Julia 1.10 and the latest stable Julia on Ubuntu x64, macOS arm64, and Windows x64. A separate workflow tests nightly.

## Commands

- Run the package tests: `julia --project=. -e 'using Pkg; Pkg.test()'`
- Prepare the documentation environment: `julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'`
- Build documentation locally: `julia --project=docs docs/make.jl local`

## Code Style

- `.JuliaFormatter.toml` configures BlueStyle. Match the existing four-space indentation, explicit `return` statements, docstrings, and section comments in neighboring Julia files.
- Use `snake_case` for functions and variables. Internal names conventionally begin with `_`; exported API additions must be deliberate.
- Keep source lines unwrapped only where existing syntax requires it; otherwise follow the surrounding formatting.
- Add or update focused tests under `test/internals/` and include new test files from `test/runtests.jl`.
- Capitalize `@testset` titles using New York Times title style.

## Behavioral Constraints

- Julia compatibility is `1.10`; changes must work on Julia 1.10 and current stable Julia.
- Tests are wired through the `Test` extra and `test` target in `Project.toml`.
- REPL help integration intentionally uses private `Base.JuliaSyntax` and `REPL.LineEdit` APIs and is explicitly coupled to them; preserve version-sensitive behavior and test changes across supported Julia versions.
- REPL help shortcuts are `F1` and `Alt+h`; both show extended help in the regular and pager modes. Keep `Alt+H` unbound because extended help is already the default. Shortcut registration is asynchronous, so tests must fetch the returned task to surface failures.
- Pager rendering is done by the in-package `_textview` (`src/view/render.jl`) over a `ViewLayout` (`src/view/layout.jl`), with the view described by a `ViewOptions`; StringManipulation.jl provides only string utilities. Account for ANSI escapes, Unicode display width, cropping, highlighting, frozen rows and columns, and search matches when changing viewport behavior.
- Keep `About` and `DataFrames` optional. Core package code must not make the weak dependencies mandatory.

## Not Configured

- No linter or pre-commit configuration is committed, and CI does not enforce formatting.
- No `Manifest.toml` is committed for the package or documentation environment.
