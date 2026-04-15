module Republic

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
    @static if VERSION >= v"1.11.0-DEV.469"
        return esc(Expr(:public, syms...))
    else
        return nothing
    end
end


"""
    exported_names(mod::Module) -> Vector{Symbol}

Return names that are `export`ed from `mod`. Version-invariant.

See also: [`public_names`](@ref)
"""
function exported_names(mod::Module)
    filter(n -> Base.isexported(mod, n), names(mod; all=true, imported=true))
end

"""
    public_names(mod::Module) -> Vector{Symbol}

Return names that are `public` but not `export`ed in `mod`. Version-invariant.

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

# Version-invariant visibility check (exported OR public)
function _is_visible(mod::Module, name::Symbol)
    Base.isexported(mod, name) && return true
    @static if VERSION >= v"1.11.0-DEV.469"
        return Base.ispublic(mod, name)
    else
        return name in _get_storage(mod)
    end
end


"""
    @republic [inherit=true] [reexport=true] using/import ...

Forward upstream names as part of the current module's public API.

**Baseline** (no flags): marks what you bring in as `public`. No wildcard
name discovery.

**`inherit=true`**: discovers public-only names upstream, imports them, and
marks them `public`.

**`reexport=true`**: re-exports exported names (instead of marking them
`public`).

The flags are orthogonal and composable.

# Examples

```julia
@republic using Foo                                # exported names → public
@republic inherit=true using Foo                   # + public-only names → public
@republic reexport=true using Foo                  # exported → re-export
@republic reexport=true inherit=true using Foo     # full API forwarding
@republic using Foo: bar, baz                      # specific names → public
@republic reexport=true using Foo: bar             # preserves per-name visibility
@republic import Foo: bar                          # import semantics + public
@republic begin                                    # blocks
    using Foo
    using Bar
end
```
"""
macro republic(ex::Expr)
    esc(republic(__module__, false, false, ex))
end

macro republic(flag_ex::Expr, ex::Expr)
    name, value = _parse_flag(flag_ex)
    inherit = name === :inherit && value
    reexport = name === :reexport && value
    esc(republic(__module__, inherit, reexport, ex))
end

macro republic(flag1::Expr, flag2::Expr, ex::Expr)
    n1, v1 = _parse_flag(flag1)
    n2, v2 = _parse_flag(flag2)
    n1 !== n2 || error("@republic: duplicate flag `$n1`")
    inherit = (n1 === :inherit ? v1 : v2)
    reexport = (n1 === :reexport ? v1 : v2)
    esc(republic(__module__, inherit, reexport, ex))
end

function _parse_flag(ex::Expr)
    ex.head === :(=) && ex.args[1] isa Symbol ||
        error("@republic: expected `flag=value`, got `$ex`")
    name = ex.args[1]::Symbol
    name in (:inherit, :reexport) ||
        error("@republic: unknown flag `$name`. Expected `inherit` or `reexport`")
    value = ex.args[2]::Bool
    return name, value
end


republic(m::Module, inherit::Bool, reexport::Bool, l::LineNumberNode) = l

function republic(m::Module, inherit::Bool, reexport::Bool, ex::Expr)
    ex = macroexpand(m, ex)
    if ex.head === :block
        return Expr(:block, map(e -> republic(m, inherit, reexport, e), ex.args)...)
    end

    ex.head::Symbol in (:module, :using, :import) ||
        ex.head === :toplevel && all(e -> isa(e, Expr) && e.head === :using, ex.args) ||
        error("@republic: syntax error")

    eval = GlobalRef(Core, :eval)
    _republish = GlobalRef(@__MODULE__, :republish_names)
    _republish_syms = GlobalRef(@__MODULE__, :republish_symbols)
    _resolve = GlobalRef(@__MODULE__, :resolve_module)
    _mark_pub = GlobalRef(@__MODULE__, :_mark_public)
    _mark_exp = GlobalRef(@__MODULE__, :_mark_exported)

    if ex.head === :module
        modules = Any[ex.args[2]]
        ex = Expr(:toplevel, ex, :(using .$(ex.args[2])))
        # Module form always inherits public-only names
        inherit = true
    elseif ex.head::Symbol in (:using, :import) && ex.args[1].head === :(:)
        # @republic {using, import} Foo: bar, baz, qux as q
        path_parts = ex.args[1].args[1].args
        orig_names, local_names = _extract_names(ex.args[1].args[2:end])
        return Expr(:toplevel, ex,
            :($_republish_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                $(QuoteNode(orig_names)), $(QuoteNode(local_names)), $inherit, $reexport)))
    elseif ex.head === :import && all(e -> e.head in (:., :as), ex.args)
        # @republic import Foo.bar, Baz.qux, Pkg as P
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
                _mark = reexport ? _mark_exp : _mark_pub
                push!(out.args, :($_mark($eval, $m, [$(QuoteNode(local_name))])))
            else
                push!(out.args,
                    :($_republish_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                        $(QuoteNode([orig_name])), $(QuoteNode([local_name])), $inherit, $reexport)))
            end
        end
        return out
    else
        # @republic using Foo, Bar, Baz
        modules = Any[e.args[end] for e in ex.args]
    end

    out = Expr(:toplevel, ex)
    for mod in modules
        push!(out.args, :($_republish($eval, $m, $mod, $inherit, $reexport)))
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

function republish_names(eval, m::Module, upstream::Module, inherit::Bool, reexport::Bool)
    exp = collect(exported_names(upstream))
    if reexport
        _mark_exported(eval, m, exp)
    else
        _mark_public(eval, m, exp)
    end
    # Inherit: also discover and import public-only names
    if inherit
        pub = collect(public_names(upstream))
        fqn = fullname(upstream)
        for name in pub
            eval(m, Expr(:using, Expr(:(:), Expr(:., fqn...), Expr(:., name))))
        end
        _mark_public(eval, m, pub)
    end
    nothing
end

function republish_symbols(eval, m::Module, upstream::Module,
                           orig_names::Vector{Symbol}, local_names::Vector{Symbol},
                           inherit::Bool, reexport::Bool)
    exported = Symbol[]
    public_only = Symbol[]
    for (orig, local_name) in zip(orig_names, local_names)
        if reexport && Base.isexported(upstream, orig)
            push!(exported, local_name)
        elseif _is_visible(upstream, orig)
            push!(public_only, local_name)
        end
    end
    _mark_exported(eval, m, exported)
    _mark_public(eval, m, public_only)
    nothing
end

export @republic, @public
@public public_names, exported_names

end
