# Republic.jl

[![Build Status](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/MurrellGroup/Republic.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/MurrellGroup/Republic.jl)

> Dependencies united under one public API.

Republic.jl manages Julia's [`public`](https://docs.julialang.org/en/v1.11/base/base/#public) visibility across module boundaries and Julia versions. It provides:

- **`@public`** — declare names as public API, with cross-version tracking
- **`@republic`** — forward upstream names into your module's public API
- **`public_names` / `exported_names`** — version-invariant discovery functions

On Julia 1.11+, Republic uses the native `public` keyword. On earlier versions, it tracks declarations internally and degrades gracefully.

## `@public`: Declaring Public API

```julia
using Republic: @public

@public foo              # single name
@public foo, bar, baz    # multiple names
@public @my_macro        # macro name
```

Replaces [SciMLPublic.jl](https://github.com/SciML/SciMLPublic.jl) and `@compat public` from [Compat.jl](https://github.com/JuliaLang/Compat.jl). Unlike those packages, Republic tracks declarations for cross-version discovery via `public_names(mod)`.

## `@republic`: Forwarding Public API

`@republic` has two orthogonal, composable flags:

| | `inherit=false` (default) | `inherit=true` |
|---|---|---|
| **`reexport=false`** (default) | exported → `public` | exported → `public`, public-only → import + `public` |
| **`reexport=true`** | exported → re-`export` | exported → re-`export`, public-only → import + `public` |

### Baseline (no flags)

Marks what you bring in as `public`. No wildcard name discovery.

```julia
@republic using Foo                 # exported names → public
@republic using Foo: bar, baz       # specific names → public
@republic import Foo: bar           # import semantics + public
```

### `inherit=true`

Discovers public-only names upstream. Imports them and marks them `public`.

```julia
@republic inherit=true using Foo    # all API names → public
```

### `reexport=true`

Re-exports exported names (instead of marking them `public`). Replaces [Reexport.jl](https://github.com/JuliaLang/Reexport.jl).

```julia
@republic reexport=true using Foo   # exported → re-export
```

### Combined: full API forwarding

```julia
@republic reexport=true inherit=true using Foo  # re-export + inherit public
```

### Full example

```julia
module MyPackage
    using Republic

    # Baseline: mark specific names
    @republic using Foo: bar, baz
    @republic import Foo: qux       # qux is extensible + public

    # Inherit: forward the full public API
    @republic inherit=true using CorePkg

    # Re-export + inherit: the CUDA.jl pattern
    @republic reexport=true inherit=true using BasePkg

    # Blocks
    @republic reexport=true inherit=true begin
        using Dep1
        using Dep2
    end
end
```

## Discovery API

```julia
exported_names(mod)   # names that are `export`ed — works on any Julia version
public_names(mod)     # names that are `public` but not `export`ed — version-invariant
```

These two functions partition a module's API into non-overlapping sets. On Julia 1.11+, `public_names` uses `Base.ispublic`. On earlier versions, it reads from Republic's internal tracking (populated by `@public` and `@republic`).

## Overriding visibility

Julia does not allow a name to be both `public` and `export`ed. Republic respects pre-existing declarations:

```julia
module MyPackage
    using Republic
    export bar                                  # already exported
    @republic republish=true using Foo          # skips `public bar`
end
```

```julia
module MyPackage
    using Republic
    public bar                                  # already public
    @republic reexport=true using Foo           # skips `export bar`
end
```

## Migration from v1.x

The default behavior of `@republic` changed in v2.0:

| v1.x | v2.0 equivalent |
|---|---|
| `@republic using Foo` | `@republic inherit=true using Foo` |
| `@republic reexport=true using Foo` | `@republic reexport=true inherit=true using Foo` |

The v1.x default performed wildcard discovery. In v2.0, the baseline is explicit — use `inherit=true` to opt into discovery. `reexport=true` no longer implies `inherit`.

## Acknowledgments

Republic.jl is derived from [Reexport.jl](https://github.com/JuliaLang/Reexport.jl) by Simon Kornblith (MIT License).
