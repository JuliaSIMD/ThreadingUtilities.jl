@testset "Internals" begin
    @test ThreadingUtilities.store!(pointer(UInt[]), (), 1) == 1
    @test ThreadingUtilities.store!(pointer(UInt[]), nothing, 1) == 1
    x = zeros(UInt, 100);
    GC.@preserve x begin
        t1 = (1.0, "hello world", 3, [1,2,3,4])
        ThreadingUtilities.store!(pointer(x), t1, 0)
        @test ThreadingUtilities.load(pointer(x), typeof(t1), 0) === (8+3sizeof(UInt), t1)
        
        t2 = (1.0, C_NULL, 3)
        ThreadingUtilities.store!(pointer(x), t2, 0)
        @test ThreadingUtilities.load(pointer(x), typeof(t2), 0) === (8+2sizeof(UInt), t2)                
    end
end
