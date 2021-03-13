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

function setup_mul_svector!(p, y::Base.RefValue{SVector{N,T}}, x::Base.RefValue{SVector{N,T}}) where {N,T}
    py = Base.unsafe_convert(Ptr{SVector{N,T}}, y)
    px = Base.unsafe_convert(Ptr{SVector{N,T}}, x)
    fptr = mul_staticarray_ptr(py, px)
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    ThreadingUtilities.store!(p, (py,px), offset)
end

@inline function launch_thread_mul_svector(tid, y, x)
    ThreadingUtilities.launch(tid, y, x) do p, y, x
        setup_mul_svector!(p, y, x)
    end
end

function mul_svector_threads(a::SVector{N,T}, b::SVector{N,T}, c::SVector{N,T}) where {N,T}
    ra = Ref(a)
    rb = Ref(b)
    rc = Ref(c)
    rx = Ref{SVector{N,T}}()
    ry = Ref{SVector{N,T}}()
    rz = Ref{SVector{N,T}}()
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
end

