# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Descriptions
# ==============================================================================
#
#   Function that generates the precompilation statements.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

using SnoopCompile

run(`rm -rf precompile_TerminalPager.jl`)

using Pkg
Pkg.build("TerminalPager")
using TerminalPager

include("input.jl")

function create_precompile_files()
    run(`bash -c "mkdir -p snoopcompile"`)

    tinf = @snoopi_deep precompilation_input()
    ttot, pcs = SnoopCompile.parcel(tinf)
    SnoopCompile.write("./snoopcompile/", pcs)

    # Remove all precompile files that are not related to StringManipulation.jl.
    run(`bash -c "find ./snoopcompile/precompile* -maxdepth 1 ! -name \"*TerminalPager*\" -type f -exec rm -f {} \\;"`)
    run(`bash -c "mv ./snoopcompile/* ./"`)
    run(`bash -c "rm -rf ./snoopcompile/"`)
end

create_precompile_files()
