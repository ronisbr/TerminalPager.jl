## Description #############################################################################
#
# History of the texts shown by the pager, so that they can be reopened after the pager
# quits and the alternate screen buffer erases them.
#
############################################################################################

"""
    mutable struct PagerHistoryEntry

Store one text shown by the pager.

# Fields

- `text::String`: Rendered text.
- `options::NamedTuple`: Keywords the pager was opened with.
- `time::Float64`: Time the text was shown, in seconds since the epoch.
- `result::Union{Nothing, PagerResult}`: Result of the last session over the text, which
    restores its viewport when the text is reopened, or `nothing` if no session ended yet.
"""
mutable struct PagerHistoryEntry
    text::String
    options::NamedTuple
    time::Float64
    result::Union{Nothing, PagerResult}
end

# Texts shown by the pager in this session, from the oldest to the newest.
const _PAGER_HISTORY = PagerHistoryEntry[]

"""
    last(n::Integer = 1) -> Nothing

Reopen the `n`-th most recent text shown by the pager in this Julia session, where the
viewport and the search of the last session over it are restored. The text is printed
instead if the standard input or output is not a terminal. Reopening a text does not add an
entry to the history, which is listed by [`history`](@ref).

This function is not exported, so that it does not clash with `Base.last`; call it as
`TerminalPager.last()`.

# Arguments

- `n::Integer`: Position of the text in the history, from the most recent one.
    (**Default**: `1`)

# Extended help

## Throws

- `ArgumentError`: If the history is empty or has fewer than `n` entries.

## Examples

```julia
julia> TerminalPager.last()

julia> TerminalPager.last(2)
```
"""
function last(n::Integer = 1)
    num_entries = length(_PAGER_HISTORY)
    num_entries == 0 && throw(ArgumentError("The pager history is empty."))
    (1 <= n <= num_entries) || throw(
        ArgumentError(
            "The pager history has $num_entries entries, so the entry $n does not exist."
        ),
    )

    entry = _PAGER_HISTORY[end - n + 1]

    # Like `pager`, print the text when the pager cannot run.
    if !(_is_terminal(stdin) && _is_terminal(stdout))
        print(entry.text)
        return nothing
    end

    options = merge(
        entry.options, (; auto = false, return_selection = true, _restore = entry.result)
    )
    result = _pager(entry.text; options...)
    (result isa PagerResult) && (entry.result = result)

    return nothing
end

"""
    history(io::IO = stdout) -> Nothing

Print to `io` the texts shown by the pager in this Julia session, from the most recent one,
with the position to pass to [`last`](@ref), the time, the number of lines, and the first
line of each text.

# Arguments

- `io::IO`: Output stream.
    (**Default**: `stdout`)

# Examples

```julia
julia> TerminalPager.history()
```
"""
function history(io::IO = stdout)
    num_entries = length(_PAGER_HISTORY)

    if num_entries == 0
        println(io, "The pager history is empty.")
        return nothing
    end

    width = max(displaysize(io)[2], 40)

    for n in 1:num_entries
        println(io, _history_label(n, _PAGER_HISTORY[end - n + 1]; width = width))
    end

    return nothing
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _push_pager_history!(text::String, options::NamedTuple) -> PagerHistoryEntry

Add `text`, shown with the keywords `options`, as the newest entry of the pager history,
dropping the oldest entries beyond the preferences `"history_size"` and
`"history_max_bytes"`, and return the entry.

# Arguments

- `text::String`: Rendered text.
- `options::NamedTuple`: Keywords the pager was opened with.
"""
function _push_pager_history!(text::String, options::NamedTuple)
    entry = PagerHistoryEntry(text, options, time(), nothing)
    push!(_PAGER_HISTORY, entry)
    _trim_pager_history!()
    return entry
end

"""
    _trim_pager_history!() -> Nothing

Drop the oldest entries of the pager history beyond the number of entries of the preference
`"history_size"`, and then beyond the bytes of the preference `"history_max_bytes"`. The
newest entry is always kept, so that [`last`](@ref) can always reopen it.
"""
function _trim_pager_history!()
    max_entries = _get_preference("history_size")::Int
    max_bytes = _get_preference("history_max_bytes")::Int

    while length(_PAGER_HISTORY) > max(max_entries, 1)
        popfirst!(_PAGER_HISTORY)
    end

    while (length(_PAGER_HISTORY) > 1) && (_history_bytes() > max_bytes)
        popfirst!(_PAGER_HISTORY)
    end

    return nothing
end

"""
    _history_bytes() -> Int

Return the number of bytes of the texts in the pager history.
"""
_history_bytes() = sum(entry -> sizeof(entry.text), _PAGER_HISTORY; init = 0)

"""
    _history_num_lines(text::String) -> Int

Return the number of lines of `text`, where a trailing newline does not add a line.

# Arguments

- `text::String`: Text to measure.
"""
function _history_num_lines(text::String)
    isempty(text) && return 0
    num_lines = count(==('\n'), text) + 1
    endswith(text, '\n') && (num_lines -= 1)
    return num_lines
end

"""
    _history_label(n::Int, entry::PagerHistoryEntry; width::Int) -> String

Return the label of `entry` at the position `n` of the history: the position, the time, the
number of lines, and the first line of the text without the decorations, cropped so that the
label fits in `width` columns.

# Arguments

- `n::Int`: Position of the entry, from the most recent one.
- `entry::PagerHistoryEntry`: Entry to describe.

# Keywords

- `width::Int`: Maximum width of the label.
"""
function _history_label(n::Int, entry::PagerHistoryEntry; width::Int)
    num_lines = _history_num_lines(entry.text)
    prefix = string(
        "#", n, "  ", Libc.strftime("%H:%M", entry.time), "  ", num_lines,
        num_lines == 1 ? " line  " : " lines  ",
    )

    first_line = remove_decorations(first(split(entry.text, '\n')))
    available = width - textwidth(prefix)
    available <= 0 && return rstrip(prefix)

    # The first line is cropped at the display width with an ellipsis.
    cropped = IOBuffer()
    cropped_width = 0

    for c in first_line
        character_width = textwidth(c)

        if cropped_width + character_width > available - 1
            write(cropped, "…")
            break
        end

        write(cropped, c)
        cropped_width += character_width
    end

    return prefix * String(take!(cropped))
end

"""
    _history_menu(term::REPL.Terminals.TTYTerminal; kwargs...) -> Int

Show a menu with the entries of the pager history on `term` and return the position of the
chosen one, or `0` if the history is empty or the menu was cancelled.

# Arguments

- `term::REPL.Terminals.TTYTerminal`: Terminal showing the menu.

# Keywords

- `request::Any`: Callable object running the menu, which receives the terminal and the
    menu and returns the chosen option or `-1`.
    (**Default**: `REPL.TerminalMenus.request`)
"""
function _history_menu(
    @nospecialize(term::REPL.Terminals.TTYTerminal); request = REPL.TerminalMenus.request
)
    num_entries = length(_PAGER_HISTORY)
    num_entries == 0 && return 0

    # Options wider than the display break the cursor movement of the menu.
    width = max(displaysize(term.out_stream)[2] - 4, 20)
    labels = [
        _history_label(n, _PAGER_HISTORY[end - n + 1]; width = width) for n in 1:num_entries
    ]

    menu = REPL.TerminalMenus.RadioMenu(
        labels; pagesize = min(10, num_entries), ctrl_c_interrupt = false
    )

    # The menu starts below the prompt.
    println(term.out_stream)
    choice = request(term, menu)

    return choice == -1 ? 0 : choice
end

"""
    _register_history_shortcuts(repl::Any) -> Task

Register `<Alt> + l`, which reopens the last text shown by the pager, and `<Alt> + L`, which
opens a menu with the history, in the pager prompts of the REPL.

# Arguments

- `repl::Any`: REPL instance whose keymaps are updated asynchronously.
"""
function _register_history_shortcuts(repl)
    return _register_shortcuts(_register_history_escapes!, repl; main_mode = false)
end

"""
    _register_history_escapes!(escapes::AbstractDict) -> Nothing

Bind `<Alt> + l` and `<Alt> + L` in the escape key map `escapes` to the history shortcuts.

# Arguments

- `escapes::AbstractDict`: Escape key map of a REPL prompt.
"""
function _register_history_escapes!(escapes)
    escapes['l'] = _reopen_last_output
    escapes['L'] = _choose_history_entry
    return nothing
end

"""
    _reopen_last_output(s::Any, _key::Any, _context::Any) -> Symbol

Reopen the last text shown by the pager from the REPL prompt, or tell that the history is
empty.

# Arguments

- `s::Any`: Current REPL line-edit state.
- `_key::Any`: Keybinding callback key, which is ignored.
- `_context::Any`: Keybinding callback context, which is ignored.
"""
function _reopen_last_output(s, _key, _context)
    term = LineEdit.terminal(s)

    # The pager leaves the raw mode off, whereas the prompt expects it on.
    _with_raw_restoration(term) do
        if isempty(_PAGER_HISTORY)
            println(term.out_stream)
            println(term.out_stream, "The pager history is empty.")
        else
            last()
        end
    end

    LineEdit.refresh_line(s)

    return :ok
end

"""
    _choose_history_entry(s::Any, _key::Any, _context::Any) -> Symbol

Show the menu of the pager history from the REPL prompt and reopen the chosen text.

# Arguments

- `s::Any`: Current REPL line-edit state.
- `_key::Any`: Keybinding callback key, which is ignored.
- `_context::Any`: Keybinding callback context, which is ignored.
"""
function _choose_history_entry(s, _key, _context)
    term = LineEdit.terminal(s)

    _with_raw_restoration(term) do
        if isempty(_PAGER_HISTORY)
            println(term.out_stream)
            println(term.out_stream, "The pager history is empty.")
        else
            n = _history_menu(term)
            (n > 0) && last(n)
        end
    end

    LineEdit.refresh_line(s)

    return :ok
end
