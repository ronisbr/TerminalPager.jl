## Description #############################################################################
#
# Functions to create the REPL mode `pager`.
#
## References ##############################################################################
#
#   This code was adapted from the Pkg.jl project.
#
############################################################################################

# Create the REPL mode `pager`. `repl` must be the active REPL, and `main` must be the main
# REPL mode (julia prompt).
function _create_pager_repl_mode(repl::REPL.AbstractREPL, main::LineEdit.Prompt)
    # == Prompt of the Pager Mode ==========================================================

    # In this case, we will use the same completion provider as the julia prompt.
    tp_mode = LineEdit.Prompt(
        _tp_mode_prompt;
        complete      = REPL.REPLCompletionProvider(),
        prompt_prefix = repl.options.hascolor ? Base.text_colors[:magenta] : "",
        prompt_suffix = "",
        sticky        = true
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

    # We want to support all the default keymap prefixes.
    prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, tp_mode)

    # We also want to support reverse searching.
    search_promt, skeymap = LineEdit.setup_search_keymap(hp)

    # Key mappings used in the pager mode:
    mk = REPL.mode_keymap(main)

    # Assign `?` as the key map to switch to pager help mode.
    help_mode_transition_keymap = Dict{Any, Any}(
        '?' => function(s, args...)
            # We must only switch to pager mode if `|` is typed at the beginning
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

    tp_mode_keymaps = Dict{Any, Any}[
        mk,
        prefix_keymap,
        skeymap,
        help_mode_transition_keymap,
        LineEdit.history_keymap,
        LineEdit.default_keymap,
        LineEdit.escape_defaults,
    ]

    tp_mode.keymap_dict = LineEdit.keymap(tp_mode_keymaps)

    return tp_mode
end

# Create the REPL mode `pager help`. `repl` must be the active REPL, `main` must be the main
# REPL mode (julia prompt), and `tp_mode` must be the REPL mode `pager`.
function _create_pager_help_repl_mode(
    repl::REPL.AbstractREPL,
    main::LineEdit.Prompt,
    tp_mode::LineEdit.Prompt
)
    # == Prompt of the Pager Help Mode =====================================================

    tp_help_mode = LineEdit.Prompt(
        _tp_help_mode_prompt;
        complete      = REPL.REPLCompletionProvider(),
        prompt_prefix = repl.options.hascolor ? Base.text_colors[:yellow] : "",
        prompt_suffix = "",
        sticky        = false
    )

    tp_help_mode.on_done = (s, buf, ok) -> begin
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

    # We want to support all the default keymap prefixes.
    prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, tp_mode)

    # We also want to support reverse searching.
    search_promt, skeymap = LineEdit.setup_search_keymap(hp)

    # Key mappings used in the pager mode:
    mk = REPL.mode_keymap(main)

    tp_help_mode.repl = repl

    tp_help_mode_keymaps = Dict{Any, Any}[
        mk,
        prefix_keymap,
        skeymap,
        LineEdit.history_keymap,
        LineEdit.default_keymap,
        LineEdit.escape_defaults,
    ]

    tp_help_mode.keymap_dict = LineEdit.keymap(tp_help_mode_keymaps)

    return tp_help_mode
end

# Initialize the pager mode in the `repl`.
function _init_pager_repl_mode(repl::AbstractREPL)
    # Get the main REPL mode (julia prompt).
    main_mode = repl.interface.modes[1]

    # Create the pager mode.
    tp_mode = _create_pager_repl_mode(repl, main_mode)

    # Add the new mode to the REPL interfaces.
    push!(repl.interface.modes, tp_mode)

    # Assign `|` as the key map to switch to pager mode.
    keymap = Dict{Any, Any}(
        '|' => function(s, args...)
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

    # Add the key map that initialize the pager mode to the default REPL key mappings.
    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, keymap)

    return nothing
end

############################################################################################
#                           Command Treatment for the REPL Modes                           #
############################################################################################

# Execute the actions when a command has been received in the REPL mode `pager`. `repl`
# must be the active REPL, and `input` is a string with the command.
function _tp_mode_do_cmd(repl::REPL.AbstractREPL, input::String)
    if !isinteractive() && !PRINTED_REPL_WARNING[]
        @warn "The parger mode is intended for interaction use only, and should not be used from scripts."
        PRINTED_REPL_WARNING[] = true
    end

    # The `stdout` will be redirected inside the try/catch. Hence, we need to store the old
    # one to restore it if everything fails.
    old_stdout = stdout

    try
        # Create a buffer that will replace `stdout`. Notice that we add a context key
        # called `bypass_pager` with value `true`. All the commands we call in this mode
        # will have its output handled to the pager. Hence, if a command also calls a pager,
        # we must only return the object. Otherwise, the section freezes until the user
        # press CTRL-D. For more information, see:
        #
        #   https://github.com/ronisbr/TerminalPager.jl/issues/40
        buf = IOBuffer()
        io  = IOContext(
            IOContext(buf, stdout),
            :bypass_pager => true,
            :displaysize  => displaysize(stdout),
            :limit        => false,
        )

        # Redirect `stdout` to the new buffer.
        Base.eval(:(stdout = $io))

        # First, we need to split the buffer into lines.
        lines = split(input, '\n', keepempty = true)

        # Variable to assemble the command, which can have multiple lines.
        cmd = ""

        # Variable to indicate that we have an error while evaluating the expression.
        is_error = false

        # Loop through the lines.
        @inbounds for i in eachindex(lines)
            cmd *= lines[i] * "\n"
            ast = Base.parse_input_line(cmd)

            # If the command is incomplete, we need to wait for another line.
            !isnothing(ast) && ast.head == :incomplete && continue

            # We will use `REPL.eval_on_backend` to evaluate the expression. This function
            # returns two values: the object returned by the expression, and a boolean value
            # indicating if we got an error.
            val, is_error = @static if VERSION >= v"1.11.6"
                REPL.eval_on_backend(ast, REPL.backend(repl))
            else
                REPL.eval_with_backend(ast, REPL.backend(repl))
            end

            # If we have an error, print the information and stop the processing.
            if is_error
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
                    Base.invokelatest(show, stdout, MIME("text/plain"), val)
                    write(stdout, '\n')
                end
            end

            # Clear the current command to receive the next one.
            cmd = ""
        end

        # Restore the old stdout.
        Base.eval(:(stdout = $old_stdout))

        if !is_error
            # Check if we need to use the alternate screen.
            use_alternate_screen_buffer = _get_preference(
                "always_use_alternate_screen_buffer_in_repl_mode"
            )

            # Take everything and display in the pager using `auto` mode. In this case, the
            # pager will only be called if there is not space in the display to show everything.
            pager(String(take!(buf)); auto = true, use_alternate_screen_buffer)
        end

        close(io)

    catch err
        Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())

    finally
        Base.eval(:(stdout = $old_stdout))
    end

    return nothing
end

# Execute the actions when a command has been received in the REPL mode `pager help`. `repl`
# must be the active REPL, and `input` is a string with the command.
function _tp_help_mode_do_cmd(repl::REPL.AbstractREPL, input::String)
    # We do not need to verify if we are in a interactive environment because this mode is
    # only accessible through pager mode, which already checks it.
    try
        # Create a buffer that will replace `stdout`.
        buf = IOBuffer()
        io = IOContext(
            IOContext(buf, stdout),
            :displaysize => displaysize(stdout),
            :limit => false,
        )

        # Get the AST that generates the help.
        ast = Base.invokelatest(REPL.helpmode, io, input)

        # Evaluate the AST, which returns a Markdown object.
        response = Core.eval(Main, ast)

        # Render the output.
        show(io, MIME("text/plain"), response)
        write(io, '\n')

        # Take everything and display in the pager using the alternate screen buffer to
        # avoid modifying the current screen state.
        pager(String(take!(buf)); use_alternate_screen_buffer = true)

        close(io)

    catch err
        Base.display_error(repl.t.err_stream, err, Base.catch_backtrace())
    end

    return nothing
end

############################################################################################
#                                         Prompts                                          #
############################################################################################

_tp_mode_prompt() = "pager> "
_tp_help_mode_prompt() = "pager?> "
