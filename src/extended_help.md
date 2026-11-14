<!--
Text of the extended help of TerminalPager.jl, the manual that `H` opens inside the pager.

It is written in GitHub Flavored Markdown, so that it can be read here as well, but only
with what the renderer in `src/extended_help.jl` lays out. The blocks are separated by blank
lines, and the docstring of `_manual_lines` describes them. Three conventions matter when
editing it:

- `<kbd>Enter</kbd>` is a key, and `<kbd>:quit</kbd>` is replaced by the keys bound to the
  action `:quit` when the manual is shown.
- A table has two columns, and its header is not shown. With keys in the first column, it
  is laid out as a key table. Otherwise, the first column is written as code.
- A code fence with backticks is an example, whose title is `title="..."` on its first
  line, and a code fence with tildes is a figure. In both, two blanks and `# ` begin a
  comment.

The last chapter, with the reference of the actions, is generated from the table of the
cheat sheet in `src/help.jl`.
-->

This is the manual of the pager, and it is shown by the pager itself, so every key described
here already works: scroll with <kbd>:down</kbd> and <kbd>:up</kbd>, search with
<kbd>:search</kbd>, and leave with <kbd>:quit</kbd>. Each chapter has a letter, which is a
bookmark: press <kbd>:goto_bookmark</kbd> and the letter to jump to the chapter, and
<kbd>:goto_bookmark</kbd> twice to return to where you were.

# Getting Started

**TerminalPager.jl** shows a text that does not fit in the terminal and lets you move
through it. It is written entirely in Julia, it follows the keys of `less` and Vi, and it
adds what tables and long outputs ask for: frozen headers, searches restricted to columns,
filters, selections, and more.

The function `pager` opens it for any object. A string is shown as it is, with its colors,
and every other object is rendered like the REPL shows it, with `show` and the MIME type
`text/plain`.

```julia title="Opening the Pager"
pager(rand(100, 100))    # page a large matrix
rand(100, 100) |> pager  # the same, as a pipe
@help write              # page a docstring
@out2pr versioninfo()    # page what a command prints
```

## The First Keys

| Key | Action |
|:--|:--|
| <kbd>:down</kbd> | Scroll one line down. |
| <kbd>:up</kbd> | Scroll one line up. |
| <kbd>:pagedown</kbd> | Scroll one page down. |
| <kbd>:pageup</kbd> | Scroll one page up. |
| <kbd>:search</kbd> | Search for a pattern. |
| <kbd>:quit</kbd> | Quit the pager. |
| <kbd>:help</kbd> | Show the cheat sheet. |
| <kbd>:extended_help</kbd> | Show this manual. |

## Two Kinds of Help

<kbd>:help</kbd> opens a cheat sheet: one row per action with its keys, a short description,
and the name of the action. <kbd>:extended_help</kbd> opens this manual, which explains each
feature in detail. Both are closed with <kbd>:quit</kbd>.

Both helps are shown by the pager itself, so everything that moves and searches works in
them. The line filter and the freeze of columns do not, since a help has nothing to filter
and no leading columns, but the rows can be frozen.

> [!TIP]
> The keys of this manual are the ones bound right now. If you change a key binding, the
> manual, the cheat sheet, and the hints of the status line follow it. An action without a
> key is shown as <kbd>:</kbd> in the text and as a dash in the tables.

# The Screen

The text takes the whole terminal but its last row, which is the status line. Three optional
elements can be added around the text: a line number ruler at the left, a column ruler on
top, and a scrollbar at the right.

~~~text
            10        20        30     # column ruler
    ────┬────┴────┬────┴────┬────┴──
 1 ┴name       value     unit       │  # frozen row
•7 │alpha      0.1986    m/s        ┃  # bookmarked line
 8 │beta       1.4142    rad        ┃  # scrollbar
 9 │gamma      2.7183    kg         │
❯                ?:help  q:quit   78%  # status line
~~~

| Key | Action |
|:--|:--|
| <kbd>:toggle_ruler</kbd> | Toggle the line number ruler. |
| <kbd>:toggle_column_ruler</kbd> | Toggle the column ruler. |
| <kbd>:toggle_scrollbar</kbd> | Toggle the scrollbar. |
| <kbd>:show_position</kbd> | Report the visible lines and columns. |

## The Status Line

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

## The Rulers and the Scrollbar

The line number ruler shows the number of each line. It ends with a foot on the last frozen
row, it marks the bookmarked lines with `•`, and it keeps the numbers of the original lines
while a filter hides some of them.

The column ruler takes two rows on top of the view. Its line has a tick on every tenth
column, with the number above it, and a half tick on every fifth one. It follows the
horizontal scrolling and the frozen columns, so it always numbers the columns that are on
the screen.

The thumb of the scrollbar shows which part of the text is visible. The report of
<kbd>:show_position</kbd> gives the exact numbers, like
`Lines 41-80 of 1200 (7%) · Columns 1-96 of 132`.

> [!TIP]
> The preference `"status_position"` changes the position to the top line over the number of
> lines, like `L120/3456`, or to both. The preferences `"show_column_ruler"` and
> `"show_scrollbar"` show those elements in every pager. See the chapter about the
> preferences.

# Moving Around

The movements follow `less` and Vi. The view never scrolls beyond the end of the text or
beyond its widest line, so the screen stays full.

| Key | Action |
|:--|:--|
| <kbd>:up</kbd> | One line up. |
| <kbd>:down</kbd> | One line down. |
| <kbd>:left</kbd> | One column left. |
| <kbd>:right</kbd> | One column right. |
| <kbd>:fastup</kbd> | Five lines up. |
| <kbd>:fastdown</kbd> | Five lines down. |
| <kbd>:fastleft</kbd> | Ten columns left. |
| <kbd>:fastright</kbd> | Ten columns right. |
| <kbd>:pageup</kbd> | One page up. |
| <kbd>:pagedown</kbd> | One page down. |
| <kbd>:halfpageup</kbd> | Half a page up. |
| <kbd>:halfpagedown</kbd> | Half a page down. |
| <kbd>:home</kbd> | First line. |
| <kbd>:end</kbd> | Last line. |
| <kbd>:bol</kbd> | First column. |
| <kbd>:eol</kbd> | Last column. |

A page is the number of rows of the view that scroll, so the frozen rows and the rulers are
not counted. The frozen rows and columns never move: the movements scroll what is below and
at the right of them.

## The Mouse Wheel

The wheel scrolls three lines at a time. Holding <kbd>Shift</kbd> while turning it, or using
a horizontal wheel, scrolls ten columns at a time.

> [!TIP]
> In the visual mode, the vertical movements move the visual line instead of the view, which
> scrolls only when the visual line reaches its edge.

> [!NOTE]
> The preference `"pager_mode"` set to `"vi"` binds <kbd>Ctrl-D</kbd> and <kbd>Ctrl-U</kbd>
> to half a page down and up, like Vi does. Otherwise, <kbd>Ctrl-D</kbd> quits the search if
> there is one, or the pager.

# Jumping to a Position

## Going to a Line

<kbd>:goto_line</kbd> opens a prompt for a position, which is shown at the top of the view.
<kbd>Enter</kbd> confirms it and <kbd>Esc</kbd> cancels it.

| Input | Meaning |
|:--|:--|
| `:120` | Line 120. |
| `:50%` | The middle of the text, or any other percentage of it. |
| `:+10` | Ten lines below the current top line. |
| `:-5` | Five lines above the current top line. |
| `:$` | The last page. `:end` does the same. |

## Bookmarks

A bookmark is a letter that remembers a line and the first visible column. The lowercase and
the uppercase letters are different bookmarks, and they last until the pager quits. While
the pager waits for the letter, the status line shows `Set mark:` or `Goto mark:`.

| Key | Action |
|:--|:--|
| <kbd>:set_bookmark</kbd> | Followed by a letter, bookmark the top line, or the visual line in the visual mode. |
| <kbd>:goto_bookmark</kbd> | Followed by a letter, jump to its bookmark. |

Pressing <kbd>:goto_bookmark</kbd> twice returns to where the view was before the last jump,
which can be a bookmark, a search, or <kbd>:goto_line</kbd>. Pressing it twice again goes
back, so it also alternates between two places.

The bookmarked lines are marked with `•` in the line number ruler, which
<kbd>:toggle_ruler</kbd> toggles. The bookmarks remember lines of the text, so they still
point to the same lines when a filter hides the others.

> [!TIP]
> The chapters of this manual are bookmarks. Press <kbd>:goto_bookmark</kbd> and `e` to read
> about searching, and then <kbd>:goto_bookmark</kbd> twice to come back here.

# Searching

<kbd>:search</kbd> opens the search prompt. The pattern is a regular expression, and its
matches are highlighted while you type, with the view following the first match at or after
its top. <kbd>Enter</kbd> confirms the search, and <kbd>Esc</kbd> cancels it and restores
the view and the previous search.

| Key | Action |
|:--|:--|
| <kbd>:next_match</kbd> | Go to the next match. |
| <kbd>:previous_match</kbd> | Go to the previous match. |
| <kbd>:quit_search</kbd> | Clear the search. |
| <kbd>:search</kbd> | Search for another pattern. |

- The search is case-insensitive unless the pattern has an uppercase letter: `/error` also
  finds `Error`, whereas `/Error` only finds `Error`.
- The active match has its own color, and the status line shows its number over the number
  of matches, like `SEARCH  match 2/5`.
- After the last match, the search wraps to the first one, and a message tells that it did.
- A match outside the view scrolls it, vertically and horizontally.

## Regular Expressions and Literal Text

The patterns use the regular expressions of Julia, which are the ones of the PCRE library.

```text title="Patterns"
/\d+\.\d+       # a number with a decimal point
/^julia>        # lines that begin with the prompt
/error|warning  # one word or the other
/a\[1\]         # the text a[1]
```

<kbd>Alt-l</kbd> at the prompt toggles the literal mode, in which the pattern is searched
exactly as it is typed, so that `a[1]` finds `a[1]`. The prompt shows `[lit]` while the mode
is on, and it stays on for the next searches of the session. A part of a regular expression
can also be quoted between `\Q` and `\E`.

> [!NOTE]
> A pattern that is not a valid regular expression is reported as `invalid regex` while it
> is typed, and it keeps the previous search if it is confirmed.

## Editing the Prompt

The prompts of the search, of the filter, of the positions, and of the file names are edited
with the same keys:

| Key | Action |
|:--|:--|
| <kbd>←</kbd>, <kbd>→</kbd> | Move the cursor. |
| <kbd>Home</kbd>, <kbd>Ctrl-A</kbd> | Go to the beginning. |
| <kbd>End</kbd>, <kbd>Ctrl-E</kbd> | Go to the end. |
| <kbd>Bksp</kbd>, <kbd>Del</kbd> | Delete a character. |
| <kbd>Ctrl-W</kbd> | Delete the word before the cursor. |
| <kbd>Ctrl-U</kbd> | Clear the prompt. |
| <kbd>↑</kbd>, <kbd>↓</kbd> | Recall the previous inputs. |
| <kbd>Enter</kbd> | Confirm. |
| <kbd>Esc</kbd>, <kbd>Ctrl-C</kbd> | Cancel. |

<kbd>Bksp</kbd> on an empty prompt closes it. The previous patterns and file names are
remembered until Julia quits.

> [!NOTE]
> A text with more than 100,000 lines is not searched while the pattern is typed, because
> every key would search all of it. The search runs when <kbd>Enter</kbd> is pressed.

# Searching in Columns

In a table, the same value can appear in many columns. A search can be restricted to a range
of columns of the screen by writing the range before the pattern, separated from it by a
blank.

| Input | Meaning |
|:--|:--|
| `/@12:20 0.5` | Search `0.5` in the columns 12 to 20. |
| `/@12 0.5` | Search from the column 12 onwards. |
| `/@:20 0.5` | Search up to the column 20. |

- A match is kept if it **starts** inside the range.
- The columns are the printable ones, as the column ruler numbers them. The escape sequences
  that color the text take no column, and a wide character takes two.
- The status line shows the range before the matches, like `SEARCH  @12:20  match 1/7`.
- While the range is typed, its columns get a background in the view, and the column ruler
  marks them if it is shown.

## Selecting the Columns on the Screen

The range does not need to be counted. Typing a second `@` right after the first one enters
the column selection, whose mode is shown as `COLUMN`.

1. Press <kbd>:search</kbd> and type `@@`. A cursor marks one column.
2. Move the cursor with <kbd>:left</kbd> and <kbd>:right</kbd> to the first column of the
   range. <kbd>:fastleft</kbd> and <kbd>:fastright</kbd> move it by ten columns, and
   <kbd>:bol</kbd> and <kbd>:eol</kbd> take it to the first and to the last column of the
   text. The view scrolls when the cursor leaves it.
3. Press <kbd>Enter</kbd> to fix the column.
4. Move the cursor to the other end of the range, which is highlighted as it grows, and
   press <kbd>Enter</kbd> again.
5. The range is written in the prompt, like `@12:20`. Type the pattern and press
   <kbd>Enter</kbd>.

- With the mouse, press on the first column, drag to the last one, and confirm with
  <kbd>Enter</kbd>.
- <kbd>Esc</kbd> leaves the selection and returns to the prompt as it was.
- To change the columns of a search that is being edited, put the cursor of the prompt right
  after its `@` and type `@`. The pattern is kept.

> [!WARNING]
> Since the second `@` starts the selection, a pattern that really begins with `@@` must be
> written as `\@@`. A pasted `@@` is never taken as the request.

> [!TIP]
> Show the column ruler with <kbd>:toggle_column_ruler</kbd> before searching, and freeze
> the header of the table, so that the columns are easy to find.

# Filtering Lines

<kbd>:filter</kbd> opens the filter prompt. The pager then shows only the lines that match
the regular expression, and the result is previewed while the pattern is typed.

| Input | Meaning |
|:--|:--|
| `&error` | Show only the lines with `error`. |
| `&!debug` | Hide the lines with `debug`. |
| `&\!x` | Show only the lines with the text `!x`. |
| `&` | With an empty pattern, clear the filter. |

- The pattern follows the rules of the search: it is case-insensitive unless it has an
  uppercase letter, and <kbd>Alt-l</kbd> toggles the literal mode.
- The frozen rows and the title rows are always shown, so the header of a table stays in
  place.
- The line number ruler keeps the numbers of the original lines, and <kbd>:goto_line</kbd>
  goes to those numbers. A line hidden by the filter is reported, and the view goes to the
  next visible one.
- A search runs over the visible lines only.
- The bookmarks and the marks of the visual mode are kept when the filter changes.
- The status line shows `FILTER`, the pattern, and the visible lines over the total, like
  `FILTER error 12/340`.

> [!TIP]
> <kbd>:quit_search</kbd> clears the search first. Pressed again, it clears the filter.

> [!NOTE]
> The filter needs the feature `:filter`, which is disabled when the pager is called with
> `has_filter = false`.

# Freezing Rows and Columns

Frozen rows stay at the top of the view while the text scrolls vertically, and frozen
columns stay at its left while it scrolls horizontally. They are the first rows and the
first columns of the text, like the header and the labels of a table.

| Key | Action |
|:--|:--|
| <kbd>:change_freeze</kbd> | Type the number of frozen rows and then of frozen columns. |
| <kbd>:select_freeze</kbd> | Select the frozen rows and columns on the screen. |
| <kbd>:change_title_rows</kbd> | Type the number of title rows. |
| <kbd>:select_title_rows</kbd> | Select the title rows on the screen. |

At the prompts, <kbd>Enter</kbd> with a number changes the value, <kbd>Enter</kbd> alone
keeps it, and <kbd>Esc</kbd> cancels. The status line shows the result, like `frozen 2×1`.

## Title Rows

A title row is a frozen row that does not scroll horizontally either. It is meant for a line
that describes the whole text, like the summary `100×100 Matrix{Float64}:` of an array,
which would make no sense scrolled. Since the titles are frozen rows, asking for more titles
than frozen rows freezes them as well.

## Selecting on the Screen

<kbd>:select_freeze</kbd> moves the view to the top-left corner of the text and draws two
guide lines. Everything above the horizontal guide and at the left of the vertical one will
be frozen.

| Key | Action |
|:--|:--|
| <kbd>:up</kbd> | Move the horizontal guide up. |
| <kbd>:down</kbd> | Move the horizontal guide down. |
| <kbd>:left</kbd> | Move the vertical guide left. |
| <kbd>:right</kbd> | Move the vertical guide right. |
| <kbd>Enter</kbd> | Apply the selection. |
| <kbd>:quit_search</kbd> | Cancel it. |

The fast movements move the guides by five rows or ten columns, and the mouse puts them on
the pointer. <kbd>:select_title_rows</kbd> works in the same way with a single guide.

```julia title="Freezing From Julia"
pager(table; frozen_rows = 2)
pager(table; frozen_rows = 2, frozen_columns = 8)
pager(matrix; frozen_rows = 1, title_rows = 1)
```

> [!NOTE]
> These actions need the feature `:change_freeze`, which is disabled when the pager is
> called with `change_freeze = false`. The keywords `change_frozen_rows = false` and
> `change_frozen_columns = false` disable only the change of the rows, together with the
> title rows, or of the columns. The prompts and the selection on the screen then ask only
> for what can be changed.

# Visual Mode

The visual mode selects lines. <kbd>:toggle_visual_mode</kbd> enters it and highlights the
**visual line**, which the vertical movements move. The selection is the visual line, the
marked lines, and the range anchored at a line, and the status line shows how many lines it
has, like `VISUAL  3 lines`.

| Key | Action |
|:--|:--|
| <kbd>:toggle_visual_mode</kbd> | Enter or leave the visual mode. |
| <kbd>:select_visual_mode_line</kbd> | Mark or unmark the visual line. |
| <kbd>:toggle_visual_anchor</kbd> | Anchor a range at the visual line, or release it. |
| <kbd>:yank</kbd> | Copy the selection to the clipboard. |
| <kbd>:yank_quit</kbd> | Copy the selection and quit the pager. |

## Selecting a Range

1. Press <kbd>:toggle_visual_mode</kbd> and move the visual line to the first line.
2. Press <kbd>:toggle_visual_anchor</kbd> to anchor the range there.
3. Move the visual line to the last line. The range follows it, in either direction.
4. Press <kbd>:yank</kbd> to copy the range, or <kbd>:select_visual_mode_line</kbd> to mark
   all its lines and go on selecting others.

- The marked lines do not need to be contiguous: mark a line, move, and mark another one.
- A click moves the visual line to the clicked line, and a click on the visual line marks it
  or unmarks it.
- The marks are cleared when the visual mode is left.
- Outside the visual mode, <kbd>:yank_quit</kbd> scrolls one line down.

> [!NOTE]
> The visual mode needs the feature `:visual_mode`, which is disabled when the pager is
> called with `has_visual_mode = false`.

# Copying, Saving, and Editing

| Key | Action |
|:--|:--|
| <kbd>:yank</kbd> | Copy the selection of the visual mode to the clipboard. |
| <kbd>:yank_all</kbd> | Copy the whole text, from any mode. |
| <kbd>:yank_quit</kbd> | Copy the selection and quit the pager. |
| <kbd>:save</kbd> | Save the text, or the selection, to a file. |
| <kbd>:edit</kbd> | Open the text, or the selection, in an editor. |

The text is copied without its colors, and a message tells how many lines were copied.

## Getting the Selection in Julia

The lines of the last copy are also kept for Julia. `TerminalPager.yanked()` returns them,
and the keyword `return_selection` makes `pager` return a `PagerResult` when it quits.

```julia title="Using the Result"
r = pager(x; return_selection = true)
r.selection                            # lines of the last copy
r.start_row                            # line at the top of the view
r.start_column                         # first visible column
r.search_pattern                       # pattern of the search
```

## Saving to a File

<kbd>:save</kbd> asks for a path and saves the whole text, or the selection in the visual
mode.

- The file has no colors. A path that begins with `!`, like `!out.txt`, keeps the escape
  sequences.
- A `~` at the beginning of the path is the home directory.
- An existing file is overwritten only after `y` confirms it.
- <kbd>↑</kbd> and <kbd>↓</kbd> recall the previous paths.

## Opening an Editor

<kbd>:edit</kbd> writes the whole text, or the selection, without colors, to a temporary
file and opens it in your editor at the current line. The editor is the one of the
environment variables `JULIA_EDITOR`, `VISUAL`, or `EDITOR`. The pager is repainted when the
editor returns, and the file is removed when the pager quits.

# Using the Mouse

| Key | Action |
|:--|:--|
| <kbd>Wheel</kbd> | Scroll three lines. |
| <kbd>Shift-Wheel</kbd> | Scroll ten columns. |
| <kbd>Wheel←</kbd>, <kbd>Wheel→</kbd> | Scroll ten columns. |
| <kbd>Click</kbd> | In the visual mode, move the visual line, or mark it. |
| <kbd>Press</kbd>, <kbd>drag</kbd> | Move the guides of the freeze selection, or select the columns of a search. |

> [!NOTE]
> While the pager reports the mouse, the terminal does not select text with it. Hold
> <kbd>Shift</kbd>, or <kbd>Option</kbd> on some terminals, to select text as usual.

The preference `"mouse"` set to `false` disables the mouse in the pager and gives it back to
the terminal:

```julia title="Disabling the Mouse"
TerminalPager.set_preference!("mouse", false)
```

# The REPL Modes

The package adds two modes to the Julia REPL. In the **pager mode**, the output of a command
is shown in the pager when it does not fit in the terminal, and printed as usual when it
does. In the **pager help mode**, every docstring is shown in the pager.

| Key | Action |
|:--|:--|
| <kbd>\|</kbd> | At the beginning of the `julia>` prompt, enter the pager mode. The prompt becomes `pager>`. |
| <kbd>?</kbd> | At the beginning of the `pager>` prompt, enter the pager help mode. The prompt becomes `pager?>`. |
| <kbd>Alt-\|</kbd> | Append `\|> pager` to the command, without running it. |
| <kbd>Alt-h</kbd>, <kbd>F1</kbd> | Show the help of the name under the cursor, and return to the command as it was. |
| <kbd>Alt-l</kbd> | In the `pager>` prompt, reopen the last text. |
| <kbd>Alt-Shift-l</kbd> | In the `pager>` prompt, pick a text of the history. |

<kbd>Alt-h</kbd> inside the arguments of a call shows the help of the function, which helps
to complete the call.

## The History

The pager uses the alternate screen of the terminal, so the text is gone when it quits. The
last texts are kept in a history, which reopens them with the position and the search they
had.

| Function | Meaning |
|:--|:--|
| `TerminalPager.last()` | Reopen the most recent text. |
| `TerminalPager.last(2)` | Reopen the one before it. |
| `TerminalPager.history()` | List the texts of the history. |

The preferences `"history_size"` and `"history_max_bytes"` limit the number and the size of
the texts that are kept.

## The Helpers

| Macro | Meaning |
|:--|:--|
| `@help name` | Show the documentation of `name` in the pager. |
| `@stdout_to_pager ex` | Run `ex` and show what it prints in the pager. It also accepts a block, like a `for` loop. |
| `@out2pr ex` | A shorter name for the previous one. |

## Related Preferences

- `"repl_mode_display"`: with `"stack"`, the default, a display pushed by a package, like
  the window of a plot, still shows the values it accepts. With `"pager"`, every value goes
  to the pager.
- `"replace_help_mode"`: makes the regular `help?>` prompt show long answers in the pager
  too, from the next Julia session on.
- `"copy_stdout_to_clipboard_in_repl_mode"`: copies the output of every command of the pager
  mode to the clipboard.

> [!TIP]
> Add `using TerminalPager` to the file `~/.julia/config/startup.jl` to have the pager, its
> modes, and its shortcuts in every Julia session.

# Calling the Pager From Code

`pager(obj; kwargs...)` accepts the following keywords. They are the same for the macro
`@stdout_to_pager`.

| Keyword | Meaning |
|:--|:--|
| `auto = false` | Open the pager only if the text does not fit in the terminal, and print it otherwise. |
| `frozen_rows = 0` | Number of frozen rows. |
| `frozen_columns = 0` | Number of frozen columns. |
| `title_rows = 0` | Number of frozen rows that are titles. |
| `show_ruler = false` | Show the line number ruler. |
| `show_column_ruler` | Show the column ruler. The default is the preference with the same name. |
| `show_scrollbar` | Show the scrollbar. The default is the preference with the same name. |
| `return_selection = false` | Return a `PagerResult` instead of `nothing`. |
| `change_freeze = true` | Allow changing the frozen rows and columns and the title rows. |
| `change_frozen_rows = true` | Allow changing the frozen rows and the title rows. |
| `change_frozen_columns = true` | Allow changing the frozen columns. |
| `has_filter = true` | Allow the line filter. |
| `has_visual_mode = true` | Allow the visual mode. |
| `has_help = true` | Allow the cheat sheet and this manual. |
| `use_alternate_screen_buffer = true` | Use the alternate screen of the terminal, which restores the screen when the pager quits. |

```julia title="Calls"
pager(df; frozen_rows = 2, show_ruler = true)
pager(text; auto = true)
@stdout_to_pager(show(big), frozen_rows = 1)
```

## Recipes

A recipe gives the default keywords for a type, so that its objects open in the pager
already configured. It is a method of `TerminalPager.pager_options` that returns a named
tuple. The keywords passed to `pager` win over the recipe.

```julia title="A Recipe for a Table Type"
import TerminalPager: pager_options

pager_options(::MyTable) =
    (; frozen_rows = 1, title_rows = 1)
```

- The method `pager_options(obj, rendered::String)` also receives the text that will be
  shown, so that it can measure it.
- The arrays have a built-in recipe that keeps their summary line on top, as a title row.
- When **DataFrames.jl** is loaded, the data frames freeze their header rows and their
  column of row numbers.
- The pager mode of the REPL applies the recipe of the value of a command.

# Preferences

The preferences are options that persist between the Julia sessions. They are stored by
**Preferences.jl** in the file `LocalPreferences.toml` of the active environment.

```julia title="Changing a Preference"
using TerminalPager
TerminalPager.set_preference!("show_scrollbar", true)
TerminalPager.drop_preference!("show_scrollbar")
TerminalPager.drop_all_preferences!()
```

The first function sets a value, the second one restores a default, and the third one
restores all the defaults, including the faces and the persisted key bindings.

## The View

| Preference | Meaning |
|:--|:--|
| `"show_column_ruler" = false` | Show the column ruler in every pager. |
| `"show_scrollbar" = false` | Show the scrollbar in every pager. |
| `"status_position" = "percent"` | Position shown at the right of the status line: `"percent"`, `"line"` for the top line over the number of lines, or `"both"`. |
| `"mouse" = true` | Report the mouse to the pager. |

## The Keys

| Preference | Meaning |
|:--|:--|
| `"pager_mode" = "default"` | With `"vi"`, <kbd>Ctrl-D</kbd> and <kbd>Ctrl-U</kbd> scroll half a page. It takes effect in the next Julia session. |

## The REPL

| Preference | Meaning |
|:--|:--|
| `"repl_mode_display" = "stack"` | How the pager mode shows a value: through the displays of Julia, or always in the pager with `"pager"`. |
| `"replace_help_mode" = false` | Make the regular `help?>` prompt use the pager. It takes effect in the next Julia session. |
| `"copy_stdout_to_clipboard_in_repl_mode" = false` | Copy the output of every command of the pager mode to the clipboard, without colors. |
| `"history_size" = 5` | Number of texts kept in the history. |
| `"history_max_bytes" = 50_000_000` | Size of the texts kept in the history. The most recent text is always kept. |

## The Terminal

| Preference | Meaning |
|:--|:--|
| `"block_alternate_screen_buffer" = false` | Never use the alternate screen, for the terminals that do not support it. |
| `"use_scroll_regions" = true` | Scroll by asking the terminal to shift the rows it already shows, which is much faster on large windows and slow connections. Disable it if the scrolling leaves garbage on the screen. |

# Key Bindings

Every key of the pager is a binding between a key and an **action**, like `:quit` or
`:search`. The last chapter of this manual and the cheat sheet, <kbd>:help</kbd>, list the
actions.

```julia title="Changing the Keys"
using TerminalPager
TerminalPager.set_keybinding("x", :quit)
TerminalPager.delete_keybinding("q")
TerminalPager.reset_keybindings()
```

A change lasts for the Julia session. With the keyword `persist = true`, it is stored as a
preference and applied in every session:

```julia title="Keeping a Change"
TerminalPager.set_keybinding("x", :quit; persist = true)
TerminalPager.reset_keybindings(; persist = true)
```

## Naming a Key

A key is a character, like `"x"`, or the name of a special key between angle brackets, like
`"<left>"`, `"<enter>"`, or `"<pagedown>"`. The keywords `alt`, `ctrl`, and `shift` select
the modifiers.

```julia title="Keys With Modifiers"
TerminalPager.set_keybinding("<left>", :bol; alt = true)
TerminalPager.set_keybinding("b", :pageup; ctrl = true)
```

`TerminalPager.debug_keycode()` shows how the pager decodes each key that is pressed, with
its name and its modifiers, until `q` is pressed. Use it to find the name of a key.

> [!NOTE]
> Not every combination reaches the pager. The terminal keeps some keys for itself, and it
> sends others without telling which modifiers were held.

## The Persisted Bindings

The persisted bindings are the table `[TerminalPager.keybindings]` of
`LocalPreferences.toml`. Each key is the modifiers `alt+`, `ctrl+`, and `shift+`, in this
order, and the name of the key. Each value is the name of the action, or `"delete"` for a
default binding that was removed.

```toml title="LocalPreferences.toml"
[TerminalPager.keybindings]
"alt+<left>" = "bol"
x = "quit"
q = "delete"
```

# Faces and Colors

Every color and text attribute of the pager is a **face** of **StyledStrings.jl**.
`TerminalPager.set_face!` changes a face for the next pager and stores it as a preference.

```julia title="Changing a Face"
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

## The Status Line and the Messages

| Face | Meaning |
|:--|:--|
| `status_bar` | Base of the status line. No attributes. |
| `status_hint` | Key hints and state of the view. Bright black. |
| `mode_search` | Name of the search mode. Bold yellow. |
| `mode_visual` | Name of the visual mode. Bold magenta. |
| `mode_freeze` | Name of the freeze selections. Bold cyan. |
| `mode_filter` | Name of the filter. Bold green. |
| `message_info` | Informative message. Green. |
| `message_error` | Error message. Red. |
| `command_status` | Status at the right of a prompt. Bright black. |

## The Text

| Face | Meaning |
|:--|:--|
| `search_match` | Search match. Black on white. |
| `search_active_match` | Active search match. Black on yellow. |
| `search_columns` | Columns of a search range. Bright black background. |
| `visual_line` | Marked lines. Bright black background. |
| `visual_active_line` | Visual line. Blue background. |
| `freeze_guide` | Guides of the freeze selection. Bold cyan. |
| `ruler` | Line number and column rulers. Bright black. |
| `bookmark` | Mark of a bookmarked line. Yellow. |
| `scrollbar_track` | Track of the scrollbar. Bright black. |
| `scrollbar_thumb` | Thumb of the scrollbar. No attributes. |

## The Help Screens

| Face | Meaning |
|:--|:--|
| `help_title` | Title of the cheat sheet and of this manual. Bold yellow. |
| `help_section` | Chapter and section titles, their marks, and the bullets. Bold yellow. |
| `help_description` | Feature tags, comments, and labels. Bright black. |
| `help_key` | Keys of the tables. Bold magenta. |
| `help_action` | Action names of the cheat sheet. Cyan. |
| `help_keycap` | Keys in the text. Bold magenta on bright black. |
| `help_code` | Code and names. Cyan. |
| `help_border` | Rules and borders. Bright black. |
| `help_tip` | Label of the tip boxes. Bold green. |
| `help_note` | Label of the note boxes. Bold bright blue. |
| `help_warning` | Label of the warning boxes. Bold red. |

The keys in the text are drawn as filled key caps, like <kbd>Enter</kbd>, when the face
`help_keycap` has a background or `inverse = true`. With a face that only sets the text,
they are written between brackets, like `[Enter]`.

> [!TIP]
> The status line has no background by default. `inverse = true` in the face `status_bar`
> draws it as a bar that matches light and dark themes. Custom colors for the bar must come
> with `inverse = false`.

## Other Places to Set the Faces

The faces are registered with the prefix `terminalpager_`, so they can also be set in the
file `config/faces.toml` of the Julia depot, usually `~/.julia/config/faces.toml`. The pager
applies its defaults first, then that file, and finally the faces set with `set_face!`.

```toml title="~/.julia/config/faces.toml"
[terminalpager.search_active_match]
foreground = "white"
background = "red"
```

# Terminals and Troubleshooting

## The Alt Shortcuts Do Nothing on macOS

The shortcuts with <kbd>Alt</kbd> need the terminal to send <kbd>Esc</kbd> followed by the
key. The terminals of macOS type a special character instead, so that <kbd>Option</kbd> and
`l` type `¬`. Enable the setting that treats the Option key as Meta: **Use Option as Meta
key** in Terminal.app, or **Left Option key: Esc+** in iTerm2.

## The Mouse Does Not Select Text

The pager receives the mouse. Hold <kbd>Shift</kbd>, or <kbd>Option</kbd> on some terminals,
to select text with the terminal, or disable the preference `"mouse"`.

## The Text Is Gone After Quitting

The pager runs on the alternate screen, which the terminal discards when the pager quits.
`TerminalPager.last()` reopens the text where it was. The pager does not use the alternate
screen when it is called with `use_alternate_screen_buffer = false`, or when the preference
`"block_alternate_screen_buffer"` is set.

## The Screen Is Garbled

The pager uses the escape sequences of XTerm, which most terminals understand. If scrolling
leaves wrong rows on the screen, disable the preference `"use_scroll_regions"`. If the
screen is wrong from the start, set the preference `"block_alternate_screen_buffer"`.

## The Copy Fails

The pager copies with the clipboard of Julia, which needs a program of the system: `pbcopy`
on macOS, `clip` on Windows, and `xclip`, `xsel`, or `wl-copy` on Linux. The copied lines
are still returned by `TerminalPager.yanked()` when the clipboard is not available.

## The Text Looks Different From the Original

The lines are cleaned before they are shown, so that every character takes the columns the
pager expects. The tabs are expanded to the next multiple of eight columns, and the carriage
returns, the other control characters, and the escape sequences that do not set colors or
text attributes are removed. The copied and the saved text is the original one, without the
escape sequences.

## Getting More Help

The docstrings of the package are available in the help mode of Julia, like `?pager` and
`?TerminalPager.set_face!`, and the documentation and the issue tracker are at
`github.com/ronisbr/TerminalPager.jl`.
