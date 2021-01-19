using ThreadingUtilities
using Test
using VectorizationBase

import Aqua
import InteractiveUtils

include("test-suite-preamble.jl")

include("internals.jl")
include("threadingutilities.jl")
include("threadpool.jl")
include("warnings.jl")

include("aqua.jl") # run the Aqua.jl tests last
