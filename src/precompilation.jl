## Description #############################################################################
#
# Precompilation.
#
############################################################################################

using PrecompileTools: PrecompileTools

# Markdown document with every kind of node found in docstrings, rendered by the workload.
const _PRECOMPILE_MARKDOWN = """
    # Title

    ## Section

    ### Subsection

    Paragraph with **bold**, *italic*, `code`, a [link](https://julialang.org), and math
    ``x^2``. A footnote[^1] and an image ![alt](image.png).

    - Item one
    - Item two
        - Nested item
        1. Ordered nested item

    1. First
    2. Second

    | Left | Right |
    |:-----|------:|
    | a    |     1 |
    | b    |     2 |

    ```julia
    x = 1
    ```

    ```
    plain code
    ```

    > Quoted paragraph.

    !!! note
        Note body.

    !!! warning "Custom title"
        Warning body.

    !!! compat "Julia 1.11"
        Compat body.

    ---

    Term
    : Definition

    [^1]: Footnote text.
    """

"""
    _start_workload_session(str::String, keywords::NamedTuple) -> Task

Start a pager session for `str` with the options in `keywords` in a new task, which the
precompilation workload drives by writing the keystrokes to the standard input.

All the sessions of the workload are started by this function so that a single task
function is compiled and stored for them, instead of one for each session.

# Arguments

- `str::String`: Text to display.
- `keywords::NamedTuple`: Keywords of the session.
"""
function _start_workload_session(str::String, @nospecialize(keywords::NamedTuple))
    options = _session_options(keywords)
    return @async _pager(str, options)
end

# The workload evaluates the help expression returned by `REPL.helpmode`, which assigns a
# global. Evaluating it into `Main`, or into any module created while precompiling, is not
# allowed, whereas this submodule belongs to the package and is open.
module HelpWorkload end

PrecompileTools.@setup_workload begin
    # We will redirect the `stdout` and `stdin` so that we can execute the pager and input
    # some commands without any visible change for the user.
    old_stdout = Base.stdout
    old_stdin = Base.stdin

    redirect_stdout(devnull)
    stdin_rd, stdin_wr = redirect_stdin()

    # The redirections must be undone even when the workload throws. Otherwise, a failing
    # workload leaves the whole precompilation process without standard streams, turning a
    # small failure into an unreadable one.
    try
        PrecompileTools.@compile_workload begin
            # Precompile everything called in __init__.
            __init__()

            # The workload must not depend on the user. `__init__` applied the key bindings
            # stored in the preferences, which can rebind the keys that the sessions below
            # type. With `q` deleted, for example, a session would never quit and the
            # precompilation would never end. Hence, the default key bindings are restored.
            # The stored ones are applied again by `__init__` when the package is loaded.
            empty!(_KEYBINDINGS)
            merge!(_KEYBINDINGS, _DEFAULT_KEYBINDINGS)
            _keybindings_changed!()

            # The workload must not change anything outside this process either. The
            # sessions below copy text, which must not replace the clipboard of the user.
            # The function that copies to the clipboard is also set again by `__init__`.
            _CLIPBOARD[] = Returns(nothing)

            # Create a mock REPL to precompile the REPL integration functions.
            mock_repl = REPL.LineEditREPL(
                REPL.Terminals.TTYTerminal("", stdin, stdout, stderr), true
            )
            mock_repl.interface = REPL.setup_interface(mock_repl)
            _init_pager_repl_mode(mock_repl)

            # The shortcuts are registered by tasks, which must finish before the keys are
            # looked up below.
            wait(_register_help_shortcuts(mock_repl))
            wait(_register_history_shortcuts(mock_repl))
            wait(_register_pipe_shortcuts(mock_repl))
            TerminalPager._replace_help_mode!(mock_repl)

            # A key bound to a function is called through a closure that **REPL.jl** creates
            # for the type of the function when the key is pressed. Those closures are
            # compiled here for the keys of this package, without running them: `|` and `?`
            # at the beginning of the line, F1, Alt+h, Alt+l, Alt+L, and Alt+|.
            mock_modes = mock_repl.interface.modes

            for (mode, keys) in (
                (mock_modes[1], ("|", "\eOP", "\eh", "\el", "\eL", "\e|")),
                (mock_modes[end], ("?", "\eOP", "\eh", "\el", "\eL", "\e|")),
            )
                for key in keys
                    binding = LineEdit.match_input(mode.keymap_dict, nothing, IOBuffer(key))
                    precompile(binding, (Any, Any))
                end
            end

            # The public entry point prints the text when the standard streams are not
            # terminals, which is the case here. It is called anyway to compile the code
            # that renders an object and merges the options of its recipe with the
            # keywords, for the calls without keywords and for the ones of the `pager>`
            # mode. Then, the workload renders the object like `pager` does and drives the
            # session directly.
            a = [0.1986 0.0; 0.0 0.0]
            pager(a)
            pager(a; auto = true)
            pager("text")
            pager("text"; auto = true)
            a |> pager
            _repl_mode_options(a, "2×2 Matrix{Float64}:\n 0.0  0.0\n 0.0  0.0", true)
            _repl_mode_options(nothing, "", false)
            _render_object(a)

            # Text of the sessions, which is larger than the display in both directions.
            # Notice that it is not obtained from a large array because building one would
            # compile and store code that is used only here.
            str = repeat(repeat(" 0.1986  0.0   ", 60) * "\n", 100)

            t = _start_workload_session(str, (; use_alternate_screen_buffer = false))

            # Ruler, and the column ruler on and off.
            write(stdin_wr, "r")
            write(stdin_wr, "RR")
            # Scrollbar on and off.
            write(stdin_wr, "ss")
            # Freeze rows and columns.
            write(stdin_wr, "f10\n10\n")
            # Title rows.
            write(stdin_wr, "t1\n")
            # Select the frozen rows and columns on the screen, with the scrollbar on so
            # that the frame with the guides feeds it, and then cancel a selection.
            write(stdin_wr, "s")
            write(stdin_wr, "F\eOB\eOC\r")
            write(stdin_wr, "Fq")
            # Select the title rows on the screen, and then cancel a selection.
            write(stdin_wr, "T\eOB\r")
            write(stdin_wr, "Tq")
            write(stdin_wr, "s")
            # Down.
            write(stdin_wr, "\eOB")
            # Up.
            write(stdin_wr, "\eOA")
            # Right.
            write(stdin_wr, "\eOC")
            # Left.
            write(stdin_wr, "\eOD")
            # Page down.
            write(stdin_wr, "\e[6~")
            # Page up.
            write(stdin_wr, "\e[5~")
            # End.
            write(stdin_wr, "\e[F")
            # Home.
            write(stdin_wr, "\e[H")
            # Visual mode.
            write(stdin_wr, "v")
            # Mark lines.
            write(stdin_wr, "MjMjMjMjMjM")
            # Unmark lines.
            write(stdin_wr, "MkMk")
            # Anchor a range, mark it, and copy the whole text.
            write(stdin_wr, "VjjMY")
            # Save prompt, cancelled.
            write(stdin_wr, "S\e")
            # Exit visual mode.
            write(stdin_wr, "v")
            # Help.
            write(stdin_wr, "?")
            # Exit help mode.
            write(stdin_wr, "q")
            # Bookmarks: set, jump, and return.
            write(stdin_wr, "ma'a''")
            # Position report and the goto forms.
            write(stdin_wr, "=")
            write(stdin_wr, ":50%\n")
            write(stdin_wr, ":+1\n")
            write(stdin_wr, ":\$\n")
            # Literal search toggled on and off at the prompt.
            write(stdin_wr, "/\el0.1986\el\n")
            # Filter, inverted filter, and cleared filter.
            write(stdin_wr, "&0.1986\n")
            write(stdin_wr, "&!0.1986\n")
            write(stdin_wr, "&\n")
            # Search restricted to a range of columns.
            write(stdin_wr, "/@1:5 0.1986\n")
            # Search.
            write(stdin_wr, "/0.1986\n")
            # Next search.
            write(stdin_wr, "nnn")
            # Exit the pager directly from search mode. Standalone Escape is exercised
            # below without racing the following quit byte.
            write(stdin_wr, "q")

            wait(t)

            # Pager with the alternate screen buffer, which is the default.
            t = _start_workload_session(str, (;))
            write(stdin_wr, "q")
            wait(t)

            # Pager returning the selection copied by Enter in the visual mode.
            t = _start_workload_session(str, (; return_selection = true))
            write(stdin_wr, "vM\n")
            wait(t)

            # Pager restoring the viewport and the search of a previous session, which is
            # what reopening an entry of the history does.
            t = _start_workload_session(
                str,
                (;
                    use_alternate_screen_buffer = false,
                    _restore = PagerResult(String[], 5, 1, "0.1986"),
                ),
            )
            write(stdin_wr, "q")
            wait(t)

            # The history of the texts shown by the pager and its menu.
            TerminalPager._push_pager_history!(str, (; use_alternate_screen_buffer = false))
            TerminalPager.history(devnull)
            TerminalPager._history_menu(
                REPL.Terminals.TTYTerminal("", IOBuffer("q"), devnull, devnull);
                request = (t, m) ->
                    REPL.TerminalMenus.request(t, m; suppress_output = true),
            )
            empty!(TerminalPager._PAGER_HISTORY)

            # Pager with auto mode, which exercises the `printable_textwidth` code path.
            # This is important because the REPL mode always uses `auto = true`.
            t = _start_workload_session(str, (; auto = true))
            write(stdin_wr, "q")
            wait(t)

            # == Internal Functions ========================================================

            TerminalPager._get_help("read")
            f = "read read read"
            TerminalPager._get_help(@view f[1:4])

            # The help and `pager(obj)` render Markdown documents. Rendering every kind of
            # node here precompiles the Markdown methods for the buffered context, which
            # otherwise cost hundreds of milliseconds at the first help of the session.
            TerminalPager._render_object(Markdown.parse(_PRECOMPILE_MARKDOWN))

            # `_get_help` does not evaluate the help expression while precompiling, and the
            # redirected `stdout` has no color support, whereas the help preamble and the
            # rendering use colors on a terminal. Hence, the help is evaluated here with a
            # colored context, into a submodule because the expression assigns a global.
            # This is the code path of the first help of a session, which used to take
            # hundreds of milliseconds to compile.
            colored = IOContext(
                IOBuffer(), :color => true, :displaysize => (24, 80), :limit => false
            )
            response = TerminalPager._eval_helpmode(colored, "read", HelpWorkload)
            show(colored, MIME("text/plain"), response)
            TerminalPager._extract_identifier("while true break end", 10)
            TerminalPager._decode_keystroke(collect(codeunits("\e[B")))
            TerminalPager._decode_keystroke(collect(codeunits("\e[<64;10;5M")))
            TerminalPager._try_read_keystroke!(PagerInput(IOBuffer("j")))
            TerminalPager._read_keystroke!(PagerInput(IOBuffer("\e")))

            burst_input = IOBuffer("jj")
            burst_term = REPL.Terminals.TTYTerminal("", burst_input, devnull, devnull)
            burst_layout = ViewLayout(fill("line", 20))
            burst_pager = Pager(;
                term = burst_term,
                buf = IOContext(IOBuffer(), :color => false),
                input = PagerInput(burst_input),
                display_size = displaysize(devnull),
                num_lines = 20,
                cropped_lines = 10,
                text_layout = burst_layout,
            )
            burst_key = TerminalPager._read_keystroke!(burst_pager.input)
            burst_action = TerminalPager._pager_key_process!(burst_pager, burst_key)
            TerminalPager._coalesce_navigation!(burst_pager, burst_action)

            # Precompile a complete frame, so that the first one the user sees is not also
            # the first one to be compiled. The terminal is `devnull`, hence this is silent.
            TerminalPager._view!(burst_pager)
            TerminalPager._redraw!(burst_pager)
            TerminalPager._redraw_status_bar!(burst_pager)

            # A second frame exercises the incremental path, which compares the frame
            # against the snapshot instead of painting every row.
            burst_pager.start_row = 2
            TerminalPager._view!(burst_pager)
            TerminalPager._redraw!(burst_pager)

            burst_pager.mode = :searching
            TerminalPager._redraw_status_bar!(burst_pager)

            # The search pattern of the session above arrives at once, like a pasted text,
            # so the incremental search does not preview it. The preview, which runs at
            # every typed character, is exercised here instead.
            TerminalPager._preview_search!(
                burst_pager, "line", TerminalPager._search_state(burst_pager)
            )
            TerminalPager._preview_filter!(
                burst_pager, "line", TerminalPager._filter_state(burst_pager)
            )
            TerminalPager._clear_filter!(burst_pager)

            for prepared_lines in (
                ["plain text", "second line"],
                ["Unicode α界", "combining e\u0301"],
                ["\e[31mANSI red\e[0m", "search search"],
            )
                prepared_layout = ViewLayout(prepared_lines)
                TerminalPager._pager_content_fits(prepared_layout, (10, 40))
                TerminalPager._assemble_yank_text(prepared_layout, [2, 1, 2])
                prepared_layout[1]
                length(prepared_layout)
                prepared_matches = string_search_per_line(prepared_layout, r"search")
                active_location = isempty(prepared_matches) ? (0, 0) : (2, 1)
                TerminalPager._textview(
                    devnull,
                    prepared_layout,
                    ViewOptions(;
                        active_match = active_location,
                        frozen_rows = 1,
                        max_columns = 40,
                        max_rows = 10,
                        ruler_foot = true,
                        search_matches = prepared_matches,
                        show_ruler = true,
                    ),
                )
                TerminalPager._textview(
                    devnull,
                    ViewLayout(prepared_layout, [2]),
                    ViewOptions(;
                        line_numbers = [2],
                        max_columns = 40,
                        max_rows = 10,
                        show_ruler = true,
                    ),
                )
            end
        end
    finally
        close(stdin_wr)
        close(stdin_rd)

        redirect_stdout(old_stdout)

        if isopen(old_stdin)
            redirect_stdin(old_stdin)
        else
            redirect_stdin(devnull)
        end
    end
end

# The input waiter is created only for terminals, which the workload does not have. Hence,
# its methods are compiled here without running them.
precompile(_create_input_waiter, (Base.TTY, Base.TTY))
precompile(_run_input_waiter_reader, (InputWaiter, Base.TTY))
precompile(_close_input_waiter!, (PagerInput,))

# The session of the workload does not write to a terminal.
precompile(_write_all, (Base.TTY, typeof(IOBuffer().data), Int))
precompile(bytesavailable, (Base.TTY,))

# The workload only registers the REPL hook. Running the hook would not help, because it
# skips its body in the non-interactive precompilation process.
precompile(_init_repl_integrations, (REPL.LineEditREPL,))

# The callbacks of the prompts and of the key bindings need a running REPL, which the
# workload does not have. Hence, they are compiled here for the types the REPL calls them
# with.
precompile(Tuple{PromptOnDone, LineEdit.MIState, IOBuffer, Bool})
precompile(Tuple{PromptSwitchKey, LineEdit.MIState, REPL.LineEditREPL, String})
precompile(Tuple{PromptSwitchKey, LineEdit.MIState, REPL.LineEditREPL, Vararg{Any}})
precompile(_tp_mode_do_cmd, (REPL.LineEditREPL, String))
precompile(_tp_help_mode_do_cmd, (REPL.LineEditREPL, String))
precompile(_paged_help_do_cmd, (REPL.LineEditREPL, String, Module))
precompile(_display_value!, (IOContext{IOBuffer}, Any))
precompile(_tp_mode_prompt, ())
precompile(_tp_help_mode_prompt, ())

for shortcut in
    (_show_pager_help, _append_pager_pipe, _reopen_last_output, _choose_history_entry)
    precompile(shortcut, (LineEdit.MIState, REPL.LineEditREPL, String))
end
