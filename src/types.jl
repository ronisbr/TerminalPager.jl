## Description #############################################################################
#
# Definition of types and structures.
#
############################################################################################

const SearchMatches = Dict{Int, Vector{Tuple{Int, Int}}}

"""
    Keystroke

Represent one decoded keystroke.

# Fields

- `raw::String`: Raw keystroke code converted to string.
- `value::String`: String representing the keystroke.
- `alt::Bool`: Whether the ALT key was pressed.
- `ctrl::Bool`: Whether the CTRL key was pressed.
- `shift::Bool`: Whether the SHIFT key was pressed.
- `x::Int`: One-based column of a mouse event, or `0` for a keyboard key.
- `y::Int`: One-based row of a mouse event, or `0` for a keyboard key.
"""
Base.@kwdef struct Keystroke
    raw::String = ""
    value::String = ""
    alt::Bool = false
    ctrl::Bool = false
    shift::Bool = false
    x::Int = 0
    y::Int = 0
end

"""
    Keystroke(raw::String, value::String, alt::Bool, ctrl::Bool, shift::Bool) -> Keystroke

Create a keyboard keystroke, that is, one without a mouse position.

# Arguments

- `raw::String`: Raw keystroke code converted to string.
- `value::String`: String representing the keystroke.
- `alt::Bool`: Whether the ALT key was pressed.
- `ctrl::Bool`: Whether the CTRL key was pressed.
- `shift::Bool`: Whether the SHIFT key was pressed.
"""
function Keystroke(raw::String, value::String, alt::Bool, ctrl::Bool, shift::Bool)
    return Keystroke(raw, value, alt, ctrl, shift, 0, 0)
end

"""
    PagerInput

Track shared pager input with a bounded incomplete prefix and one pending keystroke.

# Fields

- `stream::IO`: Input stream that supplies keystroke bytes.
- `prefix::Vector{UInt8}`: Bytes retained while decoding an incomplete keystroke.
- `pending::Union{Nothing, Keystroke}`: Keystroke retained at an input boundary.
- `can_lookahead::Bool`: Whether nonblocking lookahead is supported by `stream`.
"""
mutable struct PagerInput
    stream::IO
    prefix::Vector{UInt8}
    pending::Union{Nothing, Keystroke}
    can_lookahead::Bool
end

"""
    PagerInput(stream::IO) -> PagerInput

Create input state for `stream` with an empty prefix and no pending keystroke.

# Arguments

- `stream::IO`: Input stream that supplies keystroke bytes.
"""
PagerInput(stream::IO) = PagerInput(stream, UInt8[], nothing, true)

"""
    DisplayConfig

Store the pager faces rendered into escape sequences for one pager session.

Every field holds a complete SGR sequence that resets the attributes and then selects the
ones of the face, except the visual line backgrounds, which hold only the SGR parameters of
the background, as `textview` expects.

# Fields

- `status_bar::String`: Base of the status line.
- `status_hint::String`: Key hints, feature tags, and hidden text hints of the status line.
- `mode_search::String`: Name of the search mode on the status line.
- `mode_visual::String`: Name of the visual mode on the status line.
- `message_info::String`: Informative message on the status line.
- `message_error::String`: Error message on the status line.
- `search_match::String`: Inactive search match.
- `search_active_match::String`: Active search match.
- `visual_line::String`: Background of the lines marked in the visual mode.
- `visual_active_line::String`: Background of the visual line.
- `ruler::String`: Line number ruler.
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
    message_info::String
    message_error::String
    search_match::String
    search_active_match::String
    visual_line::String
    visual_active_line::String
    ruler::String
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
- `text_layout::TextViewLayout`: Canonical prepared text layout.
- `num_lines::Int`: Number of source lines.
- `text_width::Int`: Printable width of the widest source line, or a negative number if it
    was not computed yet. Read it with `_text_width`.
- `cropped_lines::Int`: Number of lines cropped below the viewport.
- `cropped_columns::Int`: Number of columns cropped to the right.
- `display_config::DisplayConfig`: Display configuration for the session.
- `input::PagerInput`: Shared input state for the session.
- `search_matches::SearchMatches`: Search matches grouped by source line.
- `ordered_search_matches::Vector{SearchMatch}`: Matches in navigation order.
- `active_search_match_id::Int`: Active match index in navigation order.
- `redraw::Bool`: Whether the viewport needs to be redrawn.
- `message::String`: Message shown on the command line until the next keystroke, or an
    empty string.
- `message_kind::Symbol`: Kind of `message`, `:info` or `:error`.
- `mode::Symbol`: Current pager mode.
- `event::Union{Nothing, Symbol}`: Pending pager event.
- `features::Vector{Symbol}`: Features enabled for the session.
- `frozen_columns::Int`: Number of frozen leading columns.
- `frozen_rows::Int`: Number of frozen leading rows.
- `title_rows::Int`: Number of title rows.
- `show_ruler::Bool`: Whether to show the line-number ruler.
- `show_scrollbar::Bool`: Whether to show the scrollbar at the right edge of the view.
- `scroll_regions::Bool`: Whether scrolling may shift the rows already on screen with the
    terminal scroll region sequences instead of repainting them.
- `view_buf::IOBuffer`: Reused buffer holding the rendered view before the scrollbar is added
    to it.
- `visual_mode::Bool`: Whether visual selection mode is active.
- `visual_mode_line::Int`: Active visual line relative to the viewport.
- `visual_mode_selected_lines::Vector{Int}`: Selected source-line indices.
- `mouse_row::Int`: Row of the last mouse event, or `0` if there was none.
- `mouse_column::Int`: Column of the last mouse event, or `0` if there was none.
- `visual_lines::Vector{Int}`: Reused buffer with the lines rendered with a background.
- `visual_line_backgrounds::Vector{String}`: Reused buffer with the background of each entry
    of `visual_lines`.
- `frame_cache::FrameCache`: State supporting the incremental redraw.
"""
Base.@kwdef mutable struct Pager
    term::REPL.Terminals.TTYTerminal
    buf::IOContext{IOBuffer}
    display_size::NTuple{2, Int} = (0, 0)
    start_row::Int = 1
    start_column::Int = 1
    text_layout::TextViewLayout
    num_lines::Int = 0
    text_width::Int = -1
    cropped_lines::Int = 0
    cropped_columns::Int = 0
    display_config::DisplayConfig = DisplayConfig()
    input::PagerInput = PagerInput(stdin)
    search_matches::SearchMatches = SearchMatches()
    ordered_search_matches::Vector{SearchMatch} = SearchMatch[]
    active_search_match_id::Int = 0
    redraw::Bool = true
    message::String = ""
    message_kind::Symbol = :info
    mode::Symbol = :view
    event::Union{Nothing, Symbol} = nothing
    features::Vector{Symbol} = Symbol[]
    frozen_columns::Int = 0
    frozen_rows::Int = 0
    title_rows::Int = 0
    show_ruler::Bool = false
    show_scrollbar::Bool = false
    scroll_regions::Bool = true
    view_buf::IOBuffer = IOBuffer()
    visual_mode::Bool = false
    visual_mode_line::Int = 1
    visual_mode_selected_lines::Vector{Int} = Int[]
    mouse_row::Int = 0
    mouse_column::Int = 0
    visual_lines::Vector{Int} = Int[]
    visual_line_backgrounds::Vector{String} = String[]
    frame_cache::FrameCache = FrameCache()
end
