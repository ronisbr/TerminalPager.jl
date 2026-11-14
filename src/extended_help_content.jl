## Description #############################################################################
#
# Text of the extended help. The manual is written with the blocks of `ManualBlock`, so that
# it is laid out for the width of the display and its keys follow the key bindings.
#
############################################################################################

############################################################################################
#                                          Blocks                                          #
############################################################################################

"""
    _manual_paragraph(text::String) -> ManualBlock

Create a paragraph of the extended help with the marked `text`.
"""
_manual_paragraph(text::String) = ManualBlock(:paragraph, "", text, Pair{String, String}[])

"""
    _manual_heading(title::String) -> ManualBlock

Create a section title of the extended help.
"""
_manual_heading(title::String) = ManualBlock(:heading, title, "", Pair{String, String}[])

"""
    _manual_keys(items::Vector{Pair{String, String}}) -> ManualBlock

Create a key table of the extended help. Each item is a key, which is an action written as
`":action"` or the name of a key, and its marked description.
"""
_manual_keys(items::Vector{Pair{String, String}}) = ManualBlock(:keys, "", "", items)

"""
    _manual_definitions(items::Vector{Pair{String, String}}) -> ManualBlock

Create a list of terms of the extended help. Each item is a term, written as code, and its
marked description.
"""
function _manual_definitions(items::Vector{Pair{String, String}})
    return ManualBlock(:definitions, "", "", items)
end

"""
    _manual_list(texts::Vector{String}; numbered::Bool = false) -> ManualBlock

Create a list of the extended help with one item per marked text in `texts`, bulleted or, if
`numbered` is `true`, numbered.
"""
function _manual_list(texts::Vector{String}; numbered::Bool = false)
    items = Pair{String, String}["" => text for text in texts]
    return ManualBlock(numbered ? :steps : :list, "", "", items)
end

"""
    _manual_remark(kind::Symbol, text::String) -> ManualBlock

Create a boxed remark of the extended help with the marked `text`, where `kind` is `:tip`,
`:note`, or `:warning`.
"""
function _manual_remark(kind::Symbol, text::String)
    return ManualBlock(kind, "", text, Pair{String, String}[])
end

"""
    _manual_example(title::String, items::Vector{Pair{String, String}}) -> ManualBlock

Create an example of the extended help with `title`. Each item is a line of code and its
comment, which can be empty.
"""
function _manual_example(title::String, items::Vector{Pair{String, String}})
    return ManualBlock(:example, title, "", items)
end

"""
    _manual_figure(items::Vector{Pair{String, String}}) -> ManualBlock

Create a figure of the extended help. Each item is a preformatted line and its label, which
can be empty.
"""
_manual_figure(items::Vector{Pair{String, String}}) = ManualBlock(:figure, "", "", items)

############################################################################################
#                                         Chapters                                         #
############################################################################################

"""
    _manual_chapters() -> Vector{ManualChapter}

Return the chapters of the extended help.

The chapters are created when the manual is rendered, and not when the package is loaded,
so that they cost nothing to the sessions that never open it. The last chapter is generated
from the table of the help screen, which is the single place where the actions are
described.
"""
function _manual_chapters()
    return ManualChapter[
        ManualChapter("Getting started", _manual_getting_started()),
        ManualChapter("The screen", _manual_screen()),
        ManualChapter("Moving around", _manual_moving()),
        ManualChapter("Jumping to a position", _manual_positions()),
        ManualChapter("Searching", _manual_searching()),
        ManualChapter("Searching in columns", _manual_column_search()),
        ManualChapter("Filtering lines", _manual_filtering()),
        ManualChapter("Freezing rows and columns", _manual_freezing()),
        ManualChapter("Visual mode", _manual_visual_mode()),
        ManualChapter("Copying, saving, and editing", _manual_copying()),
        ManualChapter("Using the mouse", _manual_mouse()),
        ManualChapter("The REPL modes", _manual_repl()),
        ManualChapter("Calling the pager from code", _manual_calling()),
        ManualChapter("Preferences", _manual_preferences()),
        ManualChapter("Key bindings", _manual_keybindings()),
        ManualChapter("Faces and colors", _manual_faces()),
        ManualChapter("Terminals and troubleshooting", _manual_troubleshooting()),
        ManualChapter("Action reference", _manual_action_reference()),
    ]
end

"""
    _manual_getting_started() -> Vector{ManualBlock}

Return the chapter of the extended help that introduces the pager.
"""
function _manual_getting_started()
    return ManualBlock[
        _manual_paragraph(
            "*TerminalPager.jl* shows a text that does not fit in the terminal and lets " *
            "you move through it. It is written entirely in Julia, it follows the keys " *
            "of `less` and Vi, and it adds what tables and long outputs ask for: frozen " *
            "headers, searches restricted to columns, filters, selections, and more.",
        ),
        _manual_paragraph(
            "The function `pager` opens it for any object. A string is shown as it is, " *
            "with its colors, and every other object is rendered like the REPL shows " *
            "it, with `show` and the MIME type `text/plain`.",
        ),
        _manual_example(
            "Opening the pager",
            [
                "pager(rand(100, 100))" => "page a large matrix",
                "rand(100, 100) |> pager" => "the same, as a pipe",
                "@help write" => "page a docstring",
                "@out2pr versioninfo()" => "page what a command prints",
            ],
        ),
        _manual_heading("The first keys"),
        _manual_keys([
            ":down" => "Scroll one line down.",
            ":up" => "Scroll one line up.",
            ":pagedown" => "Scroll one page down.",
            ":pageup" => "Scroll one page up.",
            ":search" => "Search for a pattern.",
            ":quit" => "Quit the pager.",
            ":help" => "Show the cheat sheet.",
            ":extended_help" => "Show this manual.",
        ]),
        _manual_heading("Two kinds of help"),
        _manual_paragraph(
            "{:help} opens a cheat sheet: one row per action with its keys, a short " *
            "description, and the name of the action. {:extended_help} opens this " *
            "manual, which explains each feature in detail. Both are closed with {:quit}.",
        ),
        _manual_remark(
            :tip,
            "The keys of this manual are the ones bound right now. If you change a key " *
            "binding, the manual, the cheat sheet, and the hints of the status line " *
            "follow it. An action without a key is shown as {:} in the text and as a " *
            "dash in the tables.",
        ),
    ]
end

"""
    _manual_screen() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the screen of the pager.
"""
function _manual_screen()
    return ManualBlock[
        _manual_paragraph(
            "The text takes the whole terminal but its last row, which is the status " *
            "line. Three optional elements can be added around the text: a line number " *
            "ruler at the left, a column ruler on top, and a scrollbar at the right.",
        ),
        _manual_figure(_manual_screen_figure()),
        _manual_keys([
            ":toggle_ruler" => "Toggle the line number ruler.",
            ":toggle_column_ruler" => "Toggle the column ruler.",
            ":toggle_scrollbar" => "Toggle the scrollbar.",
            ":show_position" => "Report the visible lines and columns.",
        ]),
        _manual_heading("The status line"),
        _manual_paragraph("From the left to the right, the status line shows:"),
        _manual_list([
            "The prompt `❯` in the normal mode, or the name of the current mode: " *
            "`SEARCH`, `VISUAL`, `FREEZE`, `TITLES`, or `COLUMN`.",
            "The details of the mode, like `match 2/5`, `no match`, the range of a " *
            "search in columns as `@12:20`, or the number of selected lines.",
            "The active filter, as `FILTER`, its pattern, and the visible lines over the " *
            "total.",
            "The state of the view: `frozen 2×1` for two frozen rows and one frozen " *
            "column, `titles 1`, and `ruler`.",
            "The key hints of the current mode, like `n:next  N:prev  Esc:clear`.",
            "`‹` and `›` when the text continues beyond the left or the right edge.",
            "The position: `All` when the whole text is visible, `Top`, `Bot`, or the " *
            "percentage of the text above the bottom of the view.",
        ]),
        _manual_paragraph(
            "When the terminal is narrow, the least important parts are dropped first: " *
            "the key hints, then the state of the view, and so on. The mode and the " *
            "position are the last ones to go.",
        ),
        _manual_paragraph(
            "A message replaces the left side of the row until the next key: `✓` begins " *
            "an information, like `3 lines copied`, and `✗` begins an error, like " *
            "`Invalid regex`.",
        ),
        _manual_heading("The rulers and the scrollbar"),
        _manual_paragraph(
            "The line number ruler shows the number of each line. It ends with a foot on " *
            "the last frozen row, it marks the bookmarked lines with `•`, and it keeps " *
            "the numbers of the original lines while a filter hides some of them.",
        ),
        _manual_paragraph(
            "The column ruler takes two rows on top of the view. Its line has a tick on " *
            "every tenth column, with the number above it, and a half tick on every " *
            "fifth one. It follows the horizontal scrolling and the frozen columns, so " *
            "it always numbers the columns that are on the screen.",
        ),
        _manual_paragraph(
            "The thumb of the scrollbar shows which part of the text is visible. The " *
            "report of {:show_position} gives the exact numbers, like `Lines 41-80 of " *
            "1200 (7%) · Columns 1-96 of 132`.",
        ),
        _manual_remark(
            :tip,
            "The preference `\"status_position\"` changes the position to the top line " *
            "over the number of lines, like `L120/3456`, or to both. The preferences " *
            "`\"show_column_ruler\"` and `\"show_scrollbar\"` show those elements in " *
            "every pager. See the chapter about the preferences.",
        ),
    ]
end

"""
    _manual_screen_figure() -> Vector{Pair{String, String}}

Return the lines of the figure of the extended help that shows the elements of the screen,
each one with its label: a view with nine lines of a table, of which the first one is
frozen, scrolled to the seventh line, with both rulers and the scrollbar.
"""
function _manual_screen_figure()
    # The line number ruler has four columns, the text has 32, and the scrollbar has one.
    text_width = 32
    numbers = " "^4 * " "^8 * "10" * " "^8 * "20" * " "^8 * "30"
    ticks = " "^4 * first("────┬────┴"^4, text_width)
    row(ruler, text, bar) = string(ruler, rpad(text, text_width), bar)
    status = "❯" * lpad("?:help  q:quit   78%", 4 + text_width)

    return Pair{String, String}[
        rpad(numbers, 4 + text_width + 1) => "column ruler",
        rpad(ticks, 4 + text_width + 1) => "",
        row(" 1 ┴", "name       value     unit", "│") => "frozen row",
        row("•7 │", "alpha      0.1986    m/s", "┃") => "bookmarked line",
        row(" 8 │", "beta       1.4142    rad", "┃") => "scrollbar",
        row(" 9 │", "gamma      2.7183    kg", "│") => "",
        status => "status line",
    ]
end

"""
    _manual_moving() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the movements.
"""
function _manual_moving()
    return ManualBlock[
        _manual_paragraph(
            "The movements follow `less` and Vi. The view never scrolls beyond the end " *
            "of the text or beyond its widest line, so the screen stays full.",
        ),
        _manual_keys([
            ":up" => "One line up.",
            ":down" => "One line down.",
            ":left" => "One column left.",
            ":right" => "One column right.",
            ":fastup" => "Five lines up.",
            ":fastdown" => "Five lines down.",
            ":fastleft" => "Ten columns left.",
            ":fastright" => "Ten columns right.",
            ":pageup" => "One page up.",
            ":pagedown" => "One page down.",
            ":halfpageup" => "Half a page up.",
            ":halfpagedown" => "Half a page down.",
            ":home" => "First line.",
            ":end" => "Last line.",
            ":bol" => "First column.",
            ":eol" => "Last column.",
        ]),
        _manual_paragraph(
            "A page is the number of rows of the view that scroll, so the frozen rows " *
            "and the rulers are not counted. The frozen rows and columns never move: " *
            "the movements scroll what is below and at the right of them.",
        ),
        _manual_heading("The mouse wheel"),
        _manual_paragraph(
            "The wheel scrolls three lines at a time. Holding {Shift} while turning it, " *
            "or using a horizontal wheel, scrolls ten columns at a time.",
        ),
        _manual_remark(
            :tip,
            "In the visual mode, the vertical movements move the visual line instead of " *
            "the view, which scrolls only when the visual line reaches its edge.",
        ),
        _manual_remark(
            :note,
            "The preference `\"pager_mode\"` set to `\"vi\"` binds {Ctrl-D} and {Ctrl-U} " *
            "to half a page down and up, like Vi does. Otherwise, {Ctrl-D} quits the " *
            "search if there is one, or the pager.",
        ),
    ]
end

"""
    _manual_positions() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the jumps and the bookmarks.
"""
function _manual_positions()
    return ManualBlock[
        _manual_heading("Going to a line"),
        _manual_paragraph(
            "{:goto_line} opens a prompt for a position, which is shown at the top of " *
            "the view. {Enter} confirms it and {Esc} cancels it.",
        ),
        _manual_definitions([
            ":120" => "Line 120.",
            ":50%" => "The middle of the text, or any other percentage of it.",
            ":+10" => "Ten lines below the current top line.",
            ":-5" => "Five lines above the current top line.",
            ":\$" => "The last page. `:end` does the same.",
        ]),
        _manual_heading("Bookmarks"),
        _manual_paragraph(
            "A bookmark is a letter that remembers a line and the first visible column. " *
            "The lowercase and the uppercase letters are different bookmarks, and they " *
            "last until the pager quits.",
        ),
        _manual_keys([
            ":set_bookmark" => "Followed by a letter, bookmark the top line, or the " *
            "visual line in the visual mode.",
            ":goto_bookmark" => "Followed by a letter, jump to its bookmark.",
        ]),
        _manual_paragraph(
            "Pressing {:goto_bookmark} twice returns to where the view was before the " *
            "last jump, which can be a bookmark, a search, or {:goto_line}. Pressing it " *
            "twice again goes back, so it also alternates between two places.",
        ),
        _manual_paragraph(
            "The bookmarked lines are marked with `•` in the line number ruler, which " *
            "{:toggle_ruler} toggles. The bookmarks remember lines of the text, so they " *
            "still point to the same lines when a filter hides the others.",
        ),
        _manual_remark(
            :tip,
            "The chapters of this manual are bookmarks. Press {:goto_bookmark} and `e` " *
            "to read about searching, and then {:goto_bookmark} twice to come back here.",
        ),
    ]
end

"""
    _manual_searching() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the search.
"""
function _manual_searching()
    return ManualBlock[
        _manual_paragraph(
            "{:search} opens the search prompt. The pattern is a regular expression, and " *
            "its matches are highlighted while you type, with the view following the " *
            "first match at or after its top. {Enter} confirms the search, and {Esc} " *
            "cancels it and restores the view and the previous search.",
        ),
        _manual_keys([
            ":next_match" => "Go to the next match.",
            ":previous_match" => "Go to the previous match.",
            ":quit_search" => "Clear the search.",
            ":search" => "Search for another pattern.",
        ]),
        _manual_list([
            "The search is case-insensitive unless the pattern has an uppercase letter: " *
            "`/error` also finds `Error`, whereas `/Error` only finds `Error`.",
            "The active match has its own color, and the status line shows its number " *
            "over the number of matches, like `SEARCH  match 2/5`.",
            "After the last match, the search wraps to the first one, and a message " *
            "tells that it did.",
            "A match outside the view scrolls it, vertically and horizontally.",
        ]),
        _manual_heading("Regular expressions and literal text"),
        _manual_paragraph(
            "The patterns use the regular expressions of Julia, which are the ones of " *
            "the PCRE library.",
        ),
        _manual_example(
            "Patterns",
            [
                "/\\d+\\.\\d+" => "a number with a decimal point",
                "/^julia>" => "lines that begin with the prompt",
                "/error|warning" => "one word or the other",
                "/a\\[1\\]" => "the text a[1]",
            ],
        ),
        _manual_paragraph(
            "{Alt-l} at the prompt toggles the literal mode, in which the pattern is " *
            "searched exactly as it is typed, so that `a[1]` finds `a[1]`. The prompt " *
            "shows `[lit]` while the mode is on, and it stays on for the next searches " *
            "of the session. A part of a regular expression can also be quoted between " *
            "`\\Q` and `\\E`.",
        ),
        _manual_remark(
            :note,
            "A pattern that is not a valid regular expression is reported as `invalid " *
            "regex` while it is typed, and it keeps the previous search if it is " *
            "confirmed.",
        ),
        _manual_heading("Editing the prompt"),
        _manual_paragraph(
            "The prompts of the search, of the filter, of the positions, and of the file " *
            "names are edited with the same keys:",
        ),
        _manual_keys([
            "←, →" => "Move the cursor.",
            "Home, Ctrl-A" => "Go to the beginning.",
            "End, Ctrl-E" => "Go to the end.",
            "Bksp, Del" => "Delete a character.",
            "Ctrl-W" => "Delete the word before the cursor.",
            "Ctrl-U" => "Clear the prompt.",
            "↑, ↓" => "Recall the previous inputs.",
            "Enter" => "Confirm.",
            "Esc, Ctrl-C" => "Cancel.",
        ]),
        _manual_paragraph(
            "{Bksp} on an empty prompt closes it. The previous patterns and file names " *
            "are remembered until Julia quits.",
        ),
        _manual_remark(
            :note,
            "A text with more than 100,000 lines is not searched while the pattern is " *
            "typed, because every key would search all of it. The search runs when " *
            "{Enter} is pressed.",
        ),
    ]
end

"""
    _manual_column_search() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the search restricted to columns.
"""
function _manual_column_search()
    return ManualBlock[
        _manual_paragraph(
            "In a table, the same value can appear in many columns. A search can be " *
            "restricted to a range of columns of the screen by writing the range before " *
            "the pattern, separated from it by a blank.",
        ),
        _manual_definitions([
            "/@12:20 0.5" => "Search `0.5` in the columns 12 to 20.",
            "/@12 0.5" => "Search from the column 12 onwards.",
            "/@:20 0.5" => "Search up to the column 20.",
        ]),
        _manual_list([
            "A match is kept if it *starts* inside the range.",
            "The columns are the printable ones, as the column ruler numbers them. The " *
            "escape sequences that color the text take no column, and a wide character " *
            "takes two.",
            "The status line shows the range before the matches, like `SEARCH  @12:20  " *
            "match 1/7`.",
            "While the range is typed, its columns get a background in the view, and " *
            "the column ruler marks them if it is shown.",
        ]),
        _manual_heading("Selecting the columns on the screen"),
        _manual_paragraph(
            "The range does not need to be counted. Typing a second `@` right after the " *
            "first one enters the column selection, whose mode is shown as `COLUMN`.",
        ),
        _manual_list(
            [
                "Press {:search} and type `@@`. A cursor marks one column.",
                "Move the cursor with {:left} and {:right} to the first column of the " *
                "range. {:fastleft} and {:fastright} move it by ten columns, and {:bol} " *
                "and {:eol} take it to the first and to the last column of the text. The " *
                "view scrolls when the cursor leaves it.",
                "Press {Enter} to fix the column.",
                "Move the cursor to the other end of the range, which is highlighted as " *
                "it grows, and press {Enter} again.",
                "The range is written in the prompt, like `@12:20`. Type the pattern " *
                "and press {Enter}.",
            ];
            numbered = true,
        ),
        _manual_list([
            "With the mouse, press on the first column, drag to the last one, and " *
            "confirm with {Enter}.",
            "{Esc} leaves the selection and returns to the prompt as it was.",
            "To change the columns of a search that is being edited, put the cursor of " *
            "the prompt right after its `@` and type `@`. The pattern is kept.",
        ]),
        _manual_remark(
            :warning,
            "Since the second `@` starts the selection, a pattern that really begins " *
            "with `@@` must be written as `\\@@`. A pasted `@@` is never taken as the " *
            "request.",
        ),
        _manual_remark(
            :tip,
            "Show the column ruler with {:toggle_column_ruler} before searching, and " *
            "freeze the header of the table, so that the columns are easy to find.",
        ),
    ]
end

"""
    _manual_filtering() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the filter.
"""
function _manual_filtering()
    return ManualBlock[
        _manual_paragraph(
            "{:filter} opens the filter prompt. The pager then shows only the lines that " *
            "match the regular expression, and the result is previewed while the " *
            "pattern is typed.",
        ),
        _manual_definitions([
            "&error" => "Show only the lines with `error`.",
            "&!debug" => "Hide the lines with `debug`.",
            "&\\!x" => "Show only the lines with the text `!x`.",
            "&" => "With an empty pattern, clear the filter.",
        ]),
        _manual_list([
            "The pattern follows the rules of the search: it is case-insensitive unless " *
            "it has an uppercase letter, and {Alt-l} toggles the literal mode.",
            "The frozen rows and the title rows are always shown, so the header of a " *
            "table stays in place.",
            "The line number ruler keeps the numbers of the original lines, and " *
            "{:goto_line} goes to those numbers. A line hidden by the filter is " *
            "reported, and the view goes to the next visible one.",
            "A search runs over the visible lines only.",
            "The bookmarks and the marks of the visual mode are kept when the filter " *
            "changes.",
            "The status line shows `FILTER`, the pattern, and the visible lines over the " *
            "total, like `FILTER error 12/340`.",
        ]),
        _manual_remark(
            :tip,
            "{:quit_search} clears the search first. Pressed again, it clears the " *
            "filter.",
        ),
    ]
end

"""
    _manual_freezing() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the frozen and the title rows.
"""
function _manual_freezing()
    return ManualBlock[
        _manual_paragraph(
            "Frozen rows stay at the top of the view while the text scrolls vertically, " *
            "and frozen columns stay at its left while it scrolls horizontally. They " *
            "are the first rows and the first columns of the text, like the header and " *
            "the labels of a table.",
        ),
        _manual_keys([
            ":change_freeze" => "Type the number of frozen rows and then of frozen " *
            "columns.",
            ":select_freeze" => "Select the frozen rows and columns on the screen.",
            ":change_title_rows" => "Type the number of title rows.",
            ":select_title_rows" => "Select the title rows on the screen.",
        ]),
        _manual_paragraph(
            "At the prompts, {Enter} with a number changes the value, {Enter} alone " *
            "keeps it, and {Esc} cancels. The status line shows the result, like `frozen " *
            "2×1`.",
        ),
        _manual_heading("Title rows"),
        _manual_paragraph(
            "A title row is a frozen row that does not scroll horizontally either. It " *
            "is meant for a line that describes the whole text, like the summary " *
            "`100×100 Matrix{Float64}:` of an array, which would make no sense scrolled. " *
            "Since " *
            "the titles are frozen rows, asking for more titles than frozen rows freezes " *
            "them as well.",
        ),
        _manual_heading("Selecting on the screen"),
        _manual_paragraph(
            "{:select_freeze} moves the view to the top-left corner of the text and " *
            "draws two guide lines. Everything above the horizontal guide and at the " *
            "left of the vertical one will be frozen.",
        ),
        _manual_keys([
            ":up" => "Move the horizontal guide up.",
            ":down" => "Move the horizontal guide down.",
            ":left" => "Move the vertical guide left.",
            ":right" => "Move the vertical guide right.",
            "Enter" => "Apply the selection.",
            ":quit_search" => "Cancel it.",
        ]),
        _manual_paragraph(
            "The fast movements move the guides by five rows or ten columns, and the " *
            "mouse puts them on the pointer. {:select_title_rows} works in the same " *
            "way with a single guide.",
        ),
        _manual_example(
            "Freezing from Julia",
            [
                "pager(table; frozen_rows = 2)" => "",
                "pager(table; frozen_rows = 2, frozen_columns = 8)" => "",
                "pager(matrix; frozen_rows = 1, title_rows = 1)" => "",
            ],
        ),
        _manual_remark(
            :note,
            "These actions need the feature `:change_freeze`, which is disabled when the " *
            "pager is called with `change_freeze = false`.",
        ),
    ]
end

"""
    _manual_visual_mode() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the visual mode.
"""
function _manual_visual_mode()
    return ManualBlock[
        _manual_paragraph(
            "The visual mode selects lines. {:toggle_visual_mode} enters it and " *
            "highlights the *visual line*, which the vertical movements move. The " *
            "selection is the visual line, the marked lines, and the range anchored at " *
            "a line, and the status line shows how many lines it has, like `VISUAL  3 " *
            "lines`.",
        ),
        _manual_keys([
            ":toggle_visual_mode" => "Enter or leave the visual mode.",
            ":select_visual_mode_line" => "Mark or unmark the visual line.",
            ":toggle_visual_anchor" => "Anchor a range at the visual line, or release it.",
            ":yank" => "Copy the selection to the clipboard.",
            ":yank_quit" => "Copy the selection and quit the pager.",
        ]),
        _manual_heading("Selecting a range"),
        _manual_list(
            [
                "Press {:toggle_visual_mode} and move the visual line to the first line.",
                "Press {:toggle_visual_anchor} to anchor the range there.",
                "Move the visual line to the last line. The range follows it, in either " *
                "direction.",
                "Press {:yank} to copy the range, or {:select_visual_mode_line} to mark " *
                "all its lines and go on selecting others.",
            ];
            numbered = true,
        ),
        _manual_list([
            "The marked lines do not need to be contiguous: mark a line, move, and mark " *
            "another one.",
            "A click moves the visual line to the clicked line, and a click on the " *
            "visual line marks it or unmarks it.",
            "The marks are cleared when the visual mode is left.",
            "Outside the visual mode, {:yank_quit} scrolls one line down.",
        ]),
        _manual_remark(
            :note,
            "The visual mode needs the feature `:visual_mode`, which is disabled when " *
            "the pager is called with `has_visual_mode = false`.",
        ),
    ]
end

"""
    _manual_copying() -> Vector{ManualBlock}

Return the chapter of the extended help that describes how the text leaves the pager.
"""
function _manual_copying()
    return ManualBlock[
        _manual_keys([
            ":yank" => "Copy the selection of the visual mode to the clipboard.",
            ":yank_all" => "Copy the whole text, from any mode.",
            ":yank_quit" => "Copy the selection and quit the pager.",
            ":save" => "Save the text, or the selection, to a file.",
            ":edit" => "Open the text, or the selection, in an editor.",
        ]),
        _manual_paragraph(
            "The text is copied without its colors, and a message tells how many lines " *
            "were copied.",
        ),
        _manual_heading("Getting the selection in Julia"),
        _manual_paragraph(
            "The lines of the last copy are also kept for Julia. " *
            "`TerminalPager.yanked()` returns them, and the keyword `return_selection` " *
            "makes `pager` return a " *
            "`PagerResult` when it quits.",
        ),
        _manual_example(
            "Using the result",
            [
                "r = pager(x; return_selection = true)" => "",
                "r.selection" => "lines of the last copy",
                "r.start_row" => "line at the top of the view",
                "r.start_column" => "first visible column",
                "r.search_pattern" => "pattern of the search",
            ],
        ),
        _manual_heading("Saving to a file"),
        _manual_paragraph(
            "{:save} asks for a path and saves the whole text, or the selection in the " *
            "visual mode.",
        ),
        _manual_list([
            "The file has no colors. A path that begins with `!`, like `!out.txt`, keeps " *
            "the escape sequences.",
            "A `~` at the beginning of the path is the home directory.",
            "An existing file is overwritten only after `y` confirms it.",
            "{↑} and {↓} recall the previous paths.",
        ]),
        _manual_heading("Opening an editor"),
        _manual_paragraph(
            "{:edit} writes the whole text, or the selection, without colors, to a " *
            "temporary file and opens it in your editor at the current line. The editor " *
            "is the one of the environment variables `JULIA_EDITOR`, `VISUAL`, or " *
            "`EDITOR`. The pager is repainted when the editor returns, and the file is " *
            "removed when the pager quits.",
        ),
    ]
end

"""
    _manual_mouse() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the mouse.
"""
function _manual_mouse()
    return ManualBlock[
        _manual_keys([
            "Wheel" => "Scroll three lines.",
            "Shift-Wheel" => "Scroll ten columns.",
            "Wheel←, Wheel→" => "Scroll ten columns.",
            "Click" => "In the visual mode, move the visual line, or mark it.",
            "Press, drag" => "Move the guides of the freeze selection, or select the " *
            "columns of a search.",
        ]),
        _manual_remark(
            :note,
            "While the pager reports the mouse, the terminal does not select text with " *
            "it. Hold {Shift}, or {Option} on some terminals, to select text as usual.",
        ),
        _manual_paragraph(
            "The preference `\"mouse\"` set to `false` disables the mouse in the pager " *
            "and gives it back to the terminal:",
        ),
        _manual_example(
            "Disabling the mouse",
            ["TerminalPager.set_preference!(\"mouse\", false)" => ""],
        ),
    ]
end

"""
    _manual_repl() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the REPL modes and the helpers.
"""
function _manual_repl()
    return ManualBlock[
        _manual_paragraph(
            "The package adds two modes to the Julia REPL. In the *pager mode*, the " *
            "output of a command is shown in the pager when it does not fit in the " *
            "terminal, and printed as usual when it does. In the *pager help mode*, " *
            "every docstring is shown in the pager.",
        ),
        _manual_keys([
            "|" => "At the beginning of the `julia>` prompt, enter the pager mode. The " *
            "prompt becomes `pager>`.",
            "?" => "At the beginning of the `pager>` prompt, enter the pager help mode. " *
            "The prompt becomes `pager?>`.",
            "Alt-|" => "Append `|> pager` to the command, without running it.",
            "Alt-h, F1" => "Show the help of the name under the cursor, and return to " *
            "the command as it was.",
            "Alt-l" => "In the `pager>` prompt, reopen the last text.",
            "Alt-Shift-l" => "In the `pager>` prompt, pick a text of the history.",
        ]),
        _manual_paragraph(
            "{Alt-h} inside the arguments of a call shows the help of the function, " *
            "which helps to complete the call.",
        ),
        _manual_heading("The history"),
        _manual_paragraph(
            "The pager uses the alternate screen of the terminal, so the text is gone " *
            "when it quits. The last texts are kept in a history, which reopens them " *
            "with the position and the search they had.",
        ),
        _manual_definitions([
            "TerminalPager.last()" => "Reopen the most recent text.",
            "TerminalPager.last(2)" => "Reopen the one before it.",
            "TerminalPager.history()" => "List the texts of the history.",
        ]),
        _manual_paragraph(
            "The preferences `\"history_size\"` and `\"history_max_bytes\"` limit the " *
            "number and the size of the texts that are kept.",
        ),
        _manual_heading("The helpers"),
        _manual_definitions([
            "@help name" => "Show the documentation of `name` in the pager.",
            "@stdout_to_pager ex" => "Run `ex` and show what it prints in the pager. It " *
            "also accepts a block, like a `for` loop.",
            "@out2pr ex" => "A shorter name for the previous one.",
        ]),
        _manual_heading("Related preferences"),
        _manual_list([
            "`\"repl_mode_display\"`: with `\"stack\"`, the default, a display pushed by " *
            "a package, like the window of a plot, still shows the values it accepts. " *
            "With `\"pager\"`, every value goes to the pager.",
            "`\"replace_help_mode\"`: makes the regular `help?>` prompt show long " *
            "answers in the pager too, from the next Julia session on.",
            "`\"copy_stdout_to_clipboard_in_repl_mode\"`: copies the output of every " *
            "command of the pager mode to the clipboard.",
        ]),
        _manual_remark(
            :tip,
            "Add `using TerminalPager` to the file `~/.julia/config/startup.jl` to have " *
            "the pager, its modes, and its shortcuts in every Julia session.",
        ),
    ]
end

"""
    _manual_calling() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the keywords and the recipes.
"""
function _manual_calling()
    return ManualBlock[
        _manual_paragraph(
            "`pager(obj; kwargs...)` accepts the following keywords. They are the same " *
            "for the macro `@stdout_to_pager`.",
        ),
        _manual_definitions([
            "auto = false" => "Open the pager only if the text does not fit in the " *
            "terminal, and print it otherwise.",
            "frozen_rows = 0" => "Number of frozen rows.",
            "frozen_columns = 0" => "Number of frozen columns.",
            "title_rows = 0" => "Number of frozen rows that are titles.",
            "show_ruler = false" => "Show the line number ruler.",
            "show_column_ruler" => "Show the column ruler. The default is the preference " *
            "with the same name.",
            "show_scrollbar" => "Show the scrollbar. The default is the preference with " *
            "the same name.",
            "return_selection = false" => "Return a `PagerResult` instead of `nothing`.",
            "change_freeze = true" => "Allow changing the frozen rows and columns.",
            "has_visual_mode = true" => "Allow the visual mode.",
            "has_help = true" => "Allow the cheat sheet and this manual.",
            "use_alternate_screen_buffer = true" => "Use the alternate screen of the " *
            "terminal, which restores the screen when the pager quits.",
        ]),
        _manual_example(
            "Calls",
            [
                "pager(df; frozen_rows = 2, show_ruler = true)" => "",
                "pager(text; auto = true)" => "",
                "@stdout_to_pager(show(big), frozen_rows = 1)" => "",
            ],
        ),
        _manual_heading("Recipes"),
        _manual_paragraph(
            "A recipe gives the default keywords for a type, so that its objects open " *
            "in the pager already configured. It is a method of " *
            "`TerminalPager.pager_options` that returns a named tuple. The keywords " *
            "passed to `pager` win over the recipe.",
        ),
        _manual_example(
            "A recipe for a table type",
            [
                "import TerminalPager: pager_options" => "",
                "" => "",
                "pager_options(::MyTable) =" => "",
                "    (; frozen_rows = 1, title_rows = 1)" => "",
            ],
        ),
        _manual_list([
            "The method `pager_options(obj, rendered::String)` also receives the text " *
            "that will be shown, so that it can measure it.",
            "The arrays have a built-in recipe that keeps their summary line on top, as " *
            "a title row.",
            "When *DataFrames.jl* is loaded, the data frames freeze their header rows " *
            "and their column of row numbers.",
            "The pager mode of the REPL applies the recipe of the value of a command.",
        ]),
    ]
end

"""
    _manual_preferences() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the preferences.
"""
function _manual_preferences()
    return ManualBlock[
        _manual_paragraph(
            "The preferences are options that persist between the Julia sessions. They " *
            "are stored by *Preferences.jl* in the file `LocalPreferences.toml` of the " *
            "active environment.",
        ),
        _manual_example(
            "Changing a preference",
            [
                "using TerminalPager" => "",
                "TerminalPager.set_preference!(\"show_scrollbar\", true)" => "",
                "TerminalPager.drop_preference!(\"show_scrollbar\")" => "",
                "TerminalPager.drop_all_preferences!()" => "",
            ],
        ),
        _manual_paragraph(
            "The first function sets a value, the second one restores a default, and " *
            "the third one restores all the defaults, including the faces and the " *
            "persisted key bindings.",
        ),
        _manual_heading("The view"),
        _manual_definitions([
            "\"show_column_ruler\" = false" => "Show the column ruler in every pager.",
            "\"show_scrollbar\" = false" => "Show the scrollbar in every pager.",
            "\"status_position\" = \"percent\"" => "Position shown at the right of the " *
            "status line: `\"percent\"`, `\"line\"` for the top line over the number of " *
            "lines, or `\"both\"`.",
            "\"mouse\" = true" => "Report the mouse to the pager.",
        ]),
        _manual_heading("The keys"),
        _manual_definitions([
            "\"pager_mode\" = \"default\"" => "With `\"vi\"`, {Ctrl-D} and {Ctrl-U} " *
            "scroll half a page. It takes effect in the next Julia session.",
        ]),
        _manual_heading("The REPL"),
        _manual_definitions([
            "\"repl_mode_display\" = \"stack\"" => "How the pager mode shows a value: " *
            "through the displays of Julia, or always in the pager with `\"pager\"`.",
            "\"replace_help_mode\" = false" => "Make the regular `help?>` prompt use the " *
            "pager. It takes effect in the next Julia session.",
            "\"copy_stdout_to_clipboard_in_repl_mode\" = false" => "Copy the output of " *
            "every command of the pager mode to the clipboard, without colors.",
            "\"history_size\" = 5" => "Number of texts kept in the history.",
            "\"history_max_bytes\" = 50_000_000" => "Size of the texts kept in the " *
            "history. The most recent text is always kept.",
        ]),
        _manual_heading("The terminal"),
        _manual_definitions([
            "\"block_alternate_screen_buffer\" = false" => "Never use the alternate " *
            "screen, for the terminals that do not support it.",
            "\"use_scroll_regions\" = true" => "Scroll by asking the terminal to shift " *
            "the rows it already shows, which is much faster on large windows and slow " *
            "connections. Disable it if the scrolling leaves garbage on the screen.",
        ]),
    ]
end

"""
    _manual_keybindings() -> Vector{ManualBlock}

Return the chapter of the extended help that describes how the keys are changed.
"""
function _manual_keybindings()
    return ManualBlock[
        _manual_paragraph(
            "Every key of the pager is a binding between a key and an *action*, like " *
            "`:quit` or `:search`. The last chapter of this manual and the cheat sheet, " *
            "{:help}, list the actions.",
        ),
        _manual_example(
            "Changing the keys",
            [
                "using TerminalPager" => "",
                "TerminalPager.set_keybinding(\"x\", :quit)" => "",
                "TerminalPager.delete_keybinding(\"q\")" => "",
                "TerminalPager.reset_keybindings()" => "",
            ],
        ),
        _manual_paragraph(
            "A change lasts for the Julia session. With the keyword `persist = true`, it " *
            "is stored as a preference and applied in every session:",
        ),
        _manual_example(
            "Keeping a change",
            [
                "TerminalPager.set_keybinding(\"x\", :quit; persist = true)" => "",
                "TerminalPager.reset_keybindings(; persist = true)" => "",
            ],
        ),
        _manual_heading("Naming a key"),
        _manual_paragraph(
            "A key is a character, like `\"x\"`, or the name of a special key between " *
            "angle brackets, like `\"<left>\"`, `\"<enter>\"`, or `\"<pagedown>\"`. The " *
            "keywords `alt`, `ctrl`, and `shift` select the modifiers.",
        ),
        _manual_example(
            "Keys with modifiers",
            [
                "TerminalPager.set_keybinding(\"<left>\", :bol; alt = true)" => "",
                "TerminalPager.set_keybinding(\"b\", :pageup; ctrl = true)" => "",
            ],
        ),
        _manual_paragraph(
            "`TerminalPager.debug_keycode()` shows how the pager decodes each key that " *
            "is pressed, with its name and its modifiers, until `q` is pressed. Use it " *
            "to find the name of a key.",
        ),
        _manual_remark(
            :note,
            "Not every combination reaches the pager. The terminal keeps some keys for " *
            "itself, and it sends others without telling which modifiers were held.",
        ),
        _manual_heading("The persisted bindings"),
        _manual_paragraph(
            "The persisted bindings are the table `[TerminalPager.keybindings]` of " *
            "`LocalPreferences.toml`. Each key is the modifiers `alt+`, `ctrl+`, and " *
            "`shift+`, in this order, and the name of the key. Each value is the name of " *
            "the action, or `\"delete\"` for a default binding that was removed.",
        ),
        _manual_example(
            "LocalPreferences.toml",
            [
                "[TerminalPager.keybindings]" => "",
                "\"alt+<left>\" = \"bol\"" => "",
                "x = \"quit\"" => "",
                "q = \"delete\"" => "",
            ],
        ),
    ]
end

"""
    _manual_faces() -> Vector{ManualBlock}

Return the chapter of the extended help that describes the faces.
"""
function _manual_faces()
    return ManualBlock[
        _manual_paragraph(
            "Every color and text attribute of the pager is a *face* of " *
            "*StyledStrings.jl*. `TerminalPager.set_face!` changes a face for the next " *
            "pager and stores it as a preference.",
        ),
        _manual_example(
            "Changing a face",
            [
                "using TerminalPager" => "",
                "TerminalPager.set_face!(\"search_match\";" => "",
                "    foreground = :black, background = :green)" => "",
                "TerminalPager.set_face!(\"status_bar\"; inverse = true)" => "",
                "TerminalPager.drop_face!(\"search_match\")" => "",
            ],
        ),
        _manual_list([
            "The keywords are the attributes of a face: `foreground`, `background`, " *
            "`weight`, `slant`, `underline`, `strikethrough`, `inverse`, and `inherit`.",
            "A color is one of the 16 colors of the terminal, like `:red` or " *
            "`:bright_black`, or a 24-bit color written as `\"#rrggbb\"`.",
            "The attributes are merged into the current face, so only what is passed " *
            "changes.",
            "`TerminalPager.drop_face!` restores the default of a face.",
        ]),
        _manual_heading("The status line and the messages"),
        _manual_definitions([
            "status_bar" => "Base of the status line. No attributes.",
            "status_hint" => "Key hints and state of the view. Bright black.",
            "mode_search" => "Name of the search mode. Bold yellow.",
            "mode_visual" => "Name of the visual mode. Bold magenta.",
            "mode_freeze" => "Name of the freeze selections. Bold cyan.",
            "mode_filter" => "Name of the filter. Bold green.",
            "message_info" => "Informative message. Green.",
            "message_error" => "Error message. Red.",
            "command_status" => "Status at the right of a prompt. Bright black.",
        ]),
        _manual_heading("The text"),
        _manual_definitions([
            "search_match" => "Search match. Black on white.",
            "search_active_match" => "Active search match. Black on yellow.",
            "search_columns" => "Columns of a search range. Bright black background.",
            "visual_line" => "Marked lines. Bright black background.",
            "visual_active_line" => "Visual line. Blue background.",
            "freeze_guide" => "Guides of the freeze selection. Bold cyan.",
            "ruler" => "Line number and column rulers. Bright black.",
            "bookmark" => "Mark of a bookmarked line. Yellow.",
            "scrollbar_track" => "Track of the scrollbar. Bright black.",
            "scrollbar_thumb" => "Thumb of the scrollbar. No attributes.",
        ]),
        _manual_heading("The help screens"),
        _manual_definitions([
            "help_title" => "Title of the cheat sheet and of this manual. Bold cyan.",
            "help_section" => "Section titles and strong text. Bold.",
            "help_description" => "Descriptions, comments, and labels. Bright black.",
            "help_key" => "Keys of the tables. Cyan.",
            "help_action" => "Action names of the cheat sheet. Bold yellow.",
            "help_chapter" => "Chapter titles of this manual. Bold cyan.",
            "help_keycap" => "Keys in the text of this manual. Black on cyan.",
            "help_code" => "Code and names in this manual. Green.",
            "help_border" => "Rules and borders of this manual. Bright black.",
            "help_tip" => "Tip boxes. Bold green.",
            "help_note" => "Note boxes. Bold blue.",
            "help_warning" => "Warning boxes. Bold yellow.",
        ]),
        _manual_remark(
            :tip,
            "The status line has no background by default. `inverse = true` in the face " *
            "`status_bar` draws it as a bar that matches light and dark themes. Custom " *
            "colors for the bar must come with `inverse = false`.",
        ),
        _manual_heading("Other places to set the faces"),
        _manual_paragraph(
            "The faces are registered with the prefix `terminalpager_`, so they can " *
            "also be set in the file `config/faces.toml` of the Julia depot, usually " *
            "`~/.julia/config/faces.toml`. The pager applies its defaults first, then " *
            "that file, and finally the faces set with `set_face!`.",
        ),
        _manual_example(
            "~/.julia/config/faces.toml",
            [
                "[terminalpager.search_active_match]" => "",
                "foreground = \"white\"" => "",
                "background = \"red\"" => "",
            ],
        ),
    ]
end

"""
    _manual_troubleshooting() -> Vector{ManualBlock}

Return the chapter of the extended help with the notes about the terminals.
"""
function _manual_troubleshooting()
    return ManualBlock[
        _manual_heading("The Alt shortcuts do nothing on macOS"),
        _manual_paragraph(
            "The shortcuts with {Alt} need the terminal to send {Esc} followed by the " *
            "key. The terminals of macOS type a special character instead, so that " *
            "{Option} and `l` type `¬`. Enable the setting that treats the Option key as " *
            "Meta: *Use Option as Meta key* in Terminal.app, or *Left Option key: Esc+* " *
            "in iTerm2.",
        ),
        _manual_heading("The mouse does not select text"),
        _manual_paragraph(
            "The pager receives the mouse. Hold {Shift}, or {Option} on some terminals, " *
            "to select text with the terminal, or disable the preference `\"mouse\"`.",
        ),
        _manual_heading("The text is gone after quitting"),
        _manual_paragraph(
            "The pager runs on the alternate screen, which the terminal discards when " *
            "the pager quits. `TerminalPager.last()` reopens the text where it was. The " *
            "pager does not use the alternate screen when it is called with " *
            "`use_alternate_screen_buffer = false`, or when the preference " *
            "`\"block_alternate_screen_buffer\"` is set.",
        ),
        _manual_heading("The screen is garbled"),
        _manual_paragraph(
            "The pager uses the escape sequences of XTerm, which most terminals " *
            "understand. If scrolling leaves wrong rows on the screen, disable the " *
            "preference `\"use_scroll_regions\"`. If the screen is wrong from the " *
            "start, set the preference `\"block_alternate_screen_buffer\"`.",
        ),
        _manual_heading("The copy fails"),
        _manual_paragraph(
            "The pager copies with the clipboard of Julia, which needs a program of the " *
            "system: `pbcopy` on macOS, `clip` on Windows, and `xclip`, `xsel`, or " *
            "`wl-copy` on Linux. The copied lines are still returned by " *
            "`TerminalPager.yanked()` when the clipboard is not available.",
        ),
        _manual_heading("The text looks different from the original"),
        _manual_paragraph(
            "The lines are cleaned before they are shown, so that every character takes " *
            "the columns the pager expects. The tabs are expanded to the next multiple " *
            "of eight columns, and the carriage returns, the other control characters, " *
            "and the escape sequences that do not set colors or text attributes are " *
            "removed. The copied and the saved text is the original one, without the " *
            "escape sequences.",
        ),
        _manual_heading("Getting more help"),
        _manual_paragraph(
            "The docstrings of the package are available in the help mode of Julia, " *
            "like `?pager` and `?TerminalPager.set_face!`, and the documentation and " *
            "the issue tracker are at `github.com/ronisbr/TerminalPager.jl`.",
        ),
    ]
end

"""
    _manual_action_reference() -> Vector{ManualBlock}

Return the chapter of the extended help that lists every action with its keys, generated
from the sections of the help screen.
"""
function _manual_action_reference()
    blocks = ManualBlock[
        _manual_paragraph(
            "Every action of the pager, with the keys bound to it, what it does, and its " *
            "name, which is what `TerminalPager.set_keybinding` receives. A section " *
            "marked with a feature is available only when the feature is enabled.",
        ),
    ]

    for section in _HELP_SECTIONS
        title = section.title
        isnothing(section.feature) || (title *= " · feature :$(section.feature)")
        push!(blocks, _manual_heading(title))

        items = Pair{String, String}[
            string(':', entry.action) =>
                string(entry.description, " `:", entry.action, "`") for
            entry in section.actions
        ]
        push!(blocks, _manual_keys(items))
    end

    return blocks
end
