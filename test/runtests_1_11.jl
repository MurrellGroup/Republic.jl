# Tests requiring Julia 1.11+ (native `public` keyword)

using Republic: @republic, public_names, exported_names
using Test

# public before @republic reexport=true is respected
module Y_public_before
    const C = 3
    const D = 4
    export C, D
end
module X_public_before
    using Republic
    public C  # declare public before @republic — @republic will skip `export` for C
    @republic reexport=true using Main.Y_public_before
end
@testset "1.11: public before @republic reexport=true is respected" begin
    @test :C in public_names(X_public_before)
    @test !Base.isexported(X_public_before, :C)  # stayed public, not promoted to export
    @test :D in exported_names(X_public_before)
    @test X_public_before.C == 3
    @test X_public_before.D == 4
end

# Native `public` declarations are discoverable by Republic
module Y_native_pub
    const A = 1
    const B = 2
    const _C = 3
    export A
    public B
end
module X_native_pub
    using Republic
    @republic inherit=true using Main.Y_native_pub
end
@testset "1.11: native public keyword discoverable by @republic" begin
    @test :A in public_names(X_native_pub)
    @test :B in public_names(X_native_pub)
    @test !(:_C in public_names(X_native_pub))
    @test X_native_pub.A == 1
    @test X_native_pub.B == 2
end

# Colon-qualified with native public names
module X_native_colon
    using Republic
    @republic using Main.Y_native_pub: A, B, _C
end
@testset "1.11: colon-qualified with native public" begin
    @test :A in public_names(X_native_colon)
    @test :B in public_names(X_native_colon)
    @test !(:_C in public_names(X_native_colon))  # private → not marked
    @test X_native_colon._C == 3                    # but still imported
end

# reexport=true with native public preserves visibility
module X_native_reexport
    using Republic
    @republic reexport=true inherit=true using Main.Y_native_pub
end
@testset "1.11: reexport with native public preserves visibility" begin
    @test :A in exported_names(X_native_reexport)
    @test :B in public_names(X_native_reexport)
    @test !Base.isexported(X_native_reexport, :B)
end
