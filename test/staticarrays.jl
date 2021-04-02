using StaticArrays, ThreadingUtilities
struct MulStaticArray{P} end
function (::MulStaticArray{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx) = ThreadingUtilities.load(p, P, 2*sizeof(UInt))
    unsafe_store!(ptry, unsafe_load(ptrx) * 2.7)
    nothing
end
@generated function mul_staticarray_ptr(::A, ::B) where {A,B}
    c = MulStaticArray{Tuple{A,B}}()
    :(@cfunction($c, Cvoid, (Ptr{UInt},)))
end

function setup_mul_svector!(p, y::Base.RefValue{T}, x::Base.RefValue{T}) where {T}
    py = Base.unsafe_convert(Ptr{T}, y)
    px = Base.unsafe_convert(Ptr{T}, x)
    fptr = mul_staticarray_ptr(py, px)
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    ThreadingUtilities.store!(p, (py,px), offset)
end

@inline function launch_thread_mul_svector(tid, y, x)
    ThreadingUtilities.launch(tid, y, x) do p, y, x
        setup_mul_svector!(p, y, x)
    end
end

function mul_svector_threads(a::T, b::T, c::T) where {T}
    ra = Ref(a)
    rb = Ref(b)
    rc = Ref(c)
    rx = Ref{T}()
    ry = Ref{T}()
    rz = Ref{T}()
    GC.@preserve ra rb rc rx ry rz begin
        launch_thread_mul_svector(1, rx, ra)
        launch_thread_mul_svector(2, ry, rb)
        launch_thread_mul_svector(3, rz, rc)
        w = muladd.(2.7, a, b)
        ThreadingUtilities.wait(1)
        ThreadingUtilities.wait(2)
        ThreadingUtilities.wait(3)
    end
    rx[],ry[],rz[],w
end

@testset "SVector Test" begin
    a = @SVector rand(16);
    b = @SVector rand(16);
    c = @SVector rand(16);
    w,x,y,z = mul_svector_threads(a, b, c)
    @test iszero(@allocated mul_svector_threads(a, b, c))
    @test w == a*2.7
    @test x == b*2.7
    @test y == c*2.7
    @test z ≈ muladd(2.7, a, b)
    A = @SMatrix rand(4,5);
    B = @SMatrix rand(4,5);
    C = @SMatrix rand(4,5);

    W,X,Y,Z = mul_svector_threads(A, B, C)
    @test W == A*2.7
    @test X == B*2.7
    @test Y == C*2.7
    @test Z ≈ muladd(2.7, A, B)
end
