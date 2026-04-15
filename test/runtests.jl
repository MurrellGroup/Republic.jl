using Republic: Republic, @republic, @public, public_names, exported_names
using Test

#=== @public macro ===#

module Pub1
    using Republic: @public
    const A = 1
    @public A
end
@testset "@public: single name" begin
    @test :A in public_names(Pub1)
    @test !Base.isexported(Pub1, :A)
end

module Pub2
    using Republic: @public
    const X = 1; const Y = 2; const Z = 3
    @public X, Y, Z
end
@testset "@public: tuple" begin
    @test Set([:X, :Y, :Z]) ⊆ Set(public_names(Pub2))
end

module Pub3
    using Republic: @public
    macro mymac() end
    @public @mymac
end
@testset "@public: macro name" begin
    @test Symbol("@mymac") in public_names(Pub3)
end

module Pub4
    using Republic: @public
    const A = 1
    macro mymac() end
    @public A, @mymac
end
@testset "@public: mixed tuple with macro" begin
    @test :A in public_names(Pub4)
    @test Symbol("@mymac") in public_names(Pub4)
end

#=== Discovery API ===#

module Disc1
    using Republic: @public
    const E = 1; const P = 2; const _Priv = 3
    export E
    @public P
end
@testset "exported_names / public_names" begin
    @test :E in exported_names(Disc1)
    @test :P in public_names(Disc1)
    @test !(:E in public_names(Disc1))   # non-overlapping
    @test !(:P in exported_names(Disc1))
    @test !(:_Priv in exported_names(Disc1))
    @test !(:_Priv in public_names(Disc1))
end

#=== Internal storage ===#

module Store1
    using Republic: @public
    const S = 1
    @public S
end
@testset "storage: gensym key, no user-visible binding" begin
    @test !isdefined(Store1, :PUBLIC_NAMES)
    @test isdefined(Store1, Symbol("#Republic_public_names"))
    @test :S in getfield(Store1, Symbol("#Republic_public_names"))
end

#=== Baseline behavior: marks what you bring in ===#

module Y1
    const Z1 = 1
    export Z1
end
module X1
    using Republic
    @republic using Main.Y1
end
@testset "baseline: exported upstream → public" begin
    @test :Z1 in public_names(X1)
    @test !Base.isexported(X1, :Z1)
    @test X1.Z1 == 1
end

module Y2
    using Republic: @public
    const A = 1
    const B = 2
    export A
    @public B
end
module X2_baseline
    using Republic
    @republic using Main.Y2
end
@testset "baseline: public-only names NOT imported" begin
    @test :A in public_names(X2_baseline)
    @test !(:B in public_names(X2_baseline))
end

#=== inherit=true: wildcard discovery ===#

module X2
    using Republic
    @republic inherit=true using Main.Y2
end
@testset "inherit=true: exported + public → all public" begin
    @test :A in public_names(X2)
    @test :B in public_names(X2)
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
    using Republic: @public
    const Z4 = 4
    @public Z4
end
module X3
    using Republic
    @republic inherit=true using Main.Y3, Main.Y4
end
@testset "inherit=true: multiple modules" begin
    @test :Z3 in public_names(X3)
    @test :Z4 in public_names(X3)
    @test !Base.isexported(X3, :Z3)
    @test !Base.isexported(X3, :Z4)
    @test X3.Z3 == 3
    @test X3.Z4 == 4
end

# Colon-qualified
module Y5
    using Republic: @public
    const Z5 = 5
    const Z6 = 6
    export Z5
    @public Z6
end
module X4
    using Republic
    @republic using Main.Y5: Z5, Z6
end
@testset "baseline: colon-qualified → all public" begin
    @test :Z5 in public_names(X4)
    @test :Z6 in public_names(X4)
    @test !Base.isexported(X4, :Z5)
    @test !Base.isexported(X4, :Z6)
    @test X4.Z5 == 5
    @test X4.Z6 == 6
end

# Colon-qualified where module is NOT a binding in the current module
module _Wrapper
    module Hidden
        const H = 42
        export H
    end
end
module X4b
    using Republic
    @republic using Main._Wrapper.Hidden: H
end
@testset "baseline: colon-qualified, module not in scope" begin
    @test :H in public_names(X4b)
    @test X4b.H == 42
end

# Colon-qualified: private names not publicized
module Y_priv
    using Republic: @public
    const A = 1
    const B = 2
    const _C = 3
    export A
    @public B
end
module X_priv
    using Republic
    @republic using Main.Y_priv: A, B, _C
end
@testset "colon-qualified: mirrors upstream visibility" begin
    @test :A in public_names(X_priv)
    @test :B in public_names(X_priv)
    @test !(:_C in public_names(X_priv))  # private upstream → not made public
    @test X_priv._C == 3                   # but still imported
end

# Import dot-qualified
module Y6
    const Z7 = 7
    export Z7
end
module Y6b
    using Republic: @public
    const Z8 = 8
    @public Z8
end
module X5
    using Republic
    @republic import Main.Y6.Z7, Main.Y6b.Z8
end
@testset "baseline: import dot-qualified → all public" begin
    @test :Z7 in public_names(X5)
    @test :Z8 in public_names(X5)
    @test !Base.isexported(X5, :Z7)
    @test !Base.isexported(X5, :Z8)
    @test X5.Z7 == 7
    @test X5.Z8 == 8
end

# Block syntax
module X6
    using Republic
    @republic inherit=true begin
        using Main.Y3
        using Main.Y4
    end
end
@testset "inherit=true: block syntax" begin
    @test :Z3 in public_names(X6)
    @test :Z4 in public_names(X6)
    @test !Base.isexported(X6, :Z3)
end

# Module definition (always inherits)
module X7
    using Republic
    @republic module Inner
        using Republic: @public
        const W = 42
        export W
        const V = 99
        @public V
    end
end
@testset "module definition → all public (always inherits)" begin
    @test :Inner in public_names(X7)
    @test :W in public_names(X7)
    @test :V in public_names(X7)
    @test !Base.isexported(X7, :W)
    @test !Base.isexported(X7, :V)
    @test X7.W == 42
    @test X7.V == 99
end

# as aliases
module Y_as
    using Republic: @public
    const E = 1
    const P = 2
    export E
    @public P
end
module X_as
    using Republic
    @republic using Main.Y_as: E as Alias_E, P as Alias_P
end
@testset "baseline: as aliases → all public" begin
    @test :Alias_E in public_names(X_as)
    @test :Alias_P in public_names(X_as)
    @test !Base.isexported(X_as, :Alias_E)
    @test X_as.Alias_E == 1
    @test X_as.Alias_P == 2
end

# import Module as Alias (dotted path — upstream visibility matters)
module Y_mod_as_wrap
    using Republic: @public
    module Y_mod_as
        const Q = 1
        export Q
    end
    @public Y_mod_as
end
module X_mod_as
    using Republic
    @republic import Main.Y_mod_as_wrap.Y_mod_as as YMA
end
@testset "baseline: import Module as Alias → public" begin
    @test :YMA in public_names(X_mod_as)
    @test !Base.isexported(X_mod_as, :YMA)
    @test X_mod_as.YMA === Y_mod_as_wrap.Y_mod_as
end

# import dot-qualified with alias
module X_dot_as
    using Republic
    @republic import Main.Y_as.E as E2, Main.Y_as.P as P2
end
@testset "baseline: import dot-qualified with alias → all public" begin
    @test :E2 in public_names(X_dot_as)
    @test :P2 in public_names(X_dot_as)
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
@testset "baseline: macroexpand" begin
    @test :A in public_names(X_macro)
    @test !Base.isexported(X_macro, :A)
end

#=== reexport=true: preserves upstream visibility ===#

module XR1
    using Republic
    @republic reexport=true inherit=true using Main.Y2
end
@testset "reexport=true inherit=true: preserves visibility" begin
    @test :A in exported_names(XR1)
    @test :B in public_names(XR1)
    @test !Base.isexported(XR1, :B)
    @test XR1.A == 1
    @test XR1.B == 2
end

module XR2
    using Republic
    @republic reexport=true using Main.Y5: Z5, Z6
end
@testset "reexport=true: colon-qualified preserves visibility" begin
    @test :Z5 in exported_names(XR2)
    @test :Z6 in public_names(XR2)
    @test !Base.isexported(XR2, :Z6)
    @test XR2.Z5 == 5
    @test XR2.Z6 == 6
end

module XR3
    using Republic
    @republic reexport=true using Main.Y_as: E as RE, P as RP
end
@testset "reexport=true: as aliases preserve visibility" begin
    @test :RE in exported_names(XR3)
    @test :RP in public_names(XR3)
    @test !Base.isexported(XR3, :RP)
    @test XR3.RE == 1
    @test XR3.RP == 2
end

module XR4
    using Republic
    @republic reexport=true import Main.Y6.Z7, Main.Y6b.Z8
end
@testset "reexport=true: import dot-qualified preserves visibility" begin
    @test :Z7 in exported_names(XR4)
    @test :Z8 in public_names(XR4)
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
    @test :R1 in exported_names(X_reexport)
    @test :R2 in exported_names(X_reexport)
    @test X_reexport.R1 == 10
    @test X_reexport.R2 == 20
end

# reexport=true inherit=true block syntax
module XR5
    using Republic
    @republic reexport=true inherit=true begin
        using Main.Y3
        using Main.Y4
    end
end
@testset "reexport=true inherit=true: block syntax" begin
    @test :Z3 in exported_names(XR5)
    @test :Z4 in public_names(XR5)
    @test !Base.isexported(XR5, :Z4)
    @test XR5.Z3 == 3
    @test XR5.Z4 == 4
end

# reexport=true with bare import Module as Alias
module XR6
    using Republic
    @republic reexport=true import Test as T
end
@testset "reexport=true: bare import as Alias → exported" begin
    @test :T in exported_names(XR6)
end

# Using Base and Core directly
module X_base
    using Republic
    @republic using Base: Dict
end
module X_core
    using Republic
    @republic using Core: Int32
end
@testset "using Base/Core modules" begin
    @test :Dict in public_names(X_base)
    @test X_base.Dict === Base.Dict
    @test :Int32 in public_names(X_core)
    @test X_core.Int32 === Core.Int32
end

# Double-dot relative path
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
    @test :X in public_names(Outer.Mid)
    @test Outer.Mid.X == 1
end

# import semantics preserved (method extension works)
module Y_import_sem
    g() = :original
    export g
end
module X_import_sem
    using Republic
    @republic import Main.Y_import_sem: g
    g(x::Int) = :extended  # method extension — only works with import
end
@testset "import allows method extension" begin
    @test X_import_sem.g() == :original
    @test X_import_sem.g(1) == :extended
    @test Main.Y_import_sem.g(1) == :extended  # same function was extended
end

# using does NOT allow method extension (regression test)
module Y_using_no_ext
    f() = :original
    export f
end
module X_using_no_ext
    using Republic
    @republic using Main.Y_using_no_ext
end
@testset "using does not allow method extension" begin
    @test :f in public_names(X_using_no_ext)
    Core.eval(X_using_no_ext, :(f(x::Int) = :new))
    @test X_using_no_ext.f(1) == :new                # new function in X
    @test Main.Y_using_no_ext.f !== X_using_no_ext.f  # different functions
end

# using with public-only names does NOT allow method extension
module Y_using_pub_no_ext
    using Republic: @public
    g() = :original
    @public g
end
module X_using_pub_no_ext
    using Republic
    @republic inherit=true using Main.Y_using_pub_no_ext
end
@testset "using public-only names does not allow method extension" begin
    @test :g in public_names(X_using_pub_no_ext)
    @test_throws ErrorException Core.eval(X_using_pub_no_ext, :(g(x::Int) = :new))
end

# export before @republic is respected
module Y_export_after
    using Republic: @public
    const A = 1
    const B = 2
    export A
    @public B
end
module X_export_before
    using Republic
    export A  # declare export before @republic — @republic will skip `public` for A
    @republic inherit=true using Main.Y_export_after
end
@testset "export before @republic is respected" begin
    @test :A in exported_names(X_export_before)
    @test :B in public_names(X_export_before)
    @test X_export_before.A == 1
    @test X_export_before.B == 2
end

#=== Flag composability ===#

module Y_compose
    using Republic: @public
    const A = 1
    const B = 2
    export A
    @public B
end
module X_compose
    using Republic
    @republic reexport=true inherit=true using Main.Y_compose
end
@testset "reexport + inherit compose" begin
    @test :A in exported_names(X_compose)   # exported → re-exported
    @test :B in public_names(X_compose)     # public → imported + public
    @test !Base.isexported(X_compose, :B)
    @test X_compose.A == 1
    @test X_compose.B == 2
end

# reexport=true alone does NOT import public-only names
module X_reexport_only
    using Republic
    @republic reexport=true using Main.Y_compose
end
@testset "reexport alone: no public-only import" begin
    @test :A in exported_names(X_reexport_only)
    @test !(:B in public_names(X_reexport_only))
end

@testset "duplicate flag is an error" begin
    @test_throws Exception @macroexpand @republic inherit=true inherit=true using Foo
end

#=== Storage tracking by @republic ===#

module Y_track
    const T1 = 1
    export T1
end
module X_track
    using Republic
    @republic using Main.Y_track
end
@testset "storage: @republic baseline tracks in storage" begin
    @test :T1 in public_names(X_track)
    @test isdefined(X_track, Symbol("#Republic_public_names"))
end

#=== Module definition with reexport=true ===#

module X7r
    using Republic
    @republic reexport=true module Inner
        using Republic: @public
        const W = 42
        export W
        const V = 99
        @public V
    end
end
@testset "module definition reexport=true: preserves visibility" begin
    @test :Inner in exported_names(X7r) # module self-exports → re-exported
    @test :W in exported_names(X7r)    # exported → re-exported
    @test :V in public_names(X7r)      # public → stays public
    @test X7r.W == 42
    @test X7r.V == 99
end

#=== Propagation chain ===#

module Chain_A
    using Republic: @public
    const FA = 1
    export FA
    const PA = 2
    @public PA
end
module Chain_B
    using Republic
    @republic inherit=true using Main.Chain_A
end
module Chain_C
    using Republic
    @republic inherit=true using Main.Chain_B
end
@testset "propagation: A → B → C" begin
    # B gets both FA (exported) and PA (public) from A, marks all public
    @test :FA in public_names(Chain_B)
    @test :PA in public_names(Chain_B)
    @test Chain_B.FA == 1
    @test Chain_B.PA == 2
    # C inherits from B — FA and PA are public-only in B → public in C
    @test :FA in public_names(Chain_C)
    @test :PA in public_names(Chain_C)
    @test Chain_C.FA == 1
    @test Chain_C.PA == 2
end

#=== Julia 1.11+ tests (native `public` keyword) ===#

if VERSION >= v"1.11.0-DEV.469"
    include("runtests_1_11.jl")
end
