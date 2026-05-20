module Republic

export @republic, @public, @reexport
@public public_names, exported_names

# Syntactically unreachable from user code (# prefix)
const _PUBLIC_NAMES_KEY = Symbol("#Republic_public_names")

function _ensure_storage(mod::Module)
    isdefined(mod, _PUBLIC_NAMES_KEY) && return
    Core.eval(mod, :(const $(_PUBLIC_NAMES_KEY) = Symbol[]))
end

function _get_storage(mod::Module)
    isdefined(mod, _PUBLIC_NAMES_KEY) || return Symbol[]
    Base.invokelatest(getfield, mod, _PUBLIC_NAMES_KEY)::Vector{Symbol}
end


_get_public_symbols(sym::Symbol) = [sym]

function _get_public_symbols(expr::Expr)
    if _is_macro_expr(expr)
        return [expr.args[1]]
    end
    expr.head === :tuple ||
        throw(ArgumentError("@public: invalid expression `$expr`. Try `@public foo, bar`"))
    symbols = Vector{Symbol}(undef, length(expr.args))
    for (i, arg) in enumerate(expr.args)
        if arg isa Symbol
            symbols[i] = arg
        elseif _is_macro_expr(arg)
            symbols[i] = arg.args[1]
        else
            throw(ArgumentError("@public: cannot mark `$arg` as public"))
        end
    end
    return symbols
end

function _is_macro_expr(expr)
    expr isa Expr || return false
    Meta.isexpr(expr, :macrocall) || return false
    length(expr.args) == 2 || return false
    expr.args[1] isa Symbol || return false
    s = string(expr.args[1])
    length(s) >= 2 && s[1] == '@' || return false
    expr.args[2] isa LineNumberNode || return false
    return true
end

"""
    @public name
    @public name1, name2, ...
    @public @macro_name

Mark names as part of the module's public API.

On Julia 1.11+, emits the native `public` keyword. On all versions, tracks
the names for cross-version discovery via [`public_names`](@ref).
"""
macro public(symbols_expr)
    syms = _get_public_symbols(symbols_expr)
    mod = __module__
    _ensure_storage(mod)
    append!(_get_storage(mod), syms)
    @static VERSION >= v"1.11.0-DEV.469" ? esc(Expr(:public, syms...)) : nothing
end


"""
    exported_names(mod::Module) -> Vector{Symbol}

Return names that are `export`ed from `mod`.

See also: [`public_names`](@ref)
"""
function exported_names(mod::Module)
    filter(n -> Base.isexported(mod, n), names(mod; all=true, imported=true))
end

"""
    public_names(mod::Module) -> Vector{Symbol}

Return names that are `public` but not `export`ed in `mod`.

On Julia 1.11+, uses `Base.ispublic`. On earlier versions, reads from
Republic's internal per-module storage (populated by [`@public`](@ref) and
[`@republic`](@ref)).

The result is non-overlapping with [`exported_names`](@ref) — together they
form the complete public API of a module.
"""
function public_names(mod::Module)
    @static if VERSION >= v"1.11.0-DEV.469"
        filter(n -> Base.ispublic(mod, n) && !Base.isexported(mod, n),
               names(mod; all=true, imported=true))
    else
        filter(n -> !Base.isexported(mod, n), _get_storage(mod))
    end
end

function _is_visible(mod::Module, name::Symbol)
    Base.isexported(mod, name) && return true
    @static VERSION >= v"1.11.0-DEV.469" ? Base.ispublic(mod, name) : name in _get_storage(mod)
end


"""
    @republic [inherit=…] [reexport=true] [republic=false] using/import ...

Forward upstream names as part of the current module's public API.

**Baseline** (no flags): marks what you bring in as `public`. No wildcard
name discovery beyond what the keyword itself injects.

**`inherit`**: widens *which* upstream names are pulled in. The keyword
(`using` vs `import`) still controls *how* (visibility vs method-extension
capable). Accepted values:

  - `:module` — module binding only. Default for `import X`. Not valid
    with `using` (the floor for `using` is already `:exported`).
  - `:exported` — module + exported names. Default for `using X`. With
    `import X`, pulls exported names in with `import` semantics so methods
    can be extended (the genuinely new capability beyond raw Julia).
  - `:public` — module + exported + public-only names. The widest scope.

Not valid with the selective form `using/import X: a, b` — the scope is
the names you listed.

**`reexport=true`**: re-exports exported names (instead of marking them
`public`).

**`republic=false`**: suppresses the `public` marking. Useful with
`inherit=:public` for importing the full upstream public API without
forwarding it (e.g. package extensions).

The flags are orthogonal and composable.

# Examples

```julia
@republic using Foo                                  # exported names → public
@republic inherit=:public using Foo                  # + public-only names → public
@republic reexport=true using Foo                    # exported → re-export
@republic reexport=true inherit=:public using Foo    # full API forwarding
@republic republic=false inherit=:public using Foo   # import full API, keep private
@republic using Foo: bar, baz                        # specific names → public
@republic reexport=true using Foo: bar               # preserves per-name visibility
@republic inherit=:exported import Foo               # exported names with method-extension
@republic inherit=:public import Foo                 # full API with method-extension
@republic import Foo: bar                            # import semantics + public
@republic begin                                      # blocks
    using Foo
    using Bar
end
```
"""
macro republic(ex::Expr)
    inherit, reexport, do_republic = _parse_flags()
    esc(republic(__module__, inherit, reexport, do_republic, ex))
end

macro republic(f1::Expr, ex::Expr)
    inherit, reexport, do_republic = _parse_flags(f1)
    esc(republic(__module__, inherit, reexport, do_republic, ex))
end

macro republic(f1::Expr, f2::Expr, ex::Expr)
    inherit, reexport, do_republic = _parse_flags(f1, f2)
    esc(republic(__module__, inherit, reexport, do_republic, ex))
end

macro republic(f1::Expr, f2::Expr, f3::Expr, ex::Expr)
    inherit, reexport, do_republic = _parse_flags(f1, f2, f3)
    esc(republic(__module__, inherit, reexport, do_republic, ex))
end

function _parse_flag(ex::Expr)
    ex.head === :(=) && ex.args[1] isa Symbol ||
        error("@republic: expected `flag=value`, got `$ex`")
    name = ex.args[1]::Symbol
    name in (:inherit, :reexport, :republic) ||
        error("@republic: unknown flag `$name`. Expected `inherit`, `reexport`, or `republic`")
    raw = ex.args[2]
    value = if raw isa Bool
        raw
    elseif raw isa QuoteNode && raw.value isa Symbol
        raw.value
    else
        error("@republic: invalid value for `$name`: `$(repr(raw))`")
    end
    return name, value
end

# Map deprecated Bool to the new scope enum (or `nothing` for "use default").
function _normalize_inherit(value)
    if value isa Bool
        if value
            Base.depwarn("`inherit=true` is deprecated; use `inherit=:public`.", :republic)
            return :public
        else
            Base.depwarn("`inherit=false` is deprecated; omit the flag (the per-keyword default already matches).", :republic)
            return nothing
        end
    end
    value isa Symbol ||
        error("@republic: `inherit` expects a Symbol (:module, :exported, or :public), got `$(repr(value))`")
    value in (:module, :exported, :public) ||
        error("@republic: `inherit` must be :module, :exported, or :public; got `:$value`")
    return value
end

function _parse_flags(exprs::Expr...)
    inherit::Union{Nothing,Symbol} = nothing
    reexport = false
    do_republic = true
    seen_inherit = seen_reexport = seen_republic = false
    for ex in exprs
        name, value = _parse_flag(ex)
        if name === :inherit
            seen_inherit && error("@republic: duplicate flag `$name`")
            seen_inherit = true
            inherit = _normalize_inherit(value)
        elseif name === :reexport
            seen_reexport && error("@republic: duplicate flag `$name`")
            seen_reexport = true
            value isa Bool ||
                error("@republic: `reexport` expects `true` or `false`, got `$(repr(value))`")
            reexport = value
        elseif name === :republic
            seen_republic && error("@republic: duplicate flag `$name`")
            seen_republic = true
            value isa Bool ||
                error("@republic: `republic` expects `true` or `false`, got `$(repr(value))`")
            do_republic = value
        end
    end
    return inherit, reexport, do_republic
end


republic(m::Module, inherit::Union{Nothing,Symbol}, reexport::Bool, do_republic::Bool, l::LineNumberNode) = l

function republic(m::Module, inherit::Union{Nothing,Symbol}, reexport::Bool, do_republic::Bool, ex::Expr)
    ex = macroexpand(m, ex)
    if ex.head === :block
        return Expr(:block, map(e -> republic(m, inherit, reexport, do_republic, e), ex.args)...)
    end

    ex.head::Symbol in (:module, :using, :import) ||
        ex.head === :toplevel && all(e -> isa(e, Expr) && e.head === :using, ex.args) ||
        error("@republic: syntax error")

    eval = GlobalRef(Core, :eval)
    _forward = GlobalRef(@__MODULE__, :forward_names)
    _forward_syms = GlobalRef(@__MODULE__, :forward_symbols)
    _resolve = GlobalRef(@__MODULE__, :resolve_module)
    _mark_pub = GlobalRef(@__MODULE__, :_mark_public)
    _mark_exp = GlobalRef(@__MODULE__, :_mark_exported)
    _reimport = GlobalRef(@__MODULE__, :_try_reimport)

    if ex.head === :module
        # Julia 1.14+ prepends a VersionNumber to module args
        modname_idx = ex.args[1] isa VersionNumber ? 3 : 2
        modules = Any[ex.args[modname_idx]]
        ex = Expr(:toplevel, ex, :(using .$(ex.args[modname_idx])))
        # Module form always inherits the full public API
        scope = :public
    elseif ex.head::Symbol in (:using, :import) && ex.args[1].head === :(:)
        # @republic {using, import} Foo: bar, baz, qux as q
        inherit === nothing ||
            error("@republic: `inherit=…` is not valid with selective `using/import X: …`; the scope is the names you listed")
        path_parts = ex.args[1].args[1].args
        orig_names, local_names = _extract_names(ex.args[1].args[2:end])
        return Expr(:toplevel, ex,
            :($_forward_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                $(QuoteNode(orig_names)), $(QuoteNode(local_names)), $reexport, $do_republic)))
    elseif ex.head === :import && all(e -> e.head in (:., :as), ex.args)
        # @republic import Foo.bar, Baz.qux, Pkg as P — floor is :module
        scope = inherit === nothing ? :module : inherit
        out = Expr(:toplevel, ex)
        for arg in ex.args
            if arg.head === :as
                path = arg.args[1]  # Expr(:., ...)
                local_name = arg.args[2]
            else
                path = arg
                local_name = arg.args[end]
            end
            orig_name = path.args[end]
            path_parts = path.args[1:end-1]
            if isempty(path_parts)
                # `import Foo` or `import Foo as Bar` — module import
                if reexport
                    push!(out.args, :($_mark_exp($eval, $m, [$(QuoteNode(local_name))])))
                elseif do_republic
                    push!(out.args, :($_mark_pub($eval, $m, [$(QuoteNode(local_name))])))
                end
            else
                push!(out.args,
                    :($_forward_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                        $(QuoteNode([orig_name])), $(QuoteNode([local_name])), $reexport, $do_republic)))
            end
            if scope !== :module
                push!(out.args, :($_reimport($eval, $m, $(QuoteNode(local_name)),
                    $(QuoteNode(scope)), $reexport, $do_republic)))
            end
        end
        return out
    else
        # @republic using Foo, Bar, Baz — floor is :exported
        scope = inherit === nothing ? :exported : inherit
        scope === :module &&
            error("@republic: `inherit=:module` is not valid with `using`; the natural floor for `using` is `:exported`. Use `import` if you only want the module binding.")
        modules = Any[e.args[end] for e in ex.args]
    end

    out = Expr(:toplevel, ex)
    for mod in modules
        push!(out.args, :($_forward($eval, $m, $mod, $(QuoteNode(scope)), $reexport, $do_republic)))
    end
    return out
end


function _extract_names(entries)
    orig_names = Symbol[]
    local_names = Symbol[]
    for e in entries
        if e.head === :as
            push!(orig_names, e.args[1].args[end])
            push!(local_names, e.args[2])
        else
            # Expr(:., :name)
            push!(orig_names, e.args[end])
            push!(local_names, e.args[end])
        end
    end
    return orig_names, local_names
end

function resolve_module(m::Module, parts)
    idx = 1
    if parts[1] === :.
        # Relative: first dot = current module, each additional = parent
        mod = m
        idx = 2
        while idx <= length(parts) && parts[idx] === :.
            mod = parentmodule(mod)
            idx += 1
        end
    else
        # Absolute: find loaded root module by name
        mod = _resolve_root(m, parts[1])
        idx = 2
    end
    for i in idx:length(parts)
        mod = getfield(mod, parts[i])
    end
    return mod
end

function _resolve_root(m::Module, name::Symbol)
    name === :Base && return Base
    name === :Core && return Core
    return Base.root_module(m, name)
end


function _mark_public(eval, m::Module, nms::Vector{Symbol})
    # Filter out names already exported in m — Julia errors on public-after-export
    filter!(n -> !Base.isexported(m, n), nms)
    isempty(nms) && return
    # Always track for cross-version discovery
    _ensure_storage(m)
    append!(_get_storage(m), nms)
    # Emit native keyword on 1.11+
    @static if VERSION >= v"1.11.0-DEV.469"
        eval(m, Expr(:public, nms...))
    end
end

function _mark_exported(eval, m::Module, nms::Vector{Symbol})
    @static if VERSION >= v"1.11.0-DEV.469"
        # Filter out names already public (not exported) in m — Julia errors on export-after-public
        filter!(n -> !Base.ispublic(m, n) || Base.isexported(m, n), nms)
    end
    isempty(nms) && return
    eval(m, Expr(:export, nms...))
end

function forward_names(eval, m::Module, upstream::Module, scope::Symbol, reexport::Bool, do_republic::Bool=true)
    # `using` floor is :exported — the original `using X` statement already
    # brought exported names into m; here we just mark them.
    if reexport
        _mark_exported(eval, m, exported_names(upstream))
    elseif do_republic
        _mark_public(eval, m, exported_names(upstream))
    end
    # :public widens to also discover public-only names (with `using` semantics)
    if scope === :public
        pub = public_names(upstream)
        fqn = fullname(upstream)
        for name in pub
            eval(m, Expr(:using, Expr(:(:), Expr(:., fqn...), Expr(:., name))))
        end
        do_republic && _mark_public(eval, m, pub)
    end
    nothing
end

function _try_reimport(eval, m::Module, name::Symbol, scope::Symbol, reexport::Bool, do_republic::Bool)
    isdefined(m, name) || return nothing
    val = getfield(m, name)
    val isa Module || return nothing
    reimport_names(eval, m, val, scope, reexport, do_republic)
end

function reimport_names(eval, m::Module, upstream::Module, scope::Symbol, reexport::Bool, do_republic::Bool)
    fqn = fullname(upstream)
    exp = exported_names(upstream)
    pub = scope === :public ? public_names(upstream) : Symbol[]
    # Import the in-scope names with import semantics (method extension possible)
    for name in Iterators.flatten((exp, pub))
        eval(m, Expr(:import, Expr(:(:), Expr(:., fqn...), Expr(:., name))))
    end
    if reexport
        _mark_exported(eval, m, exp)
    elseif do_republic
        _mark_public(eval, m, exp)
    end
    do_republic && _mark_public(eval, m, pub)
    nothing
end

function forward_symbols(eval, m::Module, upstream::Module,
                           orig_names::Vector{Symbol}, local_names::Vector{Symbol},
                           reexport::Bool, do_republic::Bool=true)
    exported = Symbol[]
    public_only = Symbol[]
    for (orig, local_name) in zip(orig_names, local_names)
        if reexport && Base.isexported(upstream, orig)
            push!(exported, local_name)
        elseif do_republic && _is_visible(upstream, orig)
            push!(public_only, local_name)
        end
    end
    _mark_exported(eval, m, exported)
    do_republic && _mark_public(eval, m, public_only)
    nothing
end

"""
    @reexport [inherit=…] [republic=false] using/import ...

Shorthand for `@republic reexport=true ...`. See [`@republic`](@ref).
"""
macro reexport(ex::Expr)
    esc(republic(__module__, nothing, true, true, ex))
end

macro reexport(f1::Expr, ex::Expr)
    inherit, _, do_republic = _parse_reexport_flags(f1)
    esc(republic(__module__, inherit, true, do_republic, ex))
end

macro reexport(f1::Expr, f2::Expr, ex::Expr)
    inherit, _, do_republic = _parse_reexport_flags(f1, f2)
    esc(republic(__module__, inherit, true, do_republic, ex))
end

function _parse_reexport_flags(exprs::Expr...)
    for ex in exprs
        name, _ = _parse_flag(ex)
        name === :reexport && error("@reexport: `reexport` flag is redundant — @reexport implies reexport=true")
    end
    _parse_flags(exprs...)
end

end
