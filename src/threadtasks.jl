struct ThreadTask
  p::Ptr{UInt}
end
Base.pointer(tt::ThreadTask) = tt.p

@inline taskpointer(tid::T) where {T} = THREADPOOLPTR[] + tid*(THREADBUFFERSIZE%T)

@inline function _call(p::Ptr{UInt})
  fptr = load(p + sizeof(UInt), Ptr{Cvoid})
  assume(fptr ≠ C_NULL)
  ccall(fptr, Cvoid, (Ptr{UInt},), p)
end
@inline function launch(f::F, tid::Integer, args::Vararg{Any,K}) where {F,K}
  p = taskpointer(tid)
  f(p, args...)
  state = _atomic_xchg!(p, TASK) # exchange must happen atomically, to prevent it from switching to `WAIT` after reading
  state == WAIT && wake_thread!(tid)
  return nothing
end

function (tt::ThreadTask)()
  p = pointer(tt)
  # max_wait = one(UInt32) << 14
  # wait_counter = max_wait
  max_back = 0x00000040
  back = max_back
  GC.@preserve THREADPOOL begin
    while true
      if _atomic_state(p) == TASK
        # if _atomic_cas_cmp!(p, TASK, EXEC)
        _call(p)
        # store!(p, SPIN)
        _atomic_store!(p, SPIN)
        # wait_counter = zero(UInt32)
        back = 0x00000001
        continue
      end
      i = back
      while i ≠ 0x00000000
        pause()
        i -= 0x00000001
      end
      # if (wait_counter += one(UInt32)) > max_wait
      # if (back += back) > max_back
      if (back += 0x00000001) > max_back
        back = 0x00000001
        _atomic_cas_cmp!(p, SPIN, WAIT) && Base.wait()
      end
    end
  end
end

# 1-based tid, pushes into task 2-nthreads()
@noinline function wake_thread!(_tid::T) where {T <: Integer}
  tid = _tid % Int
  tidp1 = tid + one(tid)
  assume(unsigned(length(Base.Workqueues)) > unsigned(tid))
  assume(unsigned(length(TASKS)) > unsigned(tidp1))
  @inbounds push!(Base.Workqueues[tidp1], TASKS[tid])
  ccall(:jl_wakeup_thread, Cvoid, (Int16,), tid % Int16)
end

@noinline function checktask(tid)
  t = TASKS[tid]
  if istaskfailed(t)
    display(t)
    dump(t)
    println()
    initialize_task(tid)
    return true
  end
  yield()
  false
end
# 1-based tid
@inline wait(tid::Integer) = wait(taskpointer(tid), tid)
@inline wait(p::Ptr{UInt}) = wait(p, (p - THREADPOOLPTR[]) ÷ (THREADBUFFERSIZE))
@inline function wait(p::Ptr{UInt}, tid)
  counter = 0x00000000
  while _atomic_state(p) == TASK
    pause()
    if ((counter += 0x00000001) > 0x00010000)
      checktask(tid) && return true
    end
  end
  false
end

