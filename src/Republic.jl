module Republic

"""
    @republic [reexport=false] using/import ...

Mark upstream `public` and `export`ed names as `public` in the current module.
Public-only names that aren't brought in by `using` are imported automatically.

By default, all names become `public` (not exported). Use `reexport=true` to
also re-export names that were `export`ed upstream.

Supports all `using`/`import` forms, including `as` aliases, blocks, and
module definitions.

# Examples

```julia
@republic using Foo                          # Foo's public API becomes public here
@republic using Foo: bar, baz                # specific names become public
@republic reexport=true using Foo            # also re-exports exported names
@republic using Foo: Foo as F                # aliases supported
@republic begin                              # blocks supported
    using Foo
    using Bar
end
```
"""
macro republic(ex::Expr)
    esc(republic(__module__, false, ex))
end

macro republic(reexport_ex::Expr, ex::Expr)
    reexport_ex.head === :(=) && reexport_ex.args[1] === :reexport ||
        error("@republic: expected `reexport=true` or `reexport=false`, got `$reexport_ex`")
    reexport = reexport_ex.args[2]::Bool
    esc(republic(__module__, reexport, ex))
end

republic(m::Module, reexport::Bool, l::LineNumberNode) = l

function republic(m::Module, reexport::Bool, ex::Expr)
    ex = macroexpand(m, ex)
    if ex.head === :block
        return Expr(:block, map(e -> republic(m, reexport, e), ex.args)...)
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
    elseif ex.head::Symbol in (:using, :import) && ex.args[1].head === :(:)
        # @republic {using, import} Foo: bar, baz, qux as q
        path_parts = ex.args[1].args[1].args
        orig_names, local_names = _extract_names(ex.args[1].args[2:end])
        return Expr(:toplevel, ex,
            :($_republish_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                $(QuoteNode(orig_names)), $(QuoteNode(local_names)), $reexport)))
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
                # `import Foo as Bar` — module import
                _mark = reexport ? _mark_exp : _mark_pub
                push!(out.args, :($_mark($eval, $m, [$(QuoteNode(local_name))])))
            else
                push!(out.args,
                    :($_republish_syms($eval, $m, $_resolve($m, $(QuoteNode(path_parts))),
                        $(QuoteNode([orig_name])), $(QuoteNode([local_name])), $reexport)))
            end
        end
        return out
    else
        # @republic using Foo, Bar, Baz
        modules = Any[e.args[end] for e in ex.args]
    end

    out = Expr(:toplevel, ex)
    for mod in modules
        push!(out.args, :($_republish($eval, $m, $mod, $reexport)))
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
        mod = Base.root_module(m, parts[1])
        idx = 2
    end
    for i in idx:length(parts)
        mod = getfield(mod, parts[i])
    end
    return mod
end

function _mark_public(eval, m::Module, names::Vector{Symbol})
    # Filter out names already exported in m — Julia errors on public-after-export
    filter!(n -> !Base.isexported(m, n), names)
    isempty(names) || eval(m, Expr(:public, names...))
end

function _mark_exported(eval, m::Module, names::Vector{Symbol})
    # Filter out names already public (not exported) in m — Julia errors on export-after-public
    filter!(n -> !Base.ispublic(m, n) || Base.isexported(m, n), names)
    isempty(names) || eval(m, Expr(:export, names...))
end

function republish_names(eval, m::Module, upstream::Module, reexport::Bool)
    exported = Symbol[]
    public_only = Symbol[]
    for name in names(upstream; all=true, imported=true)
        if Base.isexported(upstream, name)
            push!(exported, name)
        elseif Base.ispublic(upstream, name)
            push!(public_only, name)
        end
    end
    if reexport
        _mark_exported(eval, m, exported)
    else
        _mark_public(eval, m, exported)
    end
    # Import public-only names so they're actual bindings, then mark public
    for name in public_only
        eval(m, Expr(:import, Expr(:., fullname(upstream)..., name)))
    end
    _mark_public(eval, m, public_only)
    nothing
end

function republish_symbols(eval, m::Module, upstream::Module,
                           orig_names::Vector{Symbol}, local_names::Vector{Symbol},
                           reexport::Bool)
    exported = Symbol[]
    public_only = Symbol[]
    for (orig, local_name) in zip(orig_names, local_names)
        if reexport && Base.isexported(upstream, orig)
            push!(exported, local_name)
        else
            push!(public_only, local_name)
        end
    end
    _mark_exported(eval, m, exported)
    _mark_public(eval, m, public_only)
    nothing
end

export @republic

end
