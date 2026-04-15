# Republic.jl

[![Build Status](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/MurrellGroup/Republic.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/MurrellGroup/Republic.jl)

> Cross-version public API management for Julia packages.

Republic.jl manages Julia's [`public`](https://docs.julialang.org/en/v1.11/base/base/#public) visibility across module boundaries and Julia versions. It provides:

- **`@public`** — declare names as public API
- **`@republic`** — forward upstream names into your module's public API
- **`public_names` / `exported_names`** — discover public / exported functions

On Julia 1.11+, Republic uses the native `public` keyword. On earlier versions, it tracks declarations internally and degrades gracefully.

## `@public`: Declaring Public API

```julia
using Republic: @public

@public foo              # single name
@public foo, bar, baz    # multiple names
@public @my_macro        # macro name
```

Republic replaces `@compat public` from [Compat.jl](https://github.com/JuliaLang/Compat.jl), tracking declarations for cross-version discovery via `public_names(mod)`.

## `@republic`: Forwarding Public API

`@republic` has two orthogonal, composable flags:

| | `inherit=false` (default) | `inherit=true` |
|---|---|---|
| **`reexport=false`** (default) | exported → `public` | exported → `public`, public-only → import + `public` |
| **`reexport=true`** | exported → re-`export` | exported → re-`export`, public-only → import + `public` |

### Baseline (no flags)

Marks what you bring in as `public`.

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
@republic reexport=true using Foo             # exported → re-export
```

### Combined: full API forwarding

```julia
@republic reexport=true inherit=true using Foo  # re-export + inherit public
```

## Overriding visibility

Julia does not allow a name to be marked both `public` and `export`ed. Republic respects pre-existing declarations:

```julia
module MyPackage
    using Republic
    export bar                                  # already exported
    @republic inherit=true using Foo            # skips `public bar`
end
```

```julia
module MyPackage
    using Republic
    @public bar                                 # already public
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

Republic.jl v2 was inspired by `@public` from [CUDACore.jl](https://github.com/JuliaGPU/CUDA.jl/blob/c27d64b2ec32f72e82201364e20b0eb550f11e48/CUDACore/src/utils/public.jl).
