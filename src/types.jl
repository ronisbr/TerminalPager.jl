## Description #############################################################################
#
# Definition of types and structures.
#
############################################################################################

const SearchMatches = Dict{Int, Vector{Tuple{Int, Int}}}

"""
    struct ViewOptions

Store what the renderer needs to write a view of a [`ViewLayout`](@ref): the rows and the
columns of the view, the limits of the display, and how the rows are decorated. A negative
number of rows or columns means every remaining one, and a negative limit means none.

# Fields

- `first_row::Int`: First scrolled row.
    (**Default**: `1`)
- `num_rows::Int`: Number of scrolled rows.
    (**Default**: `-1`)
- `first_column::Int`: First scrolled printable column.
    (**Default**: `1`)
- `num_columns::Int`: Number of scrolled columns.
    (**Default**: `-1`)
- `frozen_rows::Int`: Number of leading rows written before the scrolled ones.
    (**Default**: `0`)
- `frozen_columns::Int`: Number of leading columns written before the scrolled ones in every
    row.
    (**Default**: `0`)
- `title_rows::Int`: Number of frozen rows written from the first column, which do not
    scroll horizontally.
    (**Default**: `0`)
- `max_rows::Int`: Number of rows of the display, including the frozen ones.
    (**Default**: `-1`)
- `max_columns::Int`: Width of the display, including the ruler.
    (**Default**: `-1`)
- `show_ruler::Bool`: Write the line-number ruler before each row.
    (**Default**: `false`)
- `ruler_foot::Bool`: End the ruler of the last frozen row with a foot instead of a bar.
    (**Default**: `false`)
- `line_numbers::Union{Nothing, Vector{Int}}`: Number written in the ruler for each row of
    the layout, which must not decrease, or `nothing` to write the row index. The width of
    the ruler follows the last number.
    (**Default**: `nothing`)
- `ruler_marks::Union{Nothing, Set{Int}}`: Rows whose ruler starts with a mark instead of a
    blank, or `nothing` for none.
    (**Default**: `nothing`)
- `search_matches::Union{Nothing, SearchMatches}`: Search matches of each row, as the first
    printable column and the width of each match, or `nothing` for none.
    (**Default**: `nothing`)
- `active_match::NTuple{2, Int}`: Row and index in the row of the active search match, or
    `(0, 0)` for none. A location without a match is ignored.
    (**Default**: `(0, 0)`)
- `visual_rows::Union{Nothing, Vector{Int}}`: Rows written with a background, or `nothing`
    for none. The first background of a repeated row wins.
    (**Default**: `nothing`)
- `visual_backgrounds::Union{String, Vector{String}}`: SGR parameters of the background of
    every visual row, or of each one of them.
    (**Default**: `"44"`)
- `highlight::String`: Escape sequence that decorates the search matches.
    (**Default**: `"\\e[7m"`)
- `active_highlight::String`: Escape sequence that decorates the active search match.
    (**Default**: `"\\e[30;43m"`)
- `ruler_decoration::String`: Escape sequence that decorates the ruler.
    (**Default**: `"\\e[90m"`)
- `ruler_mark_decoration::String`: Escape sequence that decorates the marks of the ruler, or
    an empty string to decorate them like the ruler.
    (**Default**: `""`)
"""
Base.@kwdef struct ViewOptions
    first_row::Int = 1
    num_rows::Int = -1
    first_column::Int = 1
    num_columns::Int = -1
    frozen_rows::Int = 0
    frozen_columns::Int = 0
    title_rows::Int = 0
    max_rows::Int = -1
    max_columns::Int = -1
    show_ruler::Bool = false
    ruler_foot::Bool = false
    line_numbers::Union{Nothing, Vector{Int}} = nothing
    ruler_marks::Union{Nothing, Set{Int}} = nothing
    search_matches::Union{Nothing, SearchMatches} = nothing
    active_match::NTuple{2, Int} = (0, 0)
    visual_rows::Union{Nothing, Vector{Int}} = nothing
    visual_backgrounds::Union{String, Vector{String}} = "44"
    highlight::String = "\e[7m"
    active_highlight::String = "\e[30;43m"
    ruler_decoration::String = "\e[90m"
    ruler_mark_decoration::String = ""
end

"""
    Keystroke

Represent one decoded keystroke.

The bytes the keystroke was decoded from are not kept. [`debug_keycode`](@ref) shows them.

# Fields

- `value::String`: String representing the keystroke.
- `alt::Bool`: Whether the ALT key was pressed.
- `ctrl::Bool`: Whether the CTRL key was pressed.
- `shift::Bool`: Whether the SHIFT key was pressed.
- `x::Int`: One-based column of a mouse event, or `0` for a keyboard key.
- `y::Int`: One-based row of a mouse event, or `0` for a keyboard key.
"""
Base.@kwdef struct Keystroke
    value::String = ""
    alt::Bool = false
    ctrl::Bool = false
    shift::Bool = false
    x::Int = 0
    y::Int = 0
end

"""
    mutable struct InputWaiter

Wait for the input of a pager session or for a change of the terminal display size,
whichever comes first.

A reader task waits for the input without consuming it, and a timer polls the display size.
Both notify `wake`. The reader waits for the input only after the pager task releases it,
and it reports the input by setting `input_seen`, so the pager task always reads the bytes
itself.

# Fields

- `wake::Base.Event`: Event notified when input arrives or the display size changes.
- `release::Base.Event`: Event that releases the reader task to wait for the next input.
- `input_seen::Bool`: Whether the reader task saw input after it was released. It is atomic.
- `closed::Bool`: Whether the waiter was closed. It is atomic.
- `armed::Bool`: Whether the reader task was released and did not report input yet. Only
    the pager task accesses it.
- `reader::Task`: Reader task.
- `timer::Timer`: Timer that polls the display size.
"""
mutable struct InputWaiter
    const wake::Base.Event
    const release::Base.Event
    @atomic input_seen::Bool
    @atomic closed::Bool
    armed::Bool
    reader::Task
    timer::Timer

    InputWaiter() = new(Base.Event(true), Base.Event(true), false, false, false)
end

"""
    PagerInput

Track shared pager input with a bounded incomplete prefix and one pending keystroke.

# Fields

- `stream::IO`: Input stream that supplies keystroke bytes.
- `prefix::Vector{UInt8}`: Bytes retained while decoding an incomplete keystroke.
- `pending::Union{Nothing, Keystroke}`: Keystroke retained at an input boundary.
- `can_lookahead::Bool`: Whether nonblocking lookahead is supported by `stream`.
- `waiter::Union{Nothing, InputWaiter}`: Waiter for the input and for the changes of the
    display size, or `nothing` if the input is read directly. It is shared by the sessions
    that share the input.
- `record::Union{Nothing, Vector{UInt8}}`: Buffer to which the bytes of every decoded
    keystroke are appended, or `nothing` to not record them.
"""
mutable struct PagerInput
    stream::IO
    prefix::Vector{UInt8}
    pending::Union{Nothing, Keystroke}
    can_lookahead::Bool
    waiter::Union{Nothing, InputWaiter}
    record::Union{Nothing, Vector{UInt8}}
end

"""
    PagerInput(stream::IO) -> PagerInput

Create input state for `stream` with an empty prefix, no pending keystroke, no waiter, and
no record.

# Arguments

- `stream::IO`: Input stream that supplies keystroke bytes.
"""
PagerInput(stream::IO) = PagerInput(stream, UInt8[], nothing, true, nothing, nothing)

"""
    DisplayConfig

Store the pager faces rendered into escape sequences for one pager session.

Every field holds a complete SGR sequence that resets the attributes and then selects the
ones of the face, except the backgrounds of the visual lines and of the search columns,
which hold only the SGR parameters of the background, as [`ViewOptions`](@ref) expects.

# Fields

- `status_bar::String`: Base of the status line.
- `status_hint::String`: Key hints, feature tags, and hidden text hints of the status line.
- `mode_search::String`: Name of the search mode on the status line.
- `mode_visual::String`: Name of the visual mode on the status line.
- `mode_freeze::String`: Name of the freeze selection mode on the status line.
- `mode_filter::String`: Name of the filter state on the status line.
- `message_info::String`: Informative message on the status line.
- `message_error::String`: Error message on the status line.
- `search_match::String`: Inactive search match.
- `search_active_match::String`: Active search match.
- `search_columns::String`: Background of the columns that restrict a search, shown while
    the range is typed or selected.
- `visual_line::String`: Background of the lines marked in the visual mode.
- `visual_active_line::String`: Background of the visual line.
- `freeze_guide::String`: Guide lines of the freeze selection mode.
- `ruler::String`: Line number ruler.
- `bookmark::String`: Mark of a bookmarked line in the ruler.
- `scrollbar_track::String`: Track of the scrollbar.
- `scrollbar_thumb::String`: Thumb of the scrollbar.
- `command_status::String`: Status shown at the right of the command line.
- `help_title::String`: Title of the help screen.
- `help_section::String`: Section titles of the help screen.
- `help_description::String`: Section descriptions and feature tags of the help screen.
- `help_key::String`: Keys of the help screen.
- `help_action::String`: Action names of the help screen.
"""
struct DisplayConfig
    status_bar::String
    status_hint::String
    mode_search::String
    mode_visual::String
    mode_freeze::String
    mode_filter::String
    message_info::String
    message_error::String
    search_match::String
    search_active_match::String
    search_columns::String
    visual_line::String
    visual_active_line::String
    freeze_guide::String
    ruler::String
    bookmark::String
    scrollbar_track::String
    scrollbar_thumb::String
    command_status::String
    help_title::String
    help_section::String
    help_description::String
    help_key::String
    help_action::String
end

"""
    SearchMatch

Represent a search match location in document and printable-column order.

# Fields

- `line::Int`: One-based source line index.
- `index_in_line::Int`: One-based match index within the source line.
- `column::Int`: One-based printable column where the match starts.
- `width::Int`: Printable width of the match.
"""
struct SearchMatch
    line::Int
    index_in_line::Int
    column::Int
    width::Int
end

"""
    struct SearchState

Store what a search changes in a pager session, so that it can be restored when the search
prompt is cancelled or when its pattern is not valid.

# Fields

- `search_matches::SearchMatches`: Search matches grouped by row.
- `ordered_search_matches::Vector{SearchMatch}`: Matches in navigation order.
- `active_search_match_id::Int`: Active match index in navigation order.
- `search_columns::UnitRange{Int}`: Printable columns in which a match must start.
- `search_pattern::String`: Input of the active search.
- `search_regex::Union{Nothing, Regex}`: Regular expression of the active search.
- `start_row::Int`: First visible row.
- `start_column::Int`: First visible printable column.
- `mode::Symbol`: Pager mode.
"""
struct SearchState
    search_matches::SearchMatches
    ordered_search_matches::Vector{SearchMatch}
    active_search_match_id::Int
    search_columns::UnitRange{Int}
    search_pattern::String
    search_regex::Union{Nothing, Regex}
    start_row::Int
    start_column::Int
    mode::Symbol
end

"""
    struct FilterState

Store what a filter changes in a pager session, so that it can be restored when the filter
prompt is cancelled or when its pattern is not valid.

# Fields

- `filter_regex::Union{Nothing, Regex}`: Regular expression of the active filter.
- `filter_inverted::Bool`: Whether the filter hides the matching lines.
- `filter_pattern::String`: Input of the active filter.
- `text_layout::ViewLayout`: Layout of the rows shown by the pager.
- `row_to_line::Union{Nothing, Vector{Int}}`: Source line of each row.
- `line_to_row::Union{Nothing, Vector{Int}}`: Row of each source line.
- `num_lines::Int`: Number of rows.
- `text_width::Int`: Printable width of the widest row, or a negative number.
- `start_row::Int`: First visible row.
- `start_column::Int`: First visible printable column.
- `visual_mode_line::Int`: Active visual line relative to the viewport.
- `search_matches::SearchMatches`: Search matches grouped by row.
- `ordered_search_matches::Vector{SearchMatch}`: Matches in navigation order.
- `active_search_match_id::Int`: Active match index in navigation order.
"""
struct FilterState
    filter_regex::Union{Nothing, Regex}
    filter_inverted::Bool
    filter_pattern::String
    text_layout::ViewLayout
    row_to_line::Union{Nothing, Vector{Int}}
    line_to_row::Union{Nothing, Vector{Int}}
    num_lines::Int
    text_width::Int
    start_row::Int
    start_column::Int
    visual_mode_line::Int
    search_matches::SearchMatches
    ordered_search_matches::Vector{SearchMatch}
    active_search_match_id::Int
end

"""
    mutable struct TerminalModes

Record the terminal modes a pager session enabled, so that they can be left and entered
again, for example around an external editor, and undone when the session ends.

# Fields

- `cursor_key_mode::Bool`: Whether the application cursor key mode was enabled.
- `alternate_screen::Bool`: Whether the alternate screen buffer was entered.
- `cursor_hidden::Bool`: Whether the cursor was hidden.
- `mouse::Bool`: Whether the mouse reporting was enabled.
"""
Base.@kwdef mutable struct TerminalModes
    cursor_key_mode::Bool = false
    alternate_screen::Bool = false
    cursor_hidden::Bool = false
    mouse::Bool = false
end

"""
    struct PagerResult

Store what a pager session leaves when it quits.

# Fields

- `selection::Vector{String}`: Lines copied by the last yank of the session, without their
    decorations, or an empty vector if nothing was copied.
- `start_row::Int`: Line of the text at the first visible row when the session quit.
- `start_column::Int`: First visible printable column when the session quit.
- `search_pattern::String`: Pattern of the active search when the session quit, or an empty
    string.
"""
struct PagerResult
    selection::Vector{String}
    start_row::Int
    start_column::Int
    search_pattern::String
end

"""
    FrameCache

Store what was last painted on the screen so that a redraw only emits the rows that changed.

The invariant is that, while `valid` is `true`, `bytes[row_first[i]:row_last[i]]` is exactly
what is on screen row `i` for every `i` in `1:num_rows`. An empty row is represented by
`row_last[i] < row_first[i]`.

# Fields

- `bytes::Vector{UInt8}`: Snapshot of the rows currently on screen.
- `row_first::Vector{Int}`: First index of each snapshot row in `bytes`.
- `row_last::Vector{Int}`: Last index of each snapshot row in `bytes`, inclusive.
- `num_rows::Int`: Number of rows the snapshot describes.
- `new_first::Vector{Int}`: First index of each row of the frame being painted.
- `new_last::Vector{Int}`: Last index of each row of the frame being painted, inclusive.
- `out::IOBuffer`: Reused buffer assembling everything sent to the terminal.
- `valid::Bool`: Whether the snapshot describes the screen.
- `start_row::Int`: First visible source row when the snapshot was painted.
- `start_column::Int`: First visible printable column when the snapshot was painted.
- `frozen_rows::Int`: Number of frozen rows when the snapshot was painted.
"""
Base.@kwdef mutable struct FrameCache
    bytes::Vector{UInt8} = UInt8[]
    row_first::Vector{Int} = Int[]
    row_last::Vector{Int} = Int[]
    num_rows::Int = 0
    new_first::Vector{Int} = Int[]
    new_last::Vector{Int} = Int[]
    out::IOBuffer = IOBuffer(; sizehint = 8192)
    valid::Bool = false
    start_row::Int = 0
    start_column::Int = 0
    frozen_rows::Int = 0
end

"""
    Pager

Store the mutable state for one pager session.

# Fields

- `term::REPL.Terminals.TTYTerminal`: Terminal used by the session.
- `buf::IOContext{IOBuffer}`: Buffered rendered output.
- `display_size::NTuple{2, Int}`: Current terminal rows and columns.
- `start_row::Int`: First visible source row.
- `start_column::Int`: First visible printable column.
- `text_layout::ViewLayout`: Layout of the rows shown by the pager, which is
    `source_layout` itself unless a filter is active, in which case it holds the visible
    lines only.
- `source_layout::ViewLayout`: Layout of every line of the text.
- `row_to_line::Union{Nothing, Vector{Int}}`: Source line of each row of `text_layout`, or
    `nothing` when the rows are the source lines.
- `line_to_row::Union{Nothing, Vector{Int}}`: Row of each source line, `0` for a hidden
    line, or `nothing` when the rows are the source lines.
- `filter_regex::Union{Nothing, Regex}`: Regular expression of the active filter, or
    `nothing`.
- `filter_inverted::Bool`: Whether the filter hides the matching lines instead of showing
    them.
- `filter_pattern::String`: Input of the active filter, or an empty string.
- `search_regex::Union{Nothing, Regex}`: Regular expression of the active search, or
    `nothing`.
- `num_lines::Int`: Number of rows of `text_layout`.

The rows of `text_layout` are the unit of `start_row`, `visual_mode_line`, the search
matches, and the frozen and title rows, whereas the marks of the visual mode, the range
anchor, and the bookmarks store source lines, so that they survive a change of the filter.
- `text_width::Int`: Printable width of the widest source line, or a negative number if it
    was not computed yet. Read it with `_text_width`.
- `cropped_lines::Int`: Number of lines cropped below the viewport.
- `cropped_columns::Int`: Number of columns cropped to the right.
- `display_config::DisplayConfig`: Display configuration for the session.
- `input::PagerInput`: Shared input state for the session.
- `search_matches::SearchMatches`: Search matches grouped by source line.
- `ordered_search_matches::Vector{SearchMatch}`: Matches in navigation order.
- `active_search_match_id::Int`: Active match index in navigation order.
- `search_columns::UnitRange{Int}`: Printable columns in which a match must start, or
    `1:typemax(Int)` when the search is not restricted.
- `search_pattern::String`: Input of the active search, or an empty string.
- `yanked::Vector{String}`: Lines copied by the last yank of the session, without their
    decorations.
- `redraw::Bool`: Whether the viewport needs to be redrawn.
- `message::String`: Message shown on the command line until the next keystroke, or an
    empty string.
- `message_kind::Symbol`: Kind of `message`, `:info` or `:error`.
- `mode::Symbol`: Current pager mode, `:view`, `:searching`, `:freeze_selection`,
    `:title_selection`, or `:column_selection`.
- `bookmarks::Dict{Char, Tuple{Int, Int}}`: Line and column of each bookmark, keyed by its
    letter. The lines are marked in the line-number ruler.
- `last_position::Tuple{Int, Int}`: Line of the text at the first visible row and first
    visible column before the last jump, or `(0, 0)` if there was none.
- `event::Union{Nothing, Symbol}`: Pending pager event.
- `features::Vector{Symbol}`: Features enabled for the session.
- `frozen_columns::Int`: Number of frozen leading columns.
- `frozen_rows::Int`: Number of frozen leading rows.
- `freeze_selection_rows::Int`: Number of rows selected in the freeze and title selection
    modes.
- `freeze_selection_columns::Int`: Number of columns selected in the freeze selection mode.
- `freeze_buf::IOBuffer`: Reused buffer holding the view with the freeze guides or the
    highlighted columns drawn before the scrollbar is added to it.
- `highlighted_columns::UnitRange{Int}`: Printable columns drawn with the background of the
    face `search_columns`, which are the ones of the search range being typed or selected,
    or an empty range.
- `column_selection_cursor::Int`: Column under the cursor of the column selection mode.
- `column_selection_anchor::Int`: First column fixed in the column selection mode, or `0`
    while it was not fixed yet.
- `title_rows::Int`: Number of title rows.
- `show_ruler::Bool`: Whether to show the line-number ruler.
- `show_column_ruler::Bool`: Whether to show the column ruler on top of the view.
- `show_scrollbar::Bool`: Whether to show the scrollbar at the right edge of the view.
- `status_position::Symbol`: Style of the position shown on the status line, `:percent`,
    `:line`, or `:both`.
- `scroll_regions::Bool`: Whether scrolling may shift the rows already on screen with the
    terminal scroll region sequences instead of repainting them.
- `view_buf::IOBuffer`: Reused buffer holding the rendered view before the scrollbar is added
    to it.
- `literal_search::Bool`: Whether the search patterns are literal text instead of regexes.
- `visual_mode::Bool`: Whether visual selection mode is active.
- `visual_mode_line::Int`: Active visual line relative to the viewport.
- `visual_mode_selected_lines::Vector{Int}`: Selected source-line indices.
- `visual_anchor::Int`: Line anchoring a range that ends at the visual line, or `0` when
    there is no range.
- `mouse_row::Int`: Row of the last mouse event, or `0` if there was none.
- `mouse_column::Int`: Column of the last mouse event, or `0` if there was none.
- `visual_lines::Vector{Int}`: Reused buffer with the lines rendered with a background.
- `visual_line_backgrounds::Vector{String}`: Reused buffer with the background of each entry
    of `visual_lines`.
- `frame_cache::FrameCache`: State supporting the incremental redraw.
- `terminal_modes::TerminalModes`: Terminal modes enabled by the session.
- `temporary_files::Vector{String}`: Files created by the session, like the ones opened in
    the editor, which are removed when the session ends.
"""
Base.@kwdef mutable struct Pager
    term::REPL.Terminals.TTYTerminal
    buf::IOContext{IOBuffer}
    display_size::NTuple{2, Int} = (0, 0)
    start_row::Int = 1
    start_column::Int = 1
    text_layout::ViewLayout
    source_layout::ViewLayout = text_layout
    row_to_line::Union{Nothing, Vector{Int}} = nothing
    line_to_row::Union{Nothing, Vector{Int}} = nothing
    filter_regex::Union{Nothing, Regex} = nothing
    filter_inverted::Bool = false
    filter_pattern::String = ""
    search_regex::Union{Nothing, Regex} = nothing
    num_lines::Int = 0
    text_width::Int = -1
    cropped_lines::Int = 0
    cropped_columns::Int = 0
    display_config::DisplayConfig = DisplayConfig()
    input::PagerInput = PagerInput(stdin)
    search_matches::SearchMatches = SearchMatches()
    ordered_search_matches::Vector{SearchMatch} = SearchMatch[]
    active_search_match_id::Int = 0
    search_columns::UnitRange{Int} = 1:typemax(Int)
    search_pattern::String = ""
    yanked::Vector{String} = String[]
    redraw::Bool = true
    message::String = ""
    message_kind::Symbol = :info
    mode::Symbol = :view
    bookmarks::Dict{Char, Tuple{Int, Int}} = Dict{Char, Tuple{Int, Int}}()
    last_position::Tuple{Int, Int} = (0, 0)
    event::Union{Nothing, Symbol} = nothing
    features::Vector{Symbol} = Symbol[]
    frozen_columns::Int = 0
    frozen_rows::Int = 0
    freeze_selection_rows::Int = 0
    freeze_selection_columns::Int = 0
    freeze_buf::IOBuffer = IOBuffer()
    highlighted_columns::UnitRange{Int} = 1:0
    column_selection_cursor::Int = 0
    column_selection_anchor::Int = 0
    title_rows::Int = 0
    show_ruler::Bool = false
    show_column_ruler::Bool = false
    show_scrollbar::Bool = false
    status_position::Symbol = :percent
    scroll_regions::Bool = true
    view_buf::IOBuffer = IOBuffer()
    literal_search::Bool = false
    visual_mode::Bool = false
    visual_mode_line::Int = 1
    visual_mode_selected_lines::Vector{Int} = Int[]
    visual_anchor::Int = 0
    mouse_row::Int = 0
    mouse_column::Int = 0
    visual_lines::Vector{Int} = Int[]
    visual_line_backgrounds::Vector{String} = String[]
    frame_cache::FrameCache = FrameCache()
    terminal_modes::TerminalModes = TerminalModes()
    temporary_files::Vector{String} = String[]
end

"""
    mutable struct SessionOptions

Store the options of a pager session, which are the keywords of [`pager`](@ref) together
with the objects and the functions that the internal callers and the tests provide.

The keywords are collected into this structure by [`_session_options`](@ref) once, when the
session starts. Passing them from function to function as keywords instead would compile
all those functions again for each combination of keywords used in a Julia session.

# Fields

- `auto::Bool`: Print the text without opening the pager if it fits in the display.
    (**Default**: `false`)
- `return_selection::Bool`: Return the [`PagerResult`](@ref) of the session instead of
    `nothing`.
    (**Default**: `false`)
- `change_freeze::Bool`: Enable the commands that change the frozen rows and columns.
    (**Default**: `true`)
- `frozen_columns::Int`: Number of leading columns to freeze.
    (**Default**: `0`)
- `frozen_rows::Int`: Number of leading rows to freeze.
    (**Default**: `0`)
- `title_rows::Int`: Number of leading title rows.
    (**Default**: `0`)
- `has_help::Bool`: Enable the pager help.
    (**Default**: `true`)
- `has_visual_mode::Bool`: Enable the visual selection mode.
    (**Default**: `true`)
- `show_ruler::Bool`: Show the line-number ruler initially.
    (**Default**: `false`)
- `show_column_ruler::Bool`: Show the column ruler initially.
    (**Default**: the value of the preference `"show_column_ruler"`)
- `show_scrollbar::Bool`: Show the scrollbar initially.
    (**Default**: the value of the preference `"show_scrollbar"`)
- `use_alternate_screen_buffer::Bool`: Request the alternate screen buffer of the terminal.
    (**Default**: `true`)
- `display_config::Union{Nothing, DisplayConfig}`: Prepared display configuration of the
    session, or `nothing` to load one.
    (**Default**: `nothing`)
- `input::Union{Nothing, PagerInput}`: Input state associated with the input stream of the
    terminal, or `nothing` to create one.
    (**Default**: `nothing`)
- `text_layout::Union{Nothing, ViewLayout}`: Prepared layout of the text, or `nothing` to
    create one.
    (**Default**: `nothing`)
- `manage_cursor_key_mode::Bool`: Enable and restore the cursor-key mode of the terminal.
    (**Default**: `true`)
- `manage_cursor::Bool`: Hide the cursor during the session, and show it and clear the
    status bar row when the session ends. A nested session must not do this.
    (**Default**: `true`)
- `manage_mouse::Bool`: Enable the mouse reporting during the session if the preference
    `"mouse"` is enabled, and disable it when the session ends. A nested session must not
    do this.
    (**Default**: `true`)
- `_display_config_loader::Any`: Callable object that creates the display configuration of
    the session.
    (**Default**: `_display_config`)
- `_input_factory::Any`: Callable object that creates the input state for a stream.
    (**Default**: `PagerInput`)
- `_layout_factory::Any`: Callable object that creates a layout from the lines of the text.
    (**Default**: `ViewLayout`)
- `_terminal_factory::Any`: Callable object that creates the terminal.
    (**Default**: `_default_terminal`)
- `_raw_runner::Any`: Callable object that runs the session in the raw mode.
    (**Default**: `_with_raw_mode`)
- `_waiter_factory::Any`: Callable object that receives the terminal and returns the
    [`InputWaiter`](@ref) of the session, which repaints the screen when the display size
    changes, or `nothing` to read the input directly. It is called only when the input has
    no waiter, and the session closes the waiter it created. A nested session shares the
    waiter of its parent.
    (**Default**: `_default_input_waiter`)
- `_restore::Union{Nothing, PagerResult}`: Result of a previous session over the text whose
    viewport and search are restored, or `nothing` to start at the top.
    (**Default**: `nothing`)
- `_bookmarks::Dict{Char, Tuple{Int, Int}}`: Bookmarks the session starts with, which are
    the line and the column of each letter, like the chapters of the extended help.
    (**Default**: no bookmarks)
"""
Base.@kwdef mutable struct SessionOptions
    auto::Bool = false
    return_selection::Bool = false
    change_freeze::Bool = true
    frozen_columns::Int = 0
    frozen_rows::Int = 0
    title_rows::Int = 0
    has_help::Bool = true
    has_visual_mode::Bool = true
    show_ruler::Bool = false
    show_column_ruler::Bool = _get_preference("show_column_ruler")::Bool
    show_scrollbar::Bool = _get_preference("show_scrollbar")::Bool
    use_alternate_screen_buffer::Bool = true
    display_config::Union{Nothing, DisplayConfig} = nothing
    input::Union{Nothing, PagerInput} = nothing
    text_layout::Union{Nothing, ViewLayout} = nothing
    manage_cursor_key_mode::Bool = true
    manage_cursor::Bool = true
    manage_mouse::Bool = true
    _display_config_loader::Any = _display_config
    _input_factory::Any = PagerInput
    _layout_factory::Any = ViewLayout
    _terminal_factory::Any = _default_terminal
    _raw_runner::Any = _with_raw_mode
    _waiter_factory::Any = _default_input_waiter
    _restore::Union{Nothing, PagerResult} = nothing
    _bookmarks::Dict{Char, Tuple{Int, Int}} = Dict{Char, Tuple{Int, Int}}()
end
