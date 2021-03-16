@testset "Internals" begin
    @test ThreadingUtilities.store!(pointer(UInt[]), (), 1) == 1
    @test ThreadingUtilities.store!(pointer(UInt[]), nothing, 1) == 1
    x = zeros(UInt, 100);
    GC.@preserve x begin
        t1 = (1.0, C_NULL, 3, ThreadingUtilities.stridedpointer(x))
        @test ThreadingUtilities.store!(pointer(x), t1, 0) === mapreduce(sizeof, +, t1)
        @test ThreadingUtilities.load(pointer(x), typeof(t1), 0) === (mapreduce(sizeof, +, t1), t1)

        nt1 = (;a = 1.0)
        @test ThreadingUtilities.store!(pointer(x), nt1, 0) === sizeof(nt1)
        @test ThreadingUtilities.load(pointer(x), typeof(nt1), 0) === (sizeof(nt1), nt1)
    end
end
