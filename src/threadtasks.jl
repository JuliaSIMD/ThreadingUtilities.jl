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
    state = _atomic_xchg!(p, TASK)
    state == WAIT && wake_thread!(tid)
    return nothing
end

function (tt::ThreadTask)()
    p = pointer(tt)
    max_wait = one(UInt32) << 20
    wait_counter = max_wait
    GC.@preserve THREADPOOL begin
        while true
            # if _atomic_state(p) == TASK
            if _atomic_cas_cmp!(p, TASK, EXEC)
                _call(p)
              # store!(p, SPIN)
              _atomic_store!(p, SPIN)
                wait_counter = zero(UInt32)
                continue
            end
            pause()
            if (wait_counter += one(UInt32)) > max_wait
                wait_counter = zero(UInt32)
                _atomic_cas_cmp!(p, SPIN, WAIT) && Base.wait()
            end
        end
    end
end

# 1-based tid, pushes into task 2-nthreads()
# function wake_thread!(tid::T) where {T <: Unsigned}
function wake_thread!(_tid::T) where {T <: Integer}
  tid = _tid % Int
  store!(taskpointer(_tid), TASK)
  tidp1 = tid + one(tid)
  assume(unsigned(length(Base.Workqueues)) > unsigned(tid))
  assume(unsigned(length(TASKS)) > unsigned(tidp1))
  @inbounds push!(Base.Workqueues[tidp1], TASKS[tid])
  ccall(:jl_wakeup_thread, Cvoid, (Int16,), tid % Int16)
end

# 1-based tid
@inline wait(tid::Integer) = wait(taskpointer(tid))
@inline function wait(p::Ptr{UInt})
  # TASK = 0
  # EXEC = 1
  # WAIT = 2
  # SPIN = 3
  s = _atomic_umax!(p, EXEC) # s = old state, state gets set to EXEC if s == TASK or s == EXEC
  if s == TASK # thread hasn't begun yet for some reason, so we steal the work.
    _call(p)
    store!(p, SPIN)
    return
  elseif reinterpret(UInt32, s) > 0x00000001
    return
  end
  counter = 0x00000000
  while true
    pause()
    s = _atomic_state(p) == EXEC || return
    ((counter += 0x00000001) > 0x00010000) && yield()
  end
end


# function launch_thread(f::F, tid) where {F}
#     cfunc = @cfunction($mapper, Cvoid, ());

#     fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)

#     ccall(fptr, Cvoid, ())

# end
