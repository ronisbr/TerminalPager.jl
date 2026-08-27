## Description #############################################################################
#
# Tests for the rendering context used by the public `pager` entry points.
#
############################################################################################

struct _DisplaySizeProbe end

function Base.show(io::IO, ::MIME"text/plain", ::_DisplaySizeProbe)
    return print(io, "size=", displaysize(io), " limit=", get(io, :limit, nothing))
end

@testset "Object Rendering Context" begin
    # The object used to be rendered without the display size, so everything consulting it,
    # such as Markdown, was wrapped at the default 80 columns. The pager bypass makes the
    # entry points print the rendered text instead of opening a pager.
    old_stdout = stdout
    output = IOBuffer()
    probe_stdout = IOContext(output, :displaysize => (17, 123), :bypass_pager => true)

    try
        Base.eval(:(stdout = $probe_stdout))
        pager(_DisplaySizeProbe())
        @test String(take!(output)) == "size=(17, 123) limit=false"

        @stdout_to_pager show(stdout, MIME"text/plain"(), _DisplaySizeProbe())
        @test String(take!(output)) == "size=(17, 123) limit=false"
    finally
        Base.eval(:(stdout = $old_stdout))
    end
end
