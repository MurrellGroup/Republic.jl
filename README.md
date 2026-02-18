# Republic.jl

[![Build Status](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/MurrellGroup/Republic.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/MurrellGroup/Republic.jl)

> Dependencies united under one public API.

Republic.jl re-publicizes names from upstream modules, making them part of your module's public API without exporting them into the caller's namespace. Like [Reexport.jl](https://github.com/JuliaLang/Reexport.jl), but for Julia's [`public`](https://docs.julialang.org/en/v1.11/base/base/#public) keyword (introduced in Julia 1.11).

## Usage

```julia
module MyPackage
    using Republic

    # All of Foo's public and exported names become `public` in MyPackage
    @republic using Foo

    # Specific names
    @republic using Foo: bar, baz

    # Aliases: F becomes public in MyPackage
    @republic using Foo: Foo as F

    # Blocks
    @republic begin
        using Foo
        using Bar
    end
end
```

Names marked public are accessible via qualified access (`MyPackage.bar`) without being brought into scope by `using MyPackage`. This is useful for packages that want to expose a broad API surface without polluting the caller's namespace.

## Re-exporting

By default, `@republic` makes everything public. To also re-export names that were exported upstream, use `reexport=true`:

```julia
@republic reexport=true using Foo
```

With `reexport=true`, exported names are re-exported (like Reexport.jl), and public-only names are marked public. Republic never promotes a public-only name to exported — that is a deliberate choice left to the user (see below).

## Overriding visibility

Julia does not allow a name to be marked with both `public` and `export`. This only matters if a name is `public` upstream but you want to `export` it in your module — names that are already `export`ed upstream can be handled with `reexport=true`. To export a public-only name, declare the `export` *before* `@republic`:

```julia
module MyPackage
    using Republic
    export bar            # bar will be exported, not just public
    @republic using Foo   # skips `public` for bar since it's already exported
end
```

Alternatively, use qualified imports to keep `@republic` and `export` separate:

```julia
module MyPackage
    using Republic
    using Foo: bar
    export bar
    @republic using Foo: baz, qux  # only these become public
end
```

## Acknowledgments

Republic.jl is derived from [Reexport.jl](https://github.com/JuliaLang/Reexport.jl) by Simon Kornblith (MIT License).
