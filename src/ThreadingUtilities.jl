module ThreadingUtilities

using VectorizationBase:
    pause, StaticInt, StridedPointer, stridedpointer, offsets, cache_linesize, align, __vload, __vstore!, num_threads, assume, False, register_size, NativeTypes

@enum ThreadState::UInt32 begin
  TASK = 0   # 3: task available
  EXEC = 1   # 2: task executed
  WAIT = 2   # 1: waiting
  SPIN = 3   # 0: spinning
end
const TASKS = Task[]
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
  nt = min(Threads.nthreads(),(Sys.CPU_THREADS)::Int) - 1
  resize!(THREADPOOL, (THREADBUFFERSIZE ÷ sizeof(UInt)) * nt + (cache_linesize() ÷ sizeof(UInt)) - 1)
  copyto!(THREADPOOL, zero(UInt))
  THREADPOOLPTR[] = align(pointer(THREADPOOL)) - THREADBUFFERSIZE
  Threads.atomic_fence() # ensure 0-initialization
  resize!(TASKS, nt)
  foreach(initialize_task, 1:nt)
end

end # module
