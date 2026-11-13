module TerminalPagerDataFramesExt

using DataFrames: AbstractDataFrame
using TerminalPager: TerminalPager

"""
    TerminalPager.pager_options(df::AbstractDataFrame, rendered::String) -> NamedTuple

Freeze the header rows of the data frame `df`, rendered as `rendered`, keep its title row
fixed, and freeze the row number column.
"""
function TerminalPager.pager_options(::AbstractDataFrame, rendered::String)
    return TerminalPager._table_options(rendered)
end

end # module TerminalPagerDataFramesExt
