include("testsetup.jl")

include("test-suite-preamble.jl")

include("internals.jl")
include("threadingutilities.jl")
include("staticarrays.jl")
include("threadpool.jl")
include("warnings.jl")

include("aqua.jl") # run the Aqua.jl tests last
