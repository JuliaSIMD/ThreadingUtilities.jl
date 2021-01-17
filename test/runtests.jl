using ThreadingUtilities
using VectorizationBase, Aqua
using Test

struct Copy{P} end
function (::Copy{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx,N) = ThreadingUtilities._atomic_load(p, P, 1)
    @simd ivdep for n ∈ 1:N
        vstore!(ptry, vload(ptrx, (n,)), (n,))
    end
end
@generated function copy_ptr(::A, ::B) where {A,B}
    c = Copy{Tuple{A,B,Int}}()
    quote
        @cfunction($c, Cvoid, (Ptr{UInt},))
    end
end
function setup_copy!(p, y, x)
    N = length(y)
    @assert length(x) == N
    py = stridedpointer(y)
    px = stridedpointer(x)
    fptr = copy_ptr(py, px)
    offset = ThreadingUtilities._atomic_store!(p, fptr, 0)
    ThreadingUtilities._atomic_store!(p, (py,px,N), offset)
end

@inline function launch_thread_copy!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    while true
        if ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.SPIN, ThreadingUtilities.STUP)
            setup_copy!(p, y, x)
            @assert ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.STUP, ThreadingUtilities.TASK)
            return
        elseif ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.WAIT, ThreadingUtilities.STUP)
            setup_copy!(p, y, x)
            @assert ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.STUP, ThreadingUtilities.LOCK)
            ThreadingUtilities.wake_thread!(tid % UInt)
            return
        end
        ThreadingUtilities.pause()
    end        
end


@testset "ThreadingUtilities.jl" begin
    @time Aqua.test_all(ThreadingUtilities)
    
    if length(ThreadingUtilities.TASKS) > 0
        x = rand(100);
        w = rand(100);
        y = similar(x) .= NaN;
        z = similar(x) .= NaN;
        launch_thread_copy!(1, y, x)
        ThreadingUtilities.__wait(1)
        launch_thread_copy!(1, z, w)
        ThreadingUtilities.__wait(1)
        @test y == x
        @test z == w
    end
    
end
