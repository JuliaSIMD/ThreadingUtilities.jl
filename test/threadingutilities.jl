struct Copy{P} end
function (::Copy{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx,N) = ThreadingUtilities.load(p, P, 2*sizeof(UInt))
    N > 0 || throw("This function throws if N == 0 for testing purposes.")
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
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    ThreadingUtilities.store!(p, (py,px,N), offset)
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

function test_copy(tid, N = 100_000)
    a = rand(N);
    b = rand(N);
    c = rand(N);
    x = similar(a) .= NaN;
    y = similar(b) .= NaN;
    z = similar(c) .= NaN;
    GC.@preserve a b c x y z begin
        launch_thread_copy!(tid, x, a)
        yield()
        ThreadingUtilities.__wait(tid)
        launch_thread_copy!(tid, y, b)
        yield()
        ThreadingUtilities.__wait(tid)
        launch_thread_copy!(tid, z, c)
        yield()
        ThreadingUtilities.__wait(tid)
    end
    @test a == x
    @test b == y
    @test c == z
end

@testset "ThreadingUtilities.jl" begin
    @test all(i -> isone(unsafe_load(ThreadingUtilities.taskpointer(i))), eachindex(ThreadingUtilities.TASKS))
    @test all(eachindex(ThreadingUtilities.TASKS)) do tid
        ThreadingUtilities.load(ThreadingUtilities.taskpointer(tid), ThreadingUtilities.ThreadState) === ThreadingUtilities.WAIT
    end
    @test all(eachindex(ThreadingUtilities.TASKS)) do tid
        ThreadingUtilities._atomic_load(ThreadingUtilities.taskpointer(tid)) === reinterpret(UInt, ThreadingUtilities.WAIT)
    end
    foreach(test_copy, eachindex(ThreadingUtilities.TASKS))
    
    x = rand(UInt, 3);
    GC.@preserve x begin
        ThreadingUtilities._atomic_store!(pointer(x), zero(UInt))
        @test ThreadingUtilities._atomic_xchg!(pointer(x), ThreadingUtilities.WAIT) == ThreadingUtilities.SPIN
        @test ThreadingUtilities._atomic_umax!(pointer(x), ThreadingUtilities.STUP) == ThreadingUtilities.WAIT
        @test ThreadingUtilities.load(pointer(x), ThreadingUtilities.ThreadState) == ThreadingUtilities.STUP
    end
    for tid ∈ eachindex(ThreadingUtilities.TASKS)
        launch_thread_copy!(tid, Float64[], Float64[])
    end
    yield()
    @test all(istaskfailed, ThreadingUtilities.TASKS)
    ThreadingUtilities.reinitialize_tasks!(false)
    @test !any(istaskfailed, ThreadingUtilities.TASKS)
    # test copy on the reinitialized tasks
    foreach(test_copy, eachindex(ThreadingUtilities.TASKS))
end

