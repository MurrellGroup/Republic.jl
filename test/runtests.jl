using Republic
using Test

# Helpers
public_set(m::Module) = Set(filter(x -> Base.ispublic(m, x), names(m; all=true, imported=true)))
exported_set(m::Module) = Set(filter(x -> Base.isexported(m, x), names(m; all=true, imported=true)))

#=== Default behavior: everything becomes public ===#

module Y1
    const Z1 = 1
    export Z1
end
module X1
    using Republic
    @republic using Main.Y1
end
@testset "default: exported upstream → public (not re-exported)" begin
    @test :Z1 in public_set(X1)
    @test !Base.isexported(X1, :Z1)
    @test X1.Z1 == 1
end

module Y2
    const A = 1
    const B = 2
    export A
    public B
end
module X2
    using Republic
    @republic using Main.Y2
end
@testset "default: exported + public → all public" begin
    @test :A in public_set(X2)
    @test :B in public_set(X2)
    @test !Base.isexported(X2, :A)
    @test !Base.isexported(X2, :B)
    @test X2.A == 1
    @test X2.B == 2
end

# Multiple modules
module Y3
    const Z3 = 3
    export Z3
end
module Y4
    const Z4 = 4
    public Z4
end
module X3
    using Republic
    @republic using Main.Y3, Main.Y4
end
@testset "default: multiple modules" begin
    @test :Z3 in public_set(X3)
    @test :Z4 in public_set(X3)
    @test !Base.isexported(X3, :Z3)
    @test !Base.isexported(X3, :Z4)
    @test X3.Z3 == 3
    @test X3.Z4 == 4
end

# Colon-qualified
module Y5
    const Z5 = 5
    const Z6 = 6
    export Z5
    public Z6
end
module X4
    using Republic
    @republic using Main.Y5: Z5, Z6
end
@testset "default: colon-qualified → all public" begin
    @test :Z5 in public_set(X4)
    @test :Z6 in public_set(X4)
    @test !Base.isexported(X4, :Z5)
    @test !Base.isexported(X4, :Z6)
    @test X4.Z5 == 5
    @test X4.Z6 == 6
end

# Colon-qualified where module is NOT a binding in the current module
# (mimics `@republic using SomePackage: name` in a real package)
module _Wrapper
    module Hidden
        const H = 42
        export H
    end
end
module X4b
    using Republic
    # _Wrapper.Hidden is not a binding in X4b — only H is brought in
    @republic using Main._Wrapper.Hidden: H
end
@testset "default: colon-qualified, module not in scope" begin
    @test :H in public_set(X4b)
    @test X4b.H == 42
end

# Import dot-qualified
module Y6
    const Z7 = 7
    export Z7
end
module Y6b
    const Z8 = 8
    public Z8
end
module X5
    using Republic
    @republic import Main.Y6.Z7, Main.Y6b.Z8
end
@testset "default: import dot-qualified → all public" begin
    @test :Z7 in public_set(X5)
    @test :Z8 in public_set(X5)
    @test !Base.isexported(X5, :Z7)
    @test !Base.isexported(X5, :Z8)
    @test X5.Z7 == 7
    @test X5.Z8 == 8
end

# Block syntax
module X6
    using Republic
    @republic begin
        using Main.Y3
        using Main.Y4
    end
end
@testset "default: block syntax" begin
    @test :Z3 in public_set(X6)
    @test :Z4 in public_set(X6)
    @test !Base.isexported(X6, :Z3)
end

# Module definition
module X7
    using Republic
    @republic module Inner
        const W = 42
        export W
        const V = 99
        public V
    end
end
@testset "default: module definition → all public" begin
    @test :Inner in public_set(X7)
    @test :W in public_set(X7)
    @test :V in public_set(X7)
    @test !Base.isexported(X7, :W)
    @test !Base.isexported(X7, :V)
    @test X7.W == 42
    @test X7.V == 99
end

# as aliases
module Y_as
    const E = 1
    const P = 2
    export E
    public P
end
module X_as
    using Republic
    @republic using Main.Y_as: E as Alias_E, P as Alias_P
end
@testset "default: as aliases → all public" begin
    @test :Alias_E in public_set(X_as)
    @test :Alias_P in public_set(X_as)
    @test !Base.isexported(X_as, :Alias_E)
    @test X_as.Alias_E == 1
    @test X_as.Alias_P == 2
end

# import Module as Alias
module Y_mod_as
    const Q = 1
    export Q
end
module X_mod_as
    using Republic
    @republic import Main.Y_mod_as as YMA
end
@testset "default: import Module as Alias → public" begin
    @test :YMA in public_set(X_mod_as)
    @test !Base.isexported(X_mod_as, :YMA)
    @test X_mod_as.YMA === Y_mod_as
end

# import dot-qualified with alias
module X_dot_as
    using Republic
    @republic import Main.Y_as.E as E2, Main.Y_as.P as P2
end
@testset "default: import dot-qualified with alias → all public" begin
    @test :E2 in public_set(X_dot_as)
    @test :P2 in public_set(X_dot_as)
    @test !Base.isexported(X_dot_as, :E2)
    @test X_dot_as.E2 == 1
    @test X_dot_as.P2 == 2
end

# Macroexpand
module X_macro
    using Republic

    macro identity_macro(ex::Expr)
        ex
    end

    module InnerMacro
        const A = 1
        export A
    end

    @republic @identity_macro using .InnerMacro: A
end
@testset "default: macroexpand" begin
    @test :A in public_set(X_macro)
    @test !Base.isexported(X_macro, :A)
end

#=== reexport=true: preserves upstream visibility ===#

module XR1
    using Republic
    @republic reexport=true using Main.Y2
end
@testset "reexport=true: preserves visibility" begin
    @test :A in exported_set(XR1)
    @test :B in public_set(XR1)
    @test !Base.isexported(XR1, :B)
    @test XR1.A == 1
    @test XR1.B == 2
end

module XR2
    using Republic
    @republic reexport=true using Main.Y5: Z5, Z6
end
@testset "reexport=true: colon-qualified preserves visibility" begin
    @test :Z5 in exported_set(XR2)
    @test :Z6 in public_set(XR2)
    @test !Base.isexported(XR2, :Z6)
    @test XR2.Z5 == 5
    @test XR2.Z6 == 6
end

module XR3
    using Republic
    @republic reexport=true using Main.Y_as: E as RE, P as RP
end
@testset "reexport=true: as aliases preserve visibility" begin
    @test :RE in exported_set(XR3)
    @test :RP in public_set(XR3)
    @test !Base.isexported(XR3, :RP)
    @test XR3.RE == 1
    @test XR3.RP == 2
end

module XR4
    using Republic
    @republic reexport=true import Main.Y6.Z7, Main.Y6b.Z8
end
@testset "reexport=true: import dot-qualified preserves visibility" begin
    @test :Z7 in exported_set(XR4)
    @test :Z8 in public_set(XR4)
    @test !Base.isexported(XR4, :Z8)
end

# reexport=true with export-only module behaves like Reexport
module Y_reexport
    const R1 = 10
    const R2 = 20
    export R1, R2
end
module X_reexport
    using Republic
    @republic reexport=true using Main.Y_reexport
end
@testset "reexport=true: like Reexport for export-only modules" begin
    @test :R1 in exported_set(X_reexport)
    @test :R2 in exported_set(X_reexport)
    @test X_reexport.R1 == 10
    @test X_reexport.R2 == 20
end

# reexport=true block syntax
module XR5
    using Republic
    @republic reexport=true begin
        using Main.Y3
        using Main.Y4
    end
end
@testset "reexport=true: block syntax" begin
    @test :Z3 in exported_set(XR5)
    @test :Z4 in public_set(XR5)
    @test !Base.isexported(XR5, :Z4)
    @test XR5.Z3 == 3
    @test XR5.Z4 == 4
end

# reexport=true with bare import Module as Alias (single-element path)
module XR6
    using Republic
    @republic reexport=true import Test as T
end
@testset "reexport=true: bare import as Alias → exported" begin
    @test :T in exported_set(XR6)
end

# Double-dot relative path (..Module)
module Outer
    module Inner
        const X = 1
        export X
    end
    module Mid
        using Republic
        @republic using ...Outer.Inner: X
    end
end
@testset "double-dot relative path" begin
    @test :X in public_set(Outer.Mid)
    @test Outer.Mid.X == 1
end

# export after @republic should not error
module Y_export_after
    const A = 1
    const B = 2
    export A
    public B
end
module X_export_before
    using Republic
    export A  # declare export before @republic — @republic will skip `public` for A
    @republic using Main.Y_export_after
end
@testset "export before @republic is respected" begin
    @test :A in exported_set(X_export_before)
    @test :B in public_set(X_export_before)
    @test X_export_before.A == 1
    @test X_export_before.B == 2
end
