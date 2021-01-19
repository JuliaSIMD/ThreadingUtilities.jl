@testset "Internals" begin
    @test ThreadingUtilities.store!(pointer(UInt[]), (), 1) == 1
end
