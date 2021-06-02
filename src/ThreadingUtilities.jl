module ThreadingUtilities

"""
  pause()

For use in spin-and-wait loops, like spinlocks.
"""
@inline pause() = ccall(:jl_cpu_pause, Cvoid, ())

if VERSION ≥ v"1.6.0-DEV.674"
  @inline function assume(b::Bool)::Cvoid
    Base.llvmcall(("    declare void @llvm.assume(i1)\n\n    define void @entry(i8) alwaysinline {\n    top:\n        %b = trunc i8 %0 to i1\ncall void @llvm.assume(i1 %b)\nret void\n    }\n", "entry"), Cvoid, Tuple{Bool}, b)
  end
else
  @inline function assume(b::Bool)::Cvoid
    Base.llvmcall(("declare void @llvm.assume(i1)", "%b = trunc i8 %0 to i1\ncall void @llvm.assume(i1 %b)\nret void"), Cvoid, Tuple{Bool}, b)
  end
end

@enum ThreadState::UInt32 begin
  TASK = 0   # 0: task available
  WAIT = 1   # 1: waiting
  SPIN = 2   # 2: spinning
end
const TASKS = Task[]
const LINESPACING = 256 # maximum cache-line size among contemporary CPUs.
const THREADBUFFERSIZE = 512
const THREADPOOL = UInt[]
const THREADPOOLPTR =  Ref{Ptr{UInt}}(C_NULL);

include("atomics.jl")
include("threadtasks.jl")
include("utils.jl")
include("warnings.jl")

function initialize_task(tid::Int)
  _atomic_store!(taskpointer(tid), WAIT)
  t = Task(ThreadTask(taskpointer(tid)));
  t.sticky = true # create and pin
  # set to tid, we have tasks 2...nthread, from 1-based ind perspective
  ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid % Cint)
  TASKS[tid] = t
end
function reinitialize_tasks!(verbose::Bool = true)
  for (tid,t) ∈ enumerate(TASKS)
    if istaskfailed(t)
      verbose && dump(t)
      initialize_task(tid)
    end
  end
end

function __init__()
  _print_exclusivity_warning()
  nt = min(Threads.nthreads(), (Sys.CPU_THREADS)::Int) - 1
  resize!(THREADPOOL, (THREADBUFFERSIZE ÷ sizeof(UInt)) * nt + (LINESPACING ÷ sizeof(UInt)) - 1)
  copyto!(THREADPOOL, zero(UInt))
  # align to LINESPACING boundary, and then subtract THREADBUFFERSIZE to make the pointer 1-indexed
  THREADPOOLPTR[] = reinterpret(Ptr{UInt}, (reinterpret(UInt, (pointer(THREADPOOL)))+LINESPACING-1) & (-LINESPACING)) - THREADBUFFERSIZE
  resize!(TASKS, nt)
  foreach(initialize_task, 1:nt)
end

end # module
