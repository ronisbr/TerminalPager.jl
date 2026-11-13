## Description #############################################################################
#
# Recipes: the default pager options of an object, which packages and users define for their
# types.
#
############################################################################################

"""
    pager_options(obj::Any) -> NamedTuple
    pager_options(obj::Any, rendered::String) -> NamedTuple

Return the default keywords of [`pager`](@ref) for the object `obj`, as a named tuple whose
keys are the keywords, for example `(; frozen_rows = 1, frozen_columns = 6)`. The keywords
passed to `pager` explicitly win over the ones of the recipe.

The pager calls the method with `rendered`, the text of `obj` rendered by `show` with
`MIME"text/plain"`, which falls back to the method without it. A recipe for a type is
defined by adding a method to one of them: the one with `rendered` can measure the text, for
example the width of the first column of a table, and the other depends on the object only.
Both fall back to an empty named tuple.

# Arguments

- `obj::Any`: Object shown by the pager.
- `rendered::String`: Text of `obj`, possibly with decorations and ending with a newline.

# Examples

```julia
julia> TerminalPager.pager_options(::MyTable) = (; frozen_rows = 2, title_rows = 1)
```
"""
pager_options(obj) = (;)
pager_options(obj, rendered::String) = pager_options(obj)

# An array rendered by `show` starts with a summary line, like `2×2 Matrix{Float64}:`,
# which stays on top. An empty array and a range have no summary line.
function pager_options(::AbstractArray, rendered::String)
    first_newline = findfirst('\n', rendered)
    isnothing(first_newline) && return (;)
    first_line = rendered[1:prevind(rendered, first_newline)]
    endswith(first_line, ':') || return (;)
    return (; frozen_rows = 1, title_rows = 1)
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _pager_options(obj::Any, rendered::String) -> NamedTuple

Return the recipe of `obj` for its text `rendered`, checking that it is a named tuple.

# Arguments

- `obj::Any`: Object shown by the pager.
- `rendered::String`: Text of `obj`.
"""
function _pager_options(obj, rendered::String)
    options = pager_options(obj, rendered)
    options isa NamedTuple || throw(
        ArgumentError(
            "The recipe `pager_options` of $(typeof(obj)) must return a NamedTuple; " *
                "received $(typeof(options)).",
        ),
    )

    return options
end

"""
    _merge_options(recipe::NamedTuple, kwargs::Any) -> NamedTuple

Return the keywords of `recipe` overridden by the ones in `kwargs`.

# Arguments

- `recipe::NamedTuple`: Keywords of a recipe.
- `kwargs::Any`: Keywords passed explicitly, as a named tuple or a keyword iterator.
"""
_merge_options(recipe::NamedTuple, kwargs) = merge(recipe, (; kwargs...))

"""
    _object_pager_call(obj::Any, kwargs::Any) -> Tuple{String, NamedTuple}

Return the text of `obj` rendered for the pager and the keywords of its recipe overridden by
`kwargs`.

# Arguments

- `obj::Any`: Object shown by the pager.
- `kwargs::Any`: Keywords passed explicitly.
"""
function _object_pager_call(obj, kwargs)
    rendered = _render_object(obj)
    return rendered, _merge_options(_pager_options(obj, rendered), kwargs)
end

"""
    _table_options(rendered::String) -> NamedTuple

Return the pager options of a table `rendered` with box-drawing characters, like the ones of
**PrettyTables.jl** and **DataFrames.jl**: the rows up to the first separator starting with
`─` are frozen, the rows before the header, which is the first row with a `│`, are titles,
and the columns up to the first `│` of the header are frozen. Return an empty named tuple if
the text has no header or no separator.

# Arguments

- `rendered::String`: Text of the table, possibly with decorations.
"""
function _table_options(rendered::String)
    lines = [remove_decorations(line) for line in split(rendered, '\n')]

    header = findfirst(line -> occursin('│', line), lines)
    isnothing(header) && return (;)

    separator = findnext(line -> startswith(line, '─'), lines, header + 1)
    isnothing(separator) && return (;)

    header_line = lines[header]
    bar = findfirst('│', header_line)
    frozen_columns = textwidth(header_line[1:prevind(header_line, bar)]) + 1

    return (;
        frozen_rows = separator, title_rows = header - 1, frozen_columns = frozen_columns
    )
end
