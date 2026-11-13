## Description #############################################################################
#
# Commands that take the text out of the pager: copy to the clipboard, open in the editor,
# and save to a file.
#
############################################################################################

"""
    _yank!(pagerd::Pager) -> Nothing

Copy the visual line and the marked lines of `pagerd` to the system clipboard, leaving a
message telling how many lines were copied, or that the clipboard is not available.
Nothing happens outside the visual mode.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _yank!(pagerd::Pager)
    pagerd.visual_mode || return nothing
    _copy_lines!(pagerd, pagerd.source_layout, _selected_line_ids(pagerd))
    return nothing
end

"""
    _yank_all!(pagerd::Pager) -> Nothing

Copy the whole text of `pagerd` to the system clipboard, leaving a message telling how many
lines were copied, that the clipboard is not available, or that there is nothing to copy.

# Arguments

- `pagerd::Pager`: Pager state to update.
"""
function _yank_all!(pagerd::Pager)
    if pagerd.num_lines == 0
        _set_message!(pagerd, "Nothing to copy"; kind = :error)
        return nothing
    end

    _copy_lines!(pagerd, pagerd.text_layout, 1:pagerd.num_lines)

    return nothing
end

"""
    _copy_lines!(pagerd::Pager, layout::ViewLayout, line_ids::AbstractVector{<:Integer}) ->
        Nothing

Copy the lines `line_ids` of `layout` to the system clipboard without their decorations,
leaving a message in `pagerd` telling how many lines were copied, or that the clipboard is
not available.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `layout::ViewLayout`: Layout the lines are taken from.
- `line_ids::AbstractVector{<:Integer}`: Lines to copy.
"""
function _copy_lines!(
    pagerd::Pager, layout::ViewLayout, line_ids::AbstractVector{<:Integer}
)
    yanked_lines = _undecorated_lines(layout, line_ids)
    num_yanked_lines = length(yanked_lines)
    yanked_text = _join_lines(yanked_lines)

    # The lines are kept before the clipboard is tried, so that they are returned by the
    # session and by `yanked` even where there is no clipboard.
    pagerd.yanked = yanked_lines
    empty!(_LAST_YANK)
    append!(_LAST_YANK, yanked_lines)

    # `clipboard` throws when no system clipboard provider is available, for example in a
    # headless session. The error must not tear down the pager.
    copied = try
        _CLIPBOARD[](yanked_text)
        true
    catch
        false
    end

    if copied
        _set_message!(
            pagerd,
            num_yanked_lines > 1 ? "$(num_yanked_lines) lines copied" : "1 line copied",
        )
    else
        _set_message!(pagerd, "Could not copy to the system clipboard"; kind = :error)
    end

    return nothing
end

"""
    _assemble_yank_text(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer};
        kwargs...
    ) -> Tuple{String, Int}

Assemble sorted, deduplicated lines with a trailing newline and return the text and the
selected-line count. The decorations are removed unless `keep_decorations` is `true`.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Canonical line sequence.
- `line_ids::AbstractVector{<:Integer}`: One-based line indices to sort and deduplicate.

# Keywords

- `keep_decorations::Bool`: Keep the escape sequences of the lines.
    (**Default**: `false`)
"""
function _assemble_yank_text(
    lines::AbstractVector{<:AbstractString}, line_ids; keep_decorations::Bool = false
)
    selected = _undecorated_lines(lines, line_ids; keep_decorations = keep_decorations)
    return _join_lines(selected), length(selected)
end

"""
    _undecorated_lines(
        lines::AbstractVector{<:AbstractString},
        line_ids::AbstractVector{<:Integer};
        kwargs...
    ) -> Vector{String}

Return the lines `line_ids` of `lines`, sorted and deduplicated, without their decorations
unless `keep_decorations` is `true`.

# Arguments

- `lines::AbstractVector{<:AbstractString}`: Canonical line sequence.
- `line_ids::AbstractVector{<:Integer}`: One-based line indices to sort and deduplicate.

# Keywords

- `keep_decorations::Bool`: Keep the escape sequences of the lines.
    (**Default**: `false`)
"""
function _undecorated_lines(
    lines::AbstractVector{<:AbstractString}, line_ids; keep_decorations::Bool = false
)
    ids = sort!(unique!(collect(Int, line_ids)))
    selected = Vector{String}(undef, length(ids))

    for (i, id) in enumerate(ids)
        line = lines[id]
        selected[i] = keep_decorations ? String(line) : remove_decorations(line)
    end

    return selected
end

"""
    _join_lines(lines::Vector{String}) -> String

Join `lines` with a newline after each one of them.

# Arguments

- `lines::Vector{String}`: Lines to join.
"""
function _join_lines(lines::Vector{String})
    buf = IOBuffer(; sizehint = sum(sizeof, lines; init = 0) + length(lines))

    for line in lines
        write(buf, line, '\n')
    end

    return String(take!(buf))
end

# Function that opens a file in the editor at a line. It is a reference so that the tests
# can replace it.
const _EDITOR = Ref{Any}(InteractiveUtils.edit)

# Function that copies a text to the system clipboard. It is a reference so that the tests
# and the precompilation workload can replace it, because they must not change the
# clipboard of the user.
const _CLIPBOARD = Ref{Any}(InteractiveUtils.clipboard)

"""
    _edit!(pagerd::Pager) -> Nothing

Open the lines selected in the visual mode of `pagerd`, or the whole text outside it, in the
editor of `InteractiveUtils.edit` at the visual line or the first visible row. The text is
written without the decorations to a temporary file, which is deleted when the editor
returns. The terminal modes and the raw mode are left while the editor runs and entered
again afterwards, and the screen is repainted.

# Arguments

- `pagerd::Pager`: Pager state whose text is edited.
"""
function _edit!(pagerd::Pager)
    layout, ids = _selected_text(pagerd)

    if isempty(ids)
        _set_message!(pagerd, "Nothing to edit"; kind = :error)
        return nothing
    end

    text, _ = _assemble_yank_text(layout, ids)

    # The editor opens at the visual line, which is in the selection, or at the top row.
    line = if pagerd.visual_mode
        something(findfirst(==(_source_line(pagerd, _visual_line_index(pagerd))), ids), 1)
    else
        pagerd.start_row
    end

    path = tempname() * ".txt"
    write(path, text)

    modes = pagerd.terminal_modes
    term = pagerd.term

    # The editor needs the normal screen, a visible cursor, and the cooked input.
    _leave_terminal_modes!(modes, term.out_stream)
    _set_raw_mode!(term, false)

    try
        _EDITOR[](path, line)
    catch err
        err isa InterruptException && rethrow()
        _set_message!(
            pagerd, "Could not open the editor: $(sprint(showerror, err))"; kind = :error
        )
    finally
        _set_raw_mode!(term, true)
        _enter_terminal_modes!(
            modes,
            term.out_stream;
            cursor_key_mode = modes.cursor_key_mode,
            alternate_screen = modes.alternate_screen,
            hide_cursor = modes.cursor_hidden,
            mouse = modes.mouse,
        )
        rm(path; force = true)

        # The editor painted over the screen, so nothing of the frame is known anymore.
        _invalidate_frame!(pagerd)
        _request_redraw!(pagerd)
    end

    return nothing
end

# Lines copied by the last yank of the session, returned by `yanked`.
const _LAST_YANK = String[]

"""
    yanked() -> Vector{String}

Return a copy of the lines copied by the last yank of the current Julia session, without
their decorations, or an empty vector if nothing was copied yet. The lines are kept even
when the system clipboard is not available.

# Examples

```julia
julia> lines = TerminalPager.yanked()
```
"""
yanked() = copy(_LAST_YANK)

"""
    _save!(pagerd::Pager) -> Nothing

Prompt for a path and save the lines selected in the visual mode of `pagerd`, or the whole
text outside it, to that file without the decorations. A path starting with `!` keeps them.
A tilde is expanded, an existing file is overwritten only after a confirmation, and the
result or the error is reported on the status line.

# Arguments

- `pagerd::Pager`: Pager state whose text is saved.
"""
function _save!(pagerd::Pager)
    cmd_input = _read_cmd!(pagerd; prefix = "Save to › ", history = _SAVE_HISTORY)
    _request_redraw!(pagerd)
    isnothing(cmd_input) && return nothing

    keep_decorations = startswith(cmd_input, '!')
    path = String(strip(keep_decorations ? cmd_input[2:end] : cmd_input))
    isempty(path) && return nothing

    layout, ids = _selected_text(pagerd)

    if isempty(ids)
        _set_message!(pagerd, "Nothing to save"; kind = :error)
        return nothing
    end

    # The errors of the path and of the file system, like the home directory of another
    # user, a missing directory, or a denied permission, are reported on the status line
    # instead of tearing down the pager. Notice that expanding the path and verifying if it
    # exists can also throw.
    path_exists = false

    try
        path = expanduser(path)
        path_exists = ispath(path)
    catch err
        _report_save_error!(pagerd, err)
        return nothing
    end

    if path_exists
        answer = _prompt_key!(pagerd, "Overwrite $path? (y/n)")

        if answer != 'y'
            _set_message!(pagerd, "Save cancelled")
            return nothing
        end
    end

    text, num_saved_lines = _assemble_yank_text(
        layout, ids; keep_decorations = keep_decorations
    )

    try
        write(path, text)
    catch err
        _report_save_error!(pagerd, err)
        return nothing
    end

    _push_history!(_SAVE_HISTORY, cmd_input)
    if num_saved_lines > 1
        _set_message!(pagerd, "$num_saved_lines lines saved to $path")
    else
        _set_message!(pagerd, "1 line saved to $path")
    end

    return nothing
end

"""
    _report_save_error!(pagerd::Pager, err::Any) -> Nothing

Show on the status line of `pagerd` why the text could not be saved, given the error `err`
thrown while the path was expanded or accessed. Any other kind of error is thrown again.

# Arguments

- `pagerd::Pager`: Pager state to update.
- `err::Any`: Error thrown by the save command.
"""
function _report_save_error!(pagerd::Pager, err)
    reason = if err isa SystemError
        Libc.strerror(err.errnum)
    elseif err isa Base.IOError
        Base.struverror(err.code)
    elseif err isa ArgumentError
        err.msg
    else
        rethrow(err)
    end

    _set_message!(pagerd, "Could not save: $reason"; kind = :error)

    return nothing
end
