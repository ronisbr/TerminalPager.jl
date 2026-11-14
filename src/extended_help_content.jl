## Description #############################################################################
#
# Text of the extended help. The manual is written as a text with a few marks, described in
# `_manual_lines`, and it is laid out when it is opened, so that its keys follow the key
# bindings. The last chapter, with the reference of the actions, is generated from the table
# of the help screen.
#
############################################################################################

# NOTE: The manual is one string instead of code that builds its blocks. Hence, it adds one
# object to the image of the package, and nothing but the renderer must be compiled to show
# it. Notice that this is a raw string, so that the backslashes and the dollar signs of the
# examples are written as they are shown.
const _MANUAL_SOURCE = raw"""
This is the manual of the pager, and it is shown by the pager itself, so every key described
here already works: scroll with {:down} and {:up}, search with {:search}, and leave with
{:quit}. Each chapter has a letter, which is a bookmark: press {:goto_bookmark} and the
letter to jump to the chapter, and {:goto_bookmark} twice to return to where you were.

# Getting started

*TerminalPager.jl* shows a text that does not fit in the terminal and lets you move through
it. It is written entirely in Julia, it follows the keys of `less` and Vi, and it adds what
tables and long outputs ask for: frozen headers, searches restricted to columns, filters,
selections, and more.

The function `pager` opens it for any object. A string is shown as it is, with its colors,
and every other object is rendered like the REPL shows it, with `show` and the MIME type
`text/plain`.

```Opening the pager
pager(rand(100, 100))    ## page a large matrix
rand(100, 100) |> pager  ## the same, as a pipe
@help write              ## page a docstring
@out2pr versioninfo()    ## page what a command prints
```

## The first keys

+ :down  Scroll one line down.
+ :up  Scroll one line up.
+ :pagedown  Scroll one page down.
+ :pageup  Scroll one page up.
+ :search  Search for a pattern.
+ :quit  Quit the pager.
+ :help  Show the cheat sheet.
+ :extended_help  Show this manual.

## Two kinds of help

{:help} opens a cheat sheet: one row per action with its keys, a short description, and the
name of the action. {:extended_help} opens this manual, which explains each feature in
detail. Both are closed with {:quit}.

!tip The keys of this manual are the ones bound right now. If you change a key binding, the
  manual, the cheat sheet, and the hints of the status line follow it. An action without a
  key is shown as {:} in the text and as a dash in the tables.

# The screen

The text takes the whole terminal but its last row, which is the status line. Three optional
elements can be added around the text: a line number ruler at the left, a column ruler on
top, and a scrollbar at the right.

~~~
            10        20        30     ## column ruler
    ────┬────┴────┬────┴────┬────┴──
 1 ┴name       value     unit       │  ## frozen row
•7 │alpha      0.1986    m/s        ┃  ## bookmarked line
 8 │beta       1.4142    rad        ┃  ## scrollbar
 9 │gamma      2.7183    kg         │
❯                ?:help  q:quit   78%  ## status line
~~~

+ :toggle_ruler  Toggle the line number ruler.
+ :toggle_column_ruler  Toggle the column ruler.
+ :toggle_scrollbar  Toggle the scrollbar.
+ :show_position  Report the visible lines and columns.

## The status line

From the left to the right, the status line shows:

- The prompt `❯` in the normal mode, or the name of the current mode: `SEARCH`, `VISUAL`,
  `FREEZE`, `TITLES`, or `COLUMN`.
- The details of the mode, like `match 2/5`, `no match`, the range of a search in columns as
  `@12:20`, or the number of selected lines.
- The active filter, as `FILTER`, its pattern, and the visible lines over the total.
- The state of the view: `frozen 2×1` for two frozen rows and one frozen column, `titles 1`,
  and `ruler`.
- The key hints of the current mode, like `n:next  N:prev  Esc:clear`.
- `‹` and `›` when the text continues beyond the left or the right edge.
- The position: `All` when the whole text is visible, `Top`, `Bot`, or the percentage of the
  text above the bottom of the view.

When the terminal is narrow, the least important parts are dropped first: the key hints,
then the state of the view, and so on. The mode and the position are the last ones to go.

A message replaces the left side of the row until the next key: `✓` begins an information,
like `3 lines copied`, and `✗` begins an error, like `Invalid regex`.

## The rulers and the scrollbar

The line number ruler shows the number of each line. It ends with a foot on the last frozen
row, it marks the bookmarked lines with `•`, and it keeps the numbers of the original lines
while a filter hides some of them.

The column ruler takes two rows on top of the view. Its line has a tick on every tenth
column, with the number above it, and a half tick on every fifth one. It follows the
horizontal scrolling and the frozen columns, so it always numbers the columns that are on
the screen.

The thumb of the scrollbar shows which part of the text is visible. The report of
{:show_position} gives the exact numbers, like
`Lines 41-80 of 1200 (7%) · Columns 1-96 of 132`.

!tip The preference `"status_position"` changes the position to the top line over the number
  of lines, like `L120/3456`, or to both. The preferences `"show_column_ruler"` and
  `"show_scrollbar"` show those elements in every pager. See the chapter about the
  preferences.

# Moving around

The movements follow `less` and Vi. The view never scrolls beyond the end of the text or
beyond its widest line, so the screen stays full.

+ :up  One line up.
+ :down  One line down.
+ :left  One column left.
+ :right  One column right.
+ :fastup  Five lines up.
+ :fastdown  Five lines down.
+ :fastleft  Ten columns left.
+ :fastright  Ten columns right.
+ :pageup  One page up.
+ :pagedown  One page down.
+ :halfpageup  Half a page up.
+ :halfpagedown  Half a page down.
+ :home  First line.
+ :end  Last line.
+ :bol  First column.
+ :eol  Last column.

A page is the number of rows of the view that scroll, so the frozen rows and the rulers are
not counted. The frozen rows and columns never move: the movements scroll what is below and
at the right of them.

## The mouse wheel

The wheel scrolls three lines at a time. Holding {Shift} while turning it, or using a
horizontal wheel, scrolls ten columns at a time.

!tip In the visual mode, the vertical movements move the visual line instead of the view,
  which scrolls only when the visual line reaches its edge.

!note The preference `"pager_mode"` set to `"vi"` binds {Ctrl-D} and {Ctrl-U} to half a page
  down and up, like Vi does. Otherwise, {Ctrl-D} quits the search if there is one, or the
  pager.

# Jumping to a position

## Going to a line

{:goto_line} opens a prompt for a position, which is shown at the top of the view. {Enter}
confirms it and {Esc} cancels it.

: :120  Line 120.
: :50%  The middle of the text, or any other percentage of it.
: :+10  Ten lines below the current top line.
: :-5  Five lines above the current top line.
: :$  The last page. `:end` does the same.

## Bookmarks

A bookmark is a letter that remembers a line and the first visible column. The lowercase and
the uppercase letters are different bookmarks, and they last until the pager quits.

+ :set_bookmark  Followed by a letter, bookmark the top line, or the visual line in the
  visual mode.
+ :goto_bookmark  Followed by a letter, jump to its bookmark.

Pressing {:goto_bookmark} twice returns to where the view was before the last jump, which
can be a bookmark, a search, or {:goto_line}. Pressing it twice again goes back, so it also
alternates between two places.

The bookmarked lines are marked with `•` in the line number ruler, which {:toggle_ruler}
toggles. The bookmarks remember lines of the text, so they still point to the same lines
when a filter hides the others.

!tip The chapters of this manual are bookmarks. Press {:goto_bookmark} and `e` to read about
  searching, and then {:goto_bookmark} twice to come back here.

# Searching

{:search} opens the search prompt. The pattern is a regular expression, and its matches are
highlighted while you type, with the view following the first match at or after its top.
{Enter} confirms the search, and {Esc} cancels it and restores the view and the previous
search.

+ :next_match  Go to the next match.
+ :previous_match  Go to the previous match.
+ :quit_search  Clear the search.
+ :search  Search for another pattern.

- The search is case-insensitive unless the pattern has an uppercase letter: `/error` also
  finds `Error`, whereas `/Error` only finds `Error`.
- The active match has its own color, and the status line shows its number over the number
  of matches, like `SEARCH  match 2/5`.
- After the last match, the search wraps to the first one, and a message tells that it did.
- A match outside the view scrolls it, vertically and horizontally.

## Regular expressions and literal text

The patterns use the regular expressions of Julia, which are the ones of the PCRE library.

```Patterns
/\d+\.\d+       ## a number with a decimal point
/^julia>        ## lines that begin with the prompt
/error|warning  ## one word or the other
/a\[1\]         ## the text a[1]
```

{Alt-l} at the prompt toggles the literal mode, in which the pattern is searched exactly as
it is typed, so that `a[1]` finds `a[1]`. The prompt shows `[lit]` while the mode is on, and
it stays on for the next searches of the session. A part of a regular expression can also be
quoted between `\Q` and `\E`.

!note A pattern that is not a valid regular expression is reported as `invalid regex` while
  it is typed, and it keeps the previous search if it is confirmed.

## Editing the prompt

The prompts of the search, of the filter, of the positions, and of the file names are edited
with the same keys:

+ ←, →  Move the cursor.
+ Home, Ctrl-A  Go to the beginning.
+ End, Ctrl-E  Go to the end.
+ Bksp, Del  Delete a character.
+ Ctrl-W  Delete the word before the cursor.
+ Ctrl-U  Clear the prompt.
+ ↑, ↓  Recall the previous inputs.
+ Enter  Confirm.
+ Esc, Ctrl-C  Cancel.

{Bksp} on an empty prompt closes it. The previous patterns and file names are remembered
until Julia quits.

!note A text with more than 100,000 lines is not searched while the pattern is typed,
  because every key would search all of it. The search runs when {Enter} is pressed.

# Searching in columns

In a table, the same value can appear in many columns. A search can be restricted to a range
of columns of the screen by writing the range before the pattern, separated from it by a
blank.

: /@12:20 0.5  Search `0.5` in the columns 12 to 20.
: /@12 0.5  Search from the column 12 onwards.
: /@:20 0.5  Search up to the column 20.

- A match is kept if it *starts* inside the range.
- The columns are the printable ones, as the column ruler numbers them. The escape sequences
  that color the text take no column, and a wide character takes two.
- The status line shows the range before the matches, like `SEARCH  @12:20  match 1/7`.
- While the range is typed, its columns get a background in the view, and the column ruler
  marks them if it is shown.

## Selecting the columns on the screen

The range does not need to be counted. Typing a second `@` right after the first one enters
the column selection, whose mode is shown as `COLUMN`.

1. Press {:search} and type `@@`. A cursor marks one column.
2. Move the cursor with {:left} and {:right} to the first column of the range. {:fastleft}
  and {:fastright} move it by ten columns, and {:bol} and {:eol} take it to the first and to
  the last column of the text. The view scrolls when the cursor leaves it.
3. Press {Enter} to fix the column.
4. Move the cursor to the other end of the range, which is highlighted as it grows, and
  press {Enter} again.
5. The range is written in the prompt, like `@12:20`. Type the pattern and press {Enter}.

- With the mouse, press on the first column, drag to the last one, and confirm with {Enter}.
- {Esc} leaves the selection and returns to the prompt as it was.
- To change the columns of a search that is being edited, put the cursor of the prompt right
  after its `@` and type `@`. The pattern is kept.

!warning Since the second `@` starts the selection, a pattern that really begins with `@@`
  must be written as `\@@`. A pasted `@@` is never taken as the request.

!tip Show the column ruler with {:toggle_column_ruler} before searching, and freeze the
  header of the table, so that the columns are easy to find.

# Filtering lines

{:filter} opens the filter prompt. The pager then shows only the lines that match the
regular expression, and the result is previewed while the pattern is typed.

: &error  Show only the lines with `error`.
: &!debug  Hide the lines with `debug`.
: &\!x  Show only the lines with the text `!x`.
: &  With an empty pattern, clear the filter.

- The pattern follows the rules of the search: it is case-insensitive unless it has an
  uppercase letter, and {Alt-l} toggles the literal mode.
- The frozen rows and the title rows are always shown, so the header of a table stays in
  place.
- The line number ruler keeps the numbers of the original lines, and {:goto_line} goes to
  those numbers. A line hidden by the filter is reported, and the view goes to the next
  visible one.
- A search runs over the visible lines only.
- The bookmarks and the marks of the visual mode are kept when the filter changes.
- The status line shows `FILTER`, the pattern, and the visible lines over the total, like
  `FILTER error 12/340`.

!tip {:quit_search} clears the search first. Pressed again, it clears the filter.

!note The filter needs the feature `:filter`, which is disabled when the pager is called
  with `has_filter = false`.

# Freezing rows and columns

Frozen rows stay at the top of the view while the text scrolls vertically, and frozen
columns stay at its left while it scrolls horizontally. They are the first rows and the
first columns of the text, like the header and the labels of a table.

+ :change_freeze  Type the number of frozen rows and then of frozen columns.
+ :select_freeze  Select the frozen rows and columns on the screen.
+ :change_title_rows  Type the number of title rows.
+ :select_title_rows  Select the title rows on the screen.

At the prompts, {Enter} with a number changes the value, {Enter} alone keeps it, and {Esc}
cancels. The status line shows the result, like `frozen 2×1`.

## Title rows

A title row is a frozen row that does not scroll horizontally either. It is meant for a line
that describes the whole text, like the summary `100×100 Matrix{Float64}:` of an array,
which would make no sense scrolled. Since the titles are frozen rows, asking for more titles
than frozen rows freezes them as well.

## Selecting on the screen

{:select_freeze} moves the view to the top-left corner of the text and draws two guide
lines. Everything above the horizontal guide and at the left of the vertical one will be
frozen.

+ :up  Move the horizontal guide up.
+ :down  Move the horizontal guide down.
+ :left  Move the vertical guide left.
+ :right  Move the vertical guide right.
+ Enter  Apply the selection.
+ :quit_search  Cancel it.

The fast movements move the guides by five rows or ten columns, and the mouse puts them on
the pointer. {:select_title_rows} works in the same way with a single guide.

```Freezing from Julia
pager(table; frozen_rows = 2)
pager(table; frozen_rows = 2, frozen_columns = 8)
pager(matrix; frozen_rows = 1, title_rows = 1)
```

!note These actions need the feature `:change_freeze`, which is disabled when the pager is
  called with `change_freeze = false`. The keywords `change_frozen_rows = false` and
  `change_frozen_columns = false` disable only the change of the rows, together with the
  title rows, or of the columns. The prompts and the selection on the screen then ask only
  for what can be changed.

# Visual mode

The visual mode selects lines. {:toggle_visual_mode} enters it and highlights the *visual
line*, which the vertical movements move. The selection is the visual line, the marked
lines, and the range anchored at a line, and the status line shows how many lines it has,
like `VISUAL  3 lines`.

+ :toggle_visual_mode  Enter or leave the visual mode.
+ :select_visual_mode_line  Mark or unmark the visual line.
+ :toggle_visual_anchor  Anchor a range at the visual line, or release it.
+ :yank  Copy the selection to the clipboard.
+ :yank_quit  Copy the selection and quit the pager.

## Selecting a range

1. Press {:toggle_visual_mode} and move the visual line to the first line.
2. Press {:toggle_visual_anchor} to anchor the range there.
3. Move the visual line to the last line. The range follows it, in either direction.
4. Press {:yank} to copy the range, or {:select_visual_mode_line} to mark all its lines and
  go on selecting others.

- The marked lines do not need to be contiguous: mark a line, move, and mark another one.
- A click moves the visual line to the clicked line, and a click on the visual line marks it
  or unmarks it.
- The marks are cleared when the visual mode is left.
- Outside the visual mode, {:yank_quit} scrolls one line down.

!note The visual mode needs the feature `:visual_mode`, which is disabled when the pager is
  called with `has_visual_mode = false`.

# Copying, saving, and editing

+ :yank  Copy the selection of the visual mode to the clipboard.
+ :yank_all  Copy the whole text, from any mode.
+ :yank_quit  Copy the selection and quit the pager.
+ :save  Save the text, or the selection, to a file.
+ :edit  Open the text, or the selection, in an editor.

The text is copied without its colors, and a message tells how many lines were copied.

## Getting the selection in Julia

The lines of the last copy are also kept for Julia. `TerminalPager.yanked()` returns them,
and the keyword `return_selection` makes `pager` return a `PagerResult` when it quits.

```Using the result
r = pager(x; return_selection = true)
r.selection                            ## lines of the last copy
r.start_row                            ## line at the top of the view
r.start_column                         ## first visible column
r.search_pattern                       ## pattern of the search
```

## Saving to a file

{:save} asks for a path and saves the whole text, or the selection in the visual mode.

- The file has no colors. A path that begins with `!`, like `!out.txt`, keeps the escape
  sequences.
- A `~` at the beginning of the path is the home directory.
- An existing file is overwritten only after `y` confirms it.
- {↑} and {↓} recall the previous paths.

## Opening an editor

{:edit} writes the whole text, or the selection, without colors, to a temporary file and
opens it in your editor at the current line. The editor is the one of the environment
variables `JULIA_EDITOR`, `VISUAL`, or `EDITOR`. The pager is repainted when the editor
returns, and the file is removed when the pager quits.

# Using the mouse

+ Wheel  Scroll three lines.
+ Shift-Wheel  Scroll ten columns.
+ Wheel←, Wheel→  Scroll ten columns.
+ Click  In the visual mode, move the visual line, or mark it.
+ Press, drag  Move the guides of the freeze selection, or select the columns of a search.

!note While the pager reports the mouse, the terminal does not select text with it. Hold
  {Shift}, or {Option} on some terminals, to select text as usual.

The preference `"mouse"` set to `false` disables the mouse in the pager and gives it back to
the terminal:

```Disabling the mouse
TerminalPager.set_preference!("mouse", false)
```

# The REPL modes

The package adds two modes to the Julia REPL. In the *pager mode*, the output of a command
is shown in the pager when it does not fit in the terminal, and printed as usual when it
does. In the *pager help mode*, every docstring is shown in the pager.

+ |  At the beginning of the `julia>` prompt, enter the pager mode. The prompt becomes
  `pager>`.
+ ?  At the beginning of the `pager>` prompt, enter the pager help mode. The prompt becomes
  `pager?>`.
+ Alt-|  Append `|> pager` to the command, without running it.
+ Alt-h, F1  Show the help of the name under the cursor, and return to the command as it
  was.
+ Alt-l  In the `pager>` prompt, reopen the last text.
+ Alt-Shift-l  In the `pager>` prompt, pick a text of the history.

{Alt-h} inside the arguments of a call shows the help of the function, which helps to
complete the call.

## The history

The pager uses the alternate screen of the terminal, so the text is gone when it quits. The
last texts are kept in a history, which reopens them with the position and the search they
had.

: TerminalPager.last()  Reopen the most recent text.
: TerminalPager.last(2)  Reopen the one before it.
: TerminalPager.history()  List the texts of the history.

The preferences `"history_size"` and `"history_max_bytes"` limit the number and the size of
the texts that are kept.

## The helpers

: @help name  Show the documentation of `name` in the pager.
: @stdout_to_pager ex  Run `ex` and show what it prints in the pager. It also accepts a
  block, like a `for` loop.
: @out2pr ex  A shorter name for the previous one.

## Related preferences

- `"repl_mode_display"`: with `"stack"`, the default, a display pushed by a package, like
  the window of a plot, still shows the values it accepts. With `"pager"`, every value goes
  to the pager.
- `"replace_help_mode"`: makes the regular `help?>` prompt show long answers in the pager
  too, from the next Julia session on.
- `"copy_stdout_to_clipboard_in_repl_mode"`: copies the output of every command of the pager
  mode to the clipboard.

!tip Add `using TerminalPager` to the file `~/.julia/config/startup.jl` to have the pager,
  its modes, and its shortcuts in every Julia session.

# Calling the pager from code

`pager(obj; kwargs...)` accepts the following keywords. They are the same for the macro
`@stdout_to_pager`.

: auto = false  Open the pager only if the text does not fit in the terminal, and print it
  otherwise.
: frozen_rows = 0  Number of frozen rows.
: frozen_columns = 0  Number of frozen columns.
: title_rows = 0  Number of frozen rows that are titles.
: show_ruler = false  Show the line number ruler.
: show_column_ruler  Show the column ruler. The default is the preference with the same
  name.
: show_scrollbar  Show the scrollbar. The default is the preference with the same name.
: return_selection = false  Return a `PagerResult` instead of `nothing`.
: change_freeze = true  Allow changing the frozen rows and columns and the title rows.
: change_frozen_rows = true  Allow changing the frozen rows and the title rows.
: change_frozen_columns = true  Allow changing the frozen columns.
: has_filter = true  Allow the line filter.
: has_visual_mode = true  Allow the visual mode.
: has_help = true  Allow the cheat sheet and this manual.
: use_alternate_screen_buffer = true  Use the alternate screen of the terminal, which
  restores the screen when the pager quits.

```Calls
pager(df; frozen_rows = 2, show_ruler = true)
pager(text; auto = true)
@stdout_to_pager(show(big), frozen_rows = 1)
```

## Recipes

A recipe gives the default keywords for a type, so that its objects open in the pager
already configured. It is a method of `TerminalPager.pager_options` that returns a named
tuple. The keywords passed to `pager` win over the recipe.

```A recipe for a table type
import TerminalPager: pager_options

pager_options(::MyTable) =
    (; frozen_rows = 1, title_rows = 1)
```

- The method `pager_options(obj, rendered::String)` also receives the text that will be
  shown, so that it can measure it.
- The arrays have a built-in recipe that keeps their summary line on top, as a title row.
- When *DataFrames.jl* is loaded, the data frames freeze their header rows and their column
  of row numbers.
- The pager mode of the REPL applies the recipe of the value of a command.

# Preferences

The preferences are options that persist between the Julia sessions. They are stored by
*Preferences.jl* in the file `LocalPreferences.toml` of the active environment.

```Changing a preference
using TerminalPager
TerminalPager.set_preference!("show_scrollbar", true)
TerminalPager.drop_preference!("show_scrollbar")
TerminalPager.drop_all_preferences!()
```

The first function sets a value, the second one restores a default, and the third one
restores all the defaults, including the faces and the persisted key bindings.

## The view

: "show_column_ruler" = false  Show the column ruler in every pager.
: "show_scrollbar" = false  Show the scrollbar in every pager.
: "status_position" = "percent"  Position shown at the right of the status line:
  `"percent"`, `"line"` for the top line over the number of lines, or `"both"`.
: "mouse" = true  Report the mouse to the pager.

## The keys

: "pager_mode" = "default"  With `"vi"`, {Ctrl-D} and {Ctrl-U} scroll half a page. It takes
  effect in the next Julia session.

## The REPL

: "repl_mode_display" = "stack"  How the pager mode shows a value: through the displays of
  Julia, or always in the pager with `"pager"`.
: "replace_help_mode" = false  Make the regular `help?>` prompt use the pager. It takes
  effect in the next Julia session.
: "copy_stdout_to_clipboard_in_repl_mode" = false  Copy the output of every command of the
  pager mode to the clipboard, without colors.
: "history_size" = 5  Number of texts kept in the history.
: "history_max_bytes" = 50_000_000  Size of the texts kept in the history. The most recent
  text is always kept.

## The terminal

: "block_alternate_screen_buffer" = false  Never use the alternate screen, for the terminals
  that do not support it.
: "use_scroll_regions" = true  Scroll by asking the terminal to shift the rows it already
  shows, which is much faster on large windows and slow connections. Disable it if the
  scrolling leaves garbage on the screen.

# Key bindings

Every key of the pager is a binding between a key and an *action*, like `:quit` or
`:search`. The last chapter of this manual and the cheat sheet, {:help}, list the actions.

```Changing the keys
using TerminalPager
TerminalPager.set_keybinding("x", :quit)
TerminalPager.delete_keybinding("q")
TerminalPager.reset_keybindings()
```

A change lasts for the Julia session. With the keyword `persist = true`, it is stored as a
preference and applied in every session:

```Keeping a change
TerminalPager.set_keybinding("x", :quit; persist = true)
TerminalPager.reset_keybindings(; persist = true)
```

## Naming a key

A key is a character, like `"x"`, or the name of a special key between angle brackets, like
`"<left>"`, `"<enter>"`, or `"<pagedown>"`. The keywords `alt`, `ctrl`, and `shift` select
the modifiers.

```Keys with modifiers
TerminalPager.set_keybinding("<left>", :bol; alt = true)
TerminalPager.set_keybinding("b", :pageup; ctrl = true)
```

`TerminalPager.debug_keycode()` shows how the pager decodes each key that is pressed, with
its name and its modifiers, until `q` is pressed. Use it to find the name of a key.

!note Not every combination reaches the pager. The terminal keeps some keys for itself, and
  it sends others without telling which modifiers were held.

## The persisted bindings

The persisted bindings are the table `[TerminalPager.keybindings]` of
`LocalPreferences.toml`. Each key is the modifiers `alt+`, `ctrl+`, and `shift+`, in this
order, and the name of the key. Each value is the name of the action, or `"delete"` for a
default binding that was removed.

```LocalPreferences.toml
[TerminalPager.keybindings]
"alt+<left>" = "bol"
x = "quit"
q = "delete"
```

# Faces and colors

Every color and text attribute of the pager is a *face* of *StyledStrings.jl*.
`TerminalPager.set_face!` changes a face for the next pager and stores it as a preference.

```Changing a face
using TerminalPager
TerminalPager.set_face!("search_match";
    foreground = :black, background = :green)
TerminalPager.set_face!("status_bar"; inverse = true)
TerminalPager.drop_face!("search_match")
```

- The keywords are the attributes of a face: `foreground`, `background`, `weight`, `slant`,
  `underline`, `strikethrough`, `inverse`, and `inherit`.
- A color is one of the 16 colors of the terminal, like `:red` or `:bright_black`, or a
  24-bit color written as `"#rrggbb"`.
- The attributes are merged into the current face, so only what is passed changes.
- `TerminalPager.drop_face!` restores the default of a face.

## The status line and the messages

: status_bar  Base of the status line. No attributes.
: status_hint  Key hints and state of the view. Bright black.
: mode_search  Name of the search mode. Bold yellow.
: mode_visual  Name of the visual mode. Bold magenta.
: mode_freeze  Name of the freeze selections. Bold cyan.
: mode_filter  Name of the filter. Bold green.
: message_info  Informative message. Green.
: message_error  Error message. Red.
: command_status  Status at the right of a prompt. Bright black.

## The text

: search_match  Search match. Black on white.
: search_active_match  Active search match. Black on yellow.
: search_columns  Columns of a search range. Bright black background.
: visual_line  Marked lines. Bright black background.
: visual_active_line  Visual line. Blue background.
: freeze_guide  Guides of the freeze selection. Bold cyan.
: ruler  Line number and column rulers. Bright black.
: bookmark  Mark of a bookmarked line. Yellow.
: scrollbar_track  Track of the scrollbar. Bright black.
: scrollbar_thumb  Thumb of the scrollbar. No attributes.

## The help screens

: help_title  Title of the cheat sheet and of this manual. Bold yellow.
: help_section  Chapter and section titles, their marks, and the bullets. Bold yellow.
: help_description  Feature tags, comments, and labels. Bright black.
: help_key  Keys of the tables. Bold magenta.
: help_action  Action names of the cheat sheet. Cyan.
: help_keycap  Keys in the text. Bold magenta on bright black.
: help_code  Code and names. Cyan.
: help_border  Rules and borders. Bright black.
: help_tip  Label of the tip boxes. Bold green.
: help_note  Label of the note boxes. Bold bright blue.
: help_warning  Label of the warning boxes. Bold red.

The keys in the text are drawn as filled key caps, like {Enter}, when the face `help_keycap`
has a background or `inverse = true`. With a face that only sets the text, they are written
between brackets, like `[Enter]`.

!tip The status line has no background by default. `inverse = true` in the face `status_bar`
  draws it as a bar that matches light and dark themes. Custom colors for the bar must come
  with `inverse = false`.

## Other places to set the faces

The faces are registered with the prefix `terminalpager_`, so they can also be set in the
file `config/faces.toml` of the Julia depot, usually `~/.julia/config/faces.toml`. The pager
applies its defaults first, then that file, and finally the faces set with `set_face!`.

```~/.julia/config/faces.toml
[terminalpager.search_active_match]
foreground = "white"
background = "red"
```

# Terminals and troubleshooting

## The Alt shortcuts do nothing on macOS

The shortcuts with {Alt} need the terminal to send {Esc} followed by the key. The terminals
of macOS type a special character instead, so that {Option} and `l` type `¬`. Enable the
setting that treats the Option key as Meta: *Use Option as Meta key* in Terminal.app, or
*Left Option key: Esc+* in iTerm2.

## The mouse does not select text

The pager receives the mouse. Hold {Shift}, or {Option} on some terminals, to select text
with the terminal, or disable the preference `"mouse"`.

## The text is gone after quitting

The pager runs on the alternate screen, which the terminal discards when the pager quits.
`TerminalPager.last()` reopens the text where it was. The pager does not use the alternate
screen when it is called with `use_alternate_screen_buffer = false`, or when the preference
`"block_alternate_screen_buffer"` is set.

## The screen is garbled

The pager uses the escape sequences of XTerm, which most terminals understand. If scrolling
leaves wrong rows on the screen, disable the preference `"use_scroll_regions"`. If the
screen is wrong from the start, set the preference `"block_alternate_screen_buffer"`.

## The copy fails

The pager copies with the clipboard of Julia, which needs a program of the system: `pbcopy`
on macOS, `clip` on Windows, and `xclip`, `xsel`, or `wl-copy` on Linux. The copied lines
are still returned by `TerminalPager.yanked()` when the clipboard is not available.

## The text looks different from the original

The lines are cleaned before they are shown, so that every character takes the columns the
pager expects. The tabs are expanded to the next multiple of eight columns, and the carriage
returns, the other control characters, and the escape sequences that do not set colors or
text attributes are removed. The copied and the saved text is the original one, without the
escape sequences.

## Getting more help

The docstrings of the package are available in the help mode of Julia, like `?pager` and
`?TerminalPager.set_face!`, and the documentation and the issue tracker are at
`github.com/ronisbr/TerminalPager.jl`.
"""
