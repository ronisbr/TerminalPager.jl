# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Descriptions
# ==============================================================================
#
#   Function calls to create the precompilation statements using SnoopCompiler.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function precompilation_input()
    include("../test/runtests.jl")

    # Run the pager using the most common inputs.
    rand(10, 10) |> pager
    @help(pager)
end
