# Republic.jl

[![Build Status](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/MurrellGroup/Republic.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/MurrellGroup/Republic.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/MurrellGroup/Republic.jl)

> Declare, unify, and forward public APIs across Julia versions.

Republic.jl manages Julia's [`public`](https://docs.julialang.org/en/v1.11/base/base/#public) visibility across module boundaries and Julia versions. It provides:

- **`@public`** — declare names as public API, equivalent to the `public` keyword introduced in 1.11
- **`@republic`** — forward upstream names into your module's public API
- **`@reexport`** — shorthand for `@republic reexport=true`
- **`public_names`** — returns public-but-not-exported names
- **`exported_names`** — returns exported names

The main use case for forwarding is lightweight \*Core or \*Base packages, whose types and functions you want to surface as part of your package's API. This also works for heavier packages whose interfaces you may be implementing, but prefer a qualified `@republic` import to avoid clutter.

## `@public`: Declaring Public API

```julia
using Republic: @public

@public foo              # single name
@public foo, bar, baz    # multiple names
@public @my_macro        # macro name
```

`@public` replaces `@compat public` from [Compat.jl](https://github.com/JuliaLang/Compat.jl), tracking declarations for cross-version discovery via `public_names(mod)`.

## `@republic`: Forwarding Public API

`@republic` preserves `using`/`import` semantics and has three orthogonal, composable flags:

- **`inherit`** — widen *which* upstream names are pulled in (`:module`, `:exported`, or `:public`; default tracks the keyword)
- **`reexport`** — re-export exported names instead of marking them `public` (default: `false`)
- **`republic`** — mark imported names as `public` (default: `true`)

### `using` vs `import`

`@republic` preserves Julia's native `using`/`import` distinction:

- **`using`** brings names into scope for *use* (no method extension)
- **`import`** brings names into scope for *extension* (methods can be added)

### The `inherit` scope

`inherit` controls *which* upstream names are inherited into the consumer module; the keyword controls *how* (visibility vs method-extension capable). Marking/forwarding to the consumer's public API is orthogonal — see `republic` and `reexport`. Defaults match each keyword's native floor (i.e. `@republic using/import Foo` inherits exactly what raw `using/import Foo` does).

| Value | `using Foo` | `import Foo` |
|---|---|---|
| `:module` | rewritten to `using Foo: Foo` — only the module binding (exported names NOT inherited) | module binding only (**default**) |
| `:exported` | module + exported (**default**) | module + exported, with import semantics |
| `:public` | module + exported + public-only | module + exported + public-only, with import semantics |

At the `:module` level, the using/import distinction collapses — both yield just the module binding, and no method extension applies to a module.

```julia
@republic using Foo                  # exported names → public (default scope :exported)
@republic inherit=:public using Foo  # + public-only names → public
@republic import Foo                 # module binding only → public (default scope :module)
@republic inherit=:exported import Foo  # + exported names, with import semantics
@republic inherit=:public import Foo    # + exported + public-only, with import semantics
```

`inherit` is not valid with the selective form `using/import Foo: a, b` — the scope is the names you listed.

### Baseline (no flags)

Marks what the keyword brings in as `public`. No widening.

```julia
@republic using Foo                 # exported names → public
@republic using Foo: bar, baz       # specific names → public
@republic import Foo: bar           # import semantics + public
```

### `reexport=true`

Re-exports exported names (instead of marking them `public`). Replaces [Reexport.jl](https://github.com/JuliaLang/Reexport.jl).

```julia
@republic reexport=true using Foo   # exported → re-export
@reexport using Foo                 # equivalent shorthand
```

### `republic=false`

Suppresses the `public` marking. Useful with `inherit=:public` for importing the full upstream public API without forwarding it (e.g. package extensions).

```julia
@republic republic=false inherit=:public using Foo     # import full API, keep private
@republic republic=false inherit=:public import Foo    # same, with import semantics
```

### Combined: full API forwarding

```julia
@republic reexport=true inherit=:public using Foo  # re-export + inherit public
@reexport inherit=:public using Foo                # equivalent shorthand
```

## Overriding visibility through pre-existing declarations

Julia does not allow a name to be marked both `public` and `export`ed. Republic respects pre-existing declarations:

```julia
module MyPackage
    using Republic
    export bar                                       # already exported
    @republic inherit=:public using Foo              # skips `public bar`
end
```

```julia
module MyPackage
    using Republic
    @public bar                                      # already public
    @republic reexport=true using Foo                # skips `export bar`
end
```

## Migration

The default behavior of `@republic` changed in v2.0:

| v1.x | v2.0 equivalent |
|---|---|
| `@republic using Foo` | `@republic inherit=:public using Foo` |
| `@republic reexport=true using Foo` | `@republic reexport=true inherit=:public using Foo` |

The v1.x default performed wildcard discovery. In v2.0, the baseline is explicit — use `inherit=:public` to opt into the widest discovery. `reexport=true` no longer implies `inherit`.

The Boolean `inherit=true`/`inherit=false` accepted in v2.0–v2.1 is deprecated; use `inherit=:public` (or omit the flag) instead.

## Acknowledgments

Republic.jl is derived from [Reexport.jl](https://github.com/JuliaLang/Reexport.jl) by Simon Kornblith (MIT License).

Republic.jl v2 was inspired by `@public` from [CUDACore.jl](https://github.com/JuliaGPU/CUDA.jl/blob/c27d64b2ec32f72e82201364e20b0eb550f11e48/CUDACore/src/utils/public.jl).
