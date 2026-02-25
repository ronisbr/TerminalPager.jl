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

    jl_prompt_regex = Regex("^In \\[[0-9]+\\]: |^(?:\\(.+\\) )?$(REPL.JULIA_PROMPT)")

    # == Key Mappings ======================================================================

    # We want to support all the default keymap prefixes.
    prefix_prompt, prefix_keymap = LineEdit.setup_prefix_keymap(hp, tp_mode)

    # We also want to support reverse searching.
    skeymap = @static if VERSION >= v"1.13-"
        LineEdit.history_keymap
    else
        LineEdit.setup_search_keymap(hp)[2]
    end

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
        end,

        "\e[200~" => (s::REPL.MIState, o...) -> begin
            input   = LineEdit.bracketed_paste(s)
            sbuffer = LineEdit.buffer(s)
            curspos = position(sbuffer)

            current_cmd   = ""
            prompt_beginning = true
            has_prompt = false
            dump_lines = false

            lines = split(input, '\n', keepempty = true)

            for (i, line) in enumerate(lines)
                line_has_prompt = startswith(line, jl_prompt_regex)

                (dump_lines && !line_has_prompt) && continue
                dump_lines = false

                # Check for prefix. Notice that the prefix is verifed only in the first
                # non-empty line.
                if prompt_beginning && line_has_prompt
                    has_prompt = true
                    line = chopprefix(line, jl_prompt_regex)
                end

                empty_line = isempty(strip(line))

                # We need to ignore empty lines if this is the beginning of the prompt.
                (prompt_beginning && empty_line) && continue
                prompt_beginning = false

                # If we are not at the beginning of the prompt, we should not ignore empty
                # lines, since they can be in the middle of the command.
                current_cmd *= line * "\n"
                empty_line && continue

                # Check if the expression is complete.
                ast = Meta.parse(current_cmd; raise = false, depwarn = false)
                if (isa(ast, Expr) && (ast.head === :error || ast.head === :incomplete))
                    continue
                end

                LineEdit.replace_line(s, chomp(current_cmd))

                if i == lastindex(lines)
                    LineEdit.refresh_line(s)
                    return nothing
                end

                # We need to set the option `always_show_pager_in_repl_mode` to `true` to
                # make sure the pager is always shown between the commands.
                always_show_pager = _get_preference("always_show_pager_in_repl_mode")
                set_preference!("always_show_pager_in_repl_mode", true)

                LineEdit.commit_line(s)

                terminal = LineEdit.terminal(s) # This is slightly ugly but ok for now
                REPL.raw!(terminal, false) && REPL.disable_bracketed_paste(terminal)
                @invokelatest LineEdit.mode(s).on_done(s, LineEdit.buffer(s), true)
                REPL.raw!(terminal, true) && REPL.enable_bracketed_paste(terminal)
                LineEdit.push_undo(s) # when the last line is incomplete

                set_preference!("always_show_pager_in_repl_mode", always_show_pager)

                current_cmd = ""
                prompt_beginning = true

                # If we have the prompt, we need to dump all lines until the next prompt.
                dump_lines = has_prompt
            end

            # If we reach this point, it means that we do not had a complete expression.
            # Hence, just refresh the line so the user can edit it.
            LineEdit.refresh_line(s)
            return nothing
        end,
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
    skeymap = @static if VERSION >= v"1.13-"
        LineEdit.history_keymap
    else
        LineEdit.setup_search_keymap(hp)[2]
    end

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

        has_color = get(stdout, :color, false)

        # Redirect `stdout` to the new buffer.
        Base.eval(:(stdout = $io))

        # First, we need to split the buffer into lines.
        lines = split(input, '\n', keepempty = true)

        # Variable to assemble the command, which can have multiple lines.
        cmd = ""

        # Variable to indicate that we have an error while evaluating the expression.
        is_error = false

        # Indentation for the lines.
        ind = " "^length(_tp_mode_prompt())

        # Variable to store if the current prompt output must be suppressed.
        suppress_output = true

        echo_cmd = _get_preference("echo_command_in_repl_mode")

        num_lines_in_cmd = 0

        # Loop through the lines.
        @inbounds for i in eachindex(lines)
            pad = i == firstindex(lines) ? "" : ind
            cmd *= pad * lines[i] * "\n"
            num_lines_in_cmd += 1
            ast = Meta.parse(cmd)

            # If the command is incomplete, we need to wait for another line.
            (isnothing(ast) || (ast isa Expr && ast.head == :incomplete)) && continue

            # We will use `REPL.eval_on_backend` to evaluate the expression. This function
            # returns two values: the object returned by the expression, and a boolean value
            # indicating if we got an error.
            response = @static if VERSION >= v"1.11.6"
                REPL.eval_on_backend(ast, REPL.backend(repl))
            else
                REPL.eval_with_backend(ast, REPL.backend(repl))
            end

            # If we have an error, print the information and stop the processing.
            val, is_error = response
            if is_error
                repl.waserror = true

                @static if VERSION >= v"1.11.0"
                    REPL.with_repl_linfo(repl) do io
                        io = IOContext(io, :module => Base.active_module(repl)::Module)
                        REPL.print_response(
                            io,
                            response,
                            REPL.backend(repl),
                            true,
                            has_color,
                            REPL.specialdisplay(repl)
                        )
                    end
                else
                    REPL.with_repl_linfo(repl) do io
                        io = IOContext(io, :module => REPL.active_module(repl)::Module)
                        REPL.print_response(
                            io,
                            response,
                            true,
                            has_color
                        )
                    end
                end
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

                suppress_output = false
                break
            end
        end

        # Restore the old stdout.
        Base.eval(:(stdout = $old_stdout))

        if !is_error
            # Check if we need to use the alternate screen.
            use_alternate_screen_buffer = _get_preference(
                "always_use_alternate_screen_buffer_in_repl_mode"
            )

            copy_to_clipboard = _get_preference(
                "copy_stdout_to_clipboard_in_repl_mode"
            )

            auto = !_get_preference("always_show_pager_in_repl_mode") || suppress_output

            # Take everything and display in the pager using `auto` mode. In this case, the
            # pager will only be called if there is not space in the display to show
            # everything.
            str = String(take!(buf))
            preamble = ""

            if echo_cmd
                preamble =
                    Base.text_colors[:bold] *
                    Base.text_colors[:green] *
                    REPL.JULIA_PROMPT *
                    Base.text_colors[:normal] *
                    chomp(cmd)
            end

            pager(
                str;
                auto = auto,
                preamble,
                use_alternate_screen_buffer
            )

            copy_to_clipboard && clipboard(remove_decorations(str))
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
