@testset "Internals" begin
    @test ThreadingUtilities.store!(pointer(UInt[]), (), 1) == 1
    @test ThreadingUtilities.store!(pointer(UInt[]), nothing, 1) == 1
    x = zeros(UInt, 100);
    GC.@preserve x begin
        t = (1.0, "hello world", 3)
        ThreadingUtilities.store!(pointer(x), t, 0)
        @test ThreadingUtilities.load(pointer(x), typeof(t), 0) === (24, t)
    end
end
