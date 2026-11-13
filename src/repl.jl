## Description #############################################################################
#
# Functions to create the REPL mode `pager`.
#
## References ##############################################################################
#
#   This code was adapted from the Pkg.jl project.
#
############################################################################################

# The pager mode is meant for interactive use only. We warn the user once per session if it
# is used from a script.
const PRINTED_REPL_WARNING = Ref(false)

"""
    _warn_repl_mode_noninteractive!(interactive::Bool = isinteractive()) -> Nothing

Warn once per session that the pager REPL mode is not meant for non-interactive use.

# Arguments

- `interactive::Bool`: Whether the current session is interactive.
    (**Default**: `isinteractive()`)
"""
function _warn_repl_mode_noninteractive!(interactive::Bool = isinteractive())
    if !interactive && !PRINTED_REPL_WARNING[]
        @warn(
            "The pager mode is intended for interactive use only and should not be used " *
                "from scripts."
        )
        PRINTED_REPL_WARNING[] = true
    end

    return nothing
end

"""
    _create_pager_repl_mode(
        repl::REPL.AbstractREPL,
        main::LineEdit.Prompt
    ) -> LineEdit.Prompt

Create the pager REPL mode for the active `repl` and its main prompt.

# Arguments

- `repl::REPL.AbstractREPL`: Active REPL that owns the new mode.
- `main::LineEdit.Prompt`: Main Julia prompt used for history and keymaps.
"""
function _create_pager_repl_mode(repl::REPL.AbstractREPL, main::LineEdit.Prompt)
    # == Prompt of the Pager Mode ==========================================================

    # In this case, we will use the same completion provider as the julia prompt.
    tp_mode = LineEdit.Prompt(
        _tp_mode_prompt;
        complete = REPL.REPLCompletionProvider(),
        prompt_prefix = repl.options.hascolor ? Base.text_colors[:magenta] : "",
        prompt_suffix = "",
        sticky = true,
    )

    # This function is called when the user hits return after typing a command.
    tp_mode.on_done = (s, buf, ok) -> begin
        ok || return REPL.transition(s, :abort)

        # Take the input command.
        input = String(take!(buf))
        REPL.reset(repl)

        # Process the input command inside the pager mode.
        _tp_mode_do_cmd(repl, input)

        REPL.prepare_next(repl)
        REPL.reset_state(s)
        s.current_mode.sticky || REPL.transition(s, main)
    end

    tp_mode.repl = repl

    # Check if the expression is incomplete, and, if so, request for another line.
    tp_mode.on_enter = REPL.return_callback

    # Let the command history be equal to the julia prompt.
    hp = main.hist
    hp.mode_mapping[:pager] = tp_mode
    tp_mode.hist = hp

    # Create the sub mode: pager help.
    tp_help_mode = _create_pager_help_repl_mode(repl, main, tp_mode)

    # == Key Mappings ======================================================================

    # Assign `?` as the key map to switch to pager help mode.
    help_mode_transition_keymap = Dict{Any, Any}(
        '?' => function (s, args...)
            # We must only switch to the pager help mode if `?` is typed at the beginning
            # of the line.
            if isempty(s) || (position(LineEdit.buffer(s)) == 0)
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, tp_help_mode) do
                    LineEdit.state(s, tp_help_mode).input_buffer = buf
                end
            else
                LineEdit.edit_insert(s, '?')
            end
        end
    )

    _set_mode_keymap!(tp_mode, main, help_mode_transition_keymap)

    return tp_mode
end

"""
    _create_pager_help_repl_mode(
        repl::REPL.AbstractREPL,
        main::LineEdit.Prompt,
        tp_mode::LineEdit.Prompt
    ) -> LineEdit.Prompt

Create the pager-help REPL mode.

# Arguments

- `repl::REPL.AbstractREPL`: Active REPL that owns the new mode.
- `main::LineEdit.Prompt`: Main Julia prompt used for history and keymaps.
- `tp_mode::LineEdit.Prompt`: Pager prompt to which help mode returns.
"""
function _create_pager_help_repl_mode(
    repl::REPL.AbstractREPL, main::LineEdit.Prompt, tp_mode::LineEdit.Prompt
)
    # == Prompt of the Pager Help Mode =====================================================

    tp_help_mode = LineEdit.Prompt(
        _tp_help_mode_prompt;
        complete = REPL.REPLCompletionProvider(),
        prompt_prefix = repl.options.hascolor ? Base.text_colors[:yellow] : "",
        prompt_suffix = "",
        sticky = false,
    )

    tp_help_mode.on_done =
        (s, buf, ok) -> begin
            # Without this, aborting the prompt with CTRL-D still evaluated the empty
            # input, which paged the Julia help welcome text instead of leaving the mode.
            ok || return REPL.transition(s, :abort)

            # Take the input command.
            input = String(take!(buf))
            REPL.reset(repl)

            # Process the input command inside the pager mode.
            _tp_help_mode_do_cmd(repl, input)

            REPL.prepare_next(repl)
            REPL.reset_state(s)
            s.current_mode.sticky || REPL.transition(s, tp_mode)
        end

    # == Key Mappings ======================================================================

    hp = main.hist
    hp.mode_mapping[:pager_help] = tp_help_mode
    tp_help_mode.hist = hp
    tp_help_mode.repl = repl

    _set_mode_keymap!(tp_help_mode, main)

    return tp_help_mode
end

"""
    _set_mode_keymap!(
        mode::LineEdit.Prompt,
        main::LineEdit.Prompt,
        extra::Union{Nothing, Dict{Any, Any}} = nothing
    ) -> Nothing

Set the key map of the prompt `mode` to the one of the `main` Julia prompt, the prefix
history search and the reverse search of the shared history, the `extra` key map if it is
given, and the default key maps of **REPL.jl**.

Notice that the prefix history search must be created for `mode` itself. Otherwise, the
search transitions to the wrong prompt.

# Arguments

- `mode::LineEdit.Prompt`: Prompt whose key map is set.
- `main::LineEdit.Prompt`: Main Julia prompt, whose history is shared.
- `extra::Union{Nothing, Dict{Any, Any}}`: Key map inserted before the defaults.
    (**Default**: `nothing`)
"""
function _set_mode_keymap!(mode::LineEdit.Prompt, main::LineEdit.Prompt, extra = nothing)
    hp = main.hist
    _, prefix_keymap = LineEdit.setup_prefix_keymap(hp, mode)

    skeymap = @static if VERSION >= v"1.13-"
        LineEdit.history_keymap
    else
        LineEdit.setup_search_keymap(hp)[2]
    end

    keymaps = Dict{Any, Any}[REPL.mode_keymap(main), prefix_keymap, skeymap]
    isnothing(extra) || push!(keymaps, extra)
    push!(keymaps, LineEdit.history_keymap, LineEdit.default_keymap, LineEdit.escape_defaults)

    mode.keymap_dict = LineEdit.keymap(keymaps)

    return nothing
end

"""
    _init_pager_repl_mode_when_ready(repl::REPL.LineEditREPL) -> Task

Initialize the pager REPL mode in a task that waits for the interface of `repl` to be set
up, which happens when the package is loaded from an `atreplinit` hook or before
`run_frontend`.

# Arguments

- `repl::REPL.LineEditREPL`: Active REPL that owns the new mode.
"""
function _init_pager_repl_mode_when_ready(repl::REPL.LineEditREPL)
    return @async begin
        while !isdefined(repl, :interface)
            sleep(0.1)
        end
        _init_pager_repl_mode(repl)
    end
end

"""
    _init_pager_repl_mode(repl::AbstractREPL) -> Nothing

Initialize pager and pager-help modes in `repl`.

# Arguments

- `repl::AbstractREPL`: REPL whose interface receives the pager modes.

# Keywords

- `replace_help_mode::Bool`: Page the answers of the regular `help?>` prompt too.
    (**Default**: the value of the preference `"replace_help_mode"`)
"""
function _init_pager_repl_mode(
    repl::AbstractREPL;
    replace_help_mode::Bool = _get_preference("replace_help_mode")::Bool,
)
    # Get the main REPL mode (julia prompt).
    main_mode = repl.interface.modes[1]

    # Create the pager mode.
    tp_mode = _create_pager_repl_mode(repl, main_mode)

    # Add the new mode to the REPL interfaces.
    push!(repl.interface.modes, tp_mode)

    # The shortcuts, such as the help ones, can be registered before this mode exists, for
    # example by a REPL hook that runs first. Hence, the mode applies them itself.
    _apply_shortcut_registrars!(tp_mode)

    # The regular help mode pages its answers if the user asked for it.
    replace_help_mode && _replace_help_mode!(repl)

    # Assign `|` as the key map to switch to pager mode.
    keymap = Dict{Any, Any}(
        '|' => function (s, args...)
            # We must only switch to pager mode if `|` is typed at the beginning
            # of the line.
            if isempty(s) || position(LineEdit.buffer(s)) == 0
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, tp_mode) do
                    LineEdit.state(s, tp_mode).input_buffer = buf
                end
            else
                LineEdit.edit_insert(s, '|')
            end
        end
    )

    # Add the keymap that initializes pager mode to the default REPL key mappings.
    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, keymap)

    return nothing
end

############################################################################################
#                                 Paged Regular Help Mode                                  #
############################################################################################

"""
    struct PagedHelpOnDone <: Function

Replacement of the `on_done` callback of the regular `help?>` prompt that pages its answers.
It is a `Function`, because the field of the prompt is typed so.

The answers of the regular help mode never pass through `stdout`: they go to the REPL
display. Hence, the callback evaluates the help itself, like the `pager?>` prompt does, and
pages the result when it does not fit the display. The original callback is kept, so that
it can be restored.

# Fields

- `repl::Any`: REPL that owns the prompt.
- `main::LineEdit.Prompt`: Main Julia prompt the help mode returns to.
- `original::Any`: Original `on_done` callback of the prompt.
"""
struct PagedHelpOnDone <: Function
    repl::Any
    main::LineEdit.Prompt
    original::Any
end

function (h::PagedHelpOnDone)(s, buf, ok)
    ok || return REPL.transition(s, :abort)

    input = String(take!(buf))
    REPL.reset(h.repl)
    _paged_help_do_cmd(h.repl, input, s.active_module)
    REPL.prepare_next(h.repl)
    REPL.reset_state(s)

    return s.current_mode.sticky ? true : REPL.transition(s, h.main)
end

"""
    _paged_help_do_cmd(repl::Any, input::String, mod::Module) -> Nothing

Render the help of `input` in `mod` and show it in the pager when it does not fit the
display, reporting the errors on the error stream of `repl` instead of throwing.

# Arguments

- `repl::Any`: REPL that owns the help prompt.
- `input::String`: Help query typed by the user.
- `mod::Module`: Module in which the query is evaluated.
"""
function _paged_help_do_cmd(repl, input::String, mod::Module)
    try
        pager(_get_help(strip(input), mod); auto = true)
    catch err
        Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())
    end

    return nothing
end

"""
    _help_prompt_string() -> String

Return the prompt of the regular help mode of the REPL.
"""
_help_prompt_string() = isdefined(REPL, :HELP_PROMPT) ? String(REPL.HELP_PROMPT) : "help?> "

"""
    _find_help_mode(repl::Any) -> Union{Nothing, LineEdit.Prompt}

Return the regular help prompt of `repl`, found by its prompt string, or `nothing` if the
REPL has no such prompt.

# Arguments

- `repl::Any`: REPL whose prompts are searched.
"""
function _find_help_mode(repl)
    hasproperty(repl, :interface) || return nothing
    prompt = _help_prompt_string()

    for mode in repl.interface.modes
        (mode isa LineEdit.Prompt) || continue
        (LineEdit.prompt_string(mode.prompt) == prompt) && return mode
    end

    return nothing
end

"""
    _replace_help_mode!(repl::Any) -> Bool

Make the regular help prompt of `repl` page its answers and return whether the prompt was
found. A prompt already replaced is left as it is.

# Arguments

- `repl::Any`: REPL whose help prompt is replaced.
"""
function _replace_help_mode!(repl)
    mode = _find_help_mode(repl)
    isnothing(mode) && return false
    (mode.on_done isa PagedHelpOnDone) && return true
    mode.on_done = PagedHelpOnDone(repl, first(repl.interface.modes), mode.on_done)
    return true
end

"""
    _restore_help_mode!(repl::Any) -> Bool

Restore the original callback of the regular help prompt of `repl` and return whether it
was replaced.

# Arguments

- `repl::Any`: REPL whose help prompt is restored.
"""
function _restore_help_mode!(repl)
    mode = _find_help_mode(repl)
    (isnothing(mode) || !(mode.on_done isa PagedHelpOnDone)) && return false
    mode.on_done = mode.on_done.original
    return true
end

############################################################################################
#                           Command Treatment for the REPL Modes                           #
############################################################################################

"""
    _tp_mode_do_cmd(repl::REPL.AbstractREPL, input::String) -> Nothing

Execute `input` in pager REPL mode and display its standard output.

# Arguments

- `repl::REPL.AbstractREPL`: Active REPL used to evaluate the command.
- `input::String`: Command text to evaluate.
"""
function _tp_mode_do_cmd(repl::REPL.AbstractREPL, input::String)
    _warn_repl_mode_noninteractive!()

    # The `stdout` will be redirected inside the try/catch. Hence, we need to store the old
    # one to restore it if everything fails.
    old_stdout = stdout
    io = nothing

    try
        # Create a buffer that will replace `stdout`. Notice that we add a context key
        # called `bypass_pager` with value `true`. All the commands we call in this mode
        # will have their output handed to the pager. Hence, if a command also calls a
        # pager, we must only return the object. Otherwise, the session freezes until the
        # user presses CTRL-D. For more information, see:
        #
        #   https://github.com/ronisbr/TerminalPager.jl/issues/40
        buf = IOBuffer()
        io = IOContext(
            IOContext(buf, stdout),
            :bypass_pager => true,
            :displaysize => displaysize(stdout),
            :limit => false,
        )

        # Redirect `stdout` to the new buffer.
        Base.eval(:(stdout = $io))

        # First, we need to split the buffer into lines.
        lines = split(input, '\n'; keepempty = true)

        # Index of the first line of the command being assembled, which can span multiple
        # lines.
        command_first_line = firstindex(lines)

        # Variable to indicate that we have an error while evaluating the expression.
        is_error = false

        # The last value shown, and where its rendering starts and ends in the buffer, so
        # that its recipe is applied when the buffer holds nothing else.
        shown_value = nothing
        shown_from = -1
        shown_to = -1

        # Loop through the lines.
        for i in eachindex(lines)
            # Assemble the candidate command in a single pass. Growing a string instead
            # copied the whole accumulated command once per line, which was quadratic for
            # large pasted blocks.
            cmd = _assemble_repl_command(lines, command_first_line, i)
            ast = Base.parse_input_line(cmd)

            # If the command is incomplete, we need to wait for another line. Notice that
            # `parse_input_line` does not always return an `Expr`, so we must check that before
            # reading its head.
            isa(ast, Expr) && (ast.head == :incomplete) && continue

            # The next command starts after the current line.
            command_first_line = i + 1

            # We will use `REPL.eval_on_backend` to evaluate the expression. This function
            # returns two values: the object returned by the expression, and a boolean value
            # indicating if we got an error.
            val, is_error = @static if VERSION >= v"1.11.6"
                REPL.eval_on_backend(ast, REPL.backend(repl))
            else
                REPL.eval_with_backend(ast, REPL.backend(repl))
            end

            # If we have an error, print the information and stop the processing. The output
            # captured so far must be shown first, otherwise everything the command printed
            # before failing is lost.
            if is_error
                print(old_stdout, String(take!(buf)))
                val = Base.scrub_repl_backtrace(val)
                Base.istrivialerror(val) || setglobal!(Base.MainInclude, :err, val)
                Base.invokelatest(Base.display_error, repl.t.err_stream, val)
                break
            end

            # If the user added `;` at the end of the command, we should not show the
            # output.
            if !REPL.ends_with_semicolon(cmd)
                # If the output is not `nothing`, call `show` with `MIME("text/plain")` to
                # render the object.
                if val !== nothing
                    shown_from = position(buf)
                    displayed = _display_value!(stdout, val)
                    shown_to = position(buf)

                    # A value shown by another display leaves nothing in the buffer.
                    shown_value = displayed ? nothing : val
                end
            end
        end

        # Restore the old stdout.
        Base.eval(:(stdout = $old_stdout))

        if !is_error
            copy_to_clipboard = _get_preference(
                "copy_stdout_to_clipboard_in_repl_mode"
            )::Bool

            # Take everything and display in the pager using `auto` mode. In this case, the
            # pager will only be called if there is not space in the display to show
            # everything. The recipe of the value applies when the output is its rendering.
            covers =
                (shown_value !== nothing) && (shown_from == 0) && (shown_to == position(buf))
            str = String(take!(buf))
            pager(str; _repl_mode_options(shown_value, str, covers)...)

            copy_to_clipboard && clipboard(remove_decorations(str))
        end
    catch err
        Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())

    finally
        Base.eval(:(stdout = $old_stdout))

        # `close` used to be inside the `try`, so it was skipped whenever the pager threw.
        isnothing(io) || close(io)
    end

    return nothing
end

"""
    _display_value!(io::IO, value::Any) -> Bool

Show `value`, the result of a `pager>` command, like the REPL does: the displays of the
display stack are tried from the top, except the REPL display and the text display, which
point at the terminal behind the pager, and `value` is rendered into `io` with
`MIME"text/plain"` when none of them accepts it. Return whether another display showed it.
With the preference `"repl_mode_display"` set to `"pager"`, the stack is not tried.

# Arguments

- `io::IO`: Buffer of the `pager>` command output.
- `value::Any`: Value to show.
"""
function _display_value!(io::IO, @nospecialize(value))
    if _get_preference("repl_mode_display")::String == "stack"
        displays = Base.Multimedia.displays

        for i in length(displays):-1:1
            d = displays[i]
            ((d isa REPL.REPLDisplay) || (d isa TextDisplay)) && continue

            # Like `Base.display`, a display without a method for the value is skipped. The
            # displays are pushed at runtime, so the call must see the latest world.
            try
                Base.invokelatest(display, d, value)
                return true
            catch err
                (err isa MethodError) && ((err.f === display) || (err.f === show)) ||
                    rethrow()
            end
        end
    end

    Base.invokelatest(show, io, MIME("text/plain"), value)
    write(io, '\n')

    return false
end

"""
    _repl_mode_options(value::Any, rendered::String, covers::Bool) -> NamedTuple

Return the keywords of the pager for the output `rendered` of a `pager>` command, which are
the recipe of `value` when `covers` tells that the output is its rendering, and always the
automatic mode.

# Arguments

- `value::Any`: Last value shown by the command.
- `rendered::String`: Output of the command.
- `covers::Bool`: Whether `rendered` is exactly the rendering of `value`.
"""
function _repl_mode_options(value, rendered::String, covers::Bool)
    covers || return (; auto = true)
    return _merge_options(_pager_options(value, rendered), (; auto = true))
end

"""
    _assemble_repl_command(
        lines::AbstractVector{<:AbstractString},
        first_line::Int,
        last_line::Int
    ) -> String

Assemble the newline-terminated command spanning `lines[first_line:last_line]`.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Lines of the whole REPL input.
- `first_line::Int`: One-based index of the first command line.
- `last_line::Int`: One-based index of the last command line, inclusive.
"""
function _assemble_repl_command(
    lines::AbstractVector{<:AbstractString}, first_line::Int, last_line::Int
)
    sizehint = 0

    for i in first_line:last_line
        sizehint += sizeof(lines[i]) + 1
    end

    buf = IOBuffer(; sizehint = sizehint)

    for i in first_line:last_line
        write(buf, lines[i])
        write(buf, '\n')
    end

    return String(take!(buf))
end

"""
    _tp_help_mode_do_cmd(repl::REPL.AbstractREPL, input::String) -> Nothing

Display help for `input` from pager-help REPL mode.

# Arguments

- `repl::REPL.AbstractREPL`: Active REPL used to report errors.
- `input::String`: Help query to display.
"""
function _tp_help_mode_do_cmd(repl::REPL.AbstractREPL, input::String)
    # We do not need to verify if we are in an interactive environment because this mode is
    # only accessible through pager mode, which already checks it.
    try
        # Take everything and display in the pager using the alternate screen buffer to
        # avoid modifying the current screen state.
        pager(_get_help(input); use_alternate_screen_buffer = true)
    catch err
        Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())
    end

    return nothing
end

############################################################################################
#                                         Prompts                                          #
############################################################################################

"""
    _tp_mode_prompt() -> String

Return the pager-mode prompt.
"""
_tp_mode_prompt() = "pager> "

"""
    _tp_help_mode_prompt() -> String

Return the pager-help-mode prompt.
"""
_tp_help_mode_prompt() = "pager?> "
