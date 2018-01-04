module LocalMemoize

export @memo, @memoize, get_memos, clear_memos

const MemoizedFunctions = ObjectIdDict()

get_memos(::Type{T}) where T = haskey(MemoizedFunctions, T) ?
    MemoizedFunctions[T] :
    error("No memoized cache found")
get_memos(func) = get_memos(typeof(func))
clear_memos(::Type{T}) where T = haskey(MemoizedFunctions, T) ?
    map(MemoizedFunctions[T]) do cache_table
        for key in keys(cache_table)
            delete!(cache_table, key)
        end
        cache_table
    end :
    error("No memoized cache found")
clear_memos(func) = clear_memos(typeof(func))

macro memo(expr)
    esc(expr)
end

macro memo(args...)
    nothing
end

macro memoize(expr)
    if expr isa Expr && expr.head == :function
        assign_syntax = false
    elseif expr isa Expr && expr.head == :(=) && (expr.args[1].head == :call ||
        expr.args[1].head == :(::) && expr.args[1].args[1].head == :call)
        assign_syntax = true
    else
        error("@memoize must be used on a function declaration.")
    end
    funcdecl = expr.args[1]
    funcrett = nothing
    if funcdecl.head == :(::)
        funcrett = funcdecl.args[2]
        funcdecl = funcdecl.args[1]
    end
    funcname = funcdecl.args[1]
    funcargs = funcdecl.args[2:end]
    funcbody = expr.args[2]
    memo_argnames = Symbol[]
    memo_argtypes = Symbol[]
    argdef_list = []
    argname_list = Symbol[]
    argtype_list = Symbol[]
    check_memocall = arg -> arg isa Expr && arg.head == :macrocall &&
        arg.args[1] == Symbol("@memo") && length(arg.args) > 1
    for arg in funcargs
        if check_memocall(arg)
            length(arg.args) != 2 && error("@memo in argument list only must have one and only one argument.")
            argdef = arg.args[2]
        else
            argdef = arg
        end
        if argdef isa Symbol
            argname = argdef
            argtype = :Any
        elseif argdef isa Expr && (argdef.head == :(=) || argdef.head == :kw)
            argdef1 = argdef.args[1]
            if argdef1 isa Symbol
                argname = argdef1
                argtype = :Any
            elseif argdef1 isa Expr && argdef1.head == :(::)
                argname = argdef1.args[1]
                argtype = argdef2.args[2]
            end
        elseif argdef isa Expr && argdef.head == :(::)
            argname = argdef.args[1]
            argtype = argdef.args[2]
        elseif argdef isa Expr && argdef.head == :parameters
        else
            error("Invalid argument list")
        end
        if check_memocall(arg)
            push!(memo_argnames, argname)
            push!(memo_argtypes, argtype)
        end
        push!(argdef_list, argdef)
        push!(argname_list, argname)
        push!(argtype_list, argtype)
    end

    lines = 0
    check_memolist = args -> all(arg -> arg isa Symbol, args)
    check_assignment = arg -> arg isa Expr && arg.head == :(=) &&
        arg.args[1] isa Symbol
    memolist = Symbol[]
    for (i, expression) in enumerate(funcbody.args)
        if check_memocall(expression)
            if check_memolist(expression.args[2:end])
                append!(memolist, expression.args[2:end])
            elseif check_assignment(expression.args[2])
                push!(memolist, expression.args[2].args[1])
            else
                error("@memo in body must be used on an assignment or a list of variables to be memoized.")
            end
            lines = i
        end
    end
    memoize_return = lines == 0
    if memoize_return && length(memo_argnames) != 0
        error("In function memoization @memo can not be used on arguments.")
    end
    if memoize_return
        memo_argnames = argname_list
        memo_argtypes = argtype_list
    end

    getsymbol = name -> Symbol(string(gensym(), "_", funcname, "_", name))

    func_cachename = getsymbol("memocache")
    cachename = getsymbol("cache")
    index_name = getsymbol("index")

    cache_struct = getsymbol("cache_t")
    dict_type = :(Dict{Tuple{$(memo_argtypes...)}, $(cache_struct)})

    if memoize_return
        original_func_name = getsymbol("original")
        original_func = :($original_func_name($(argdef_list...))=$funcbody)
        func_main = :(
            function $funcname($(argdef_list...))
                $index_name = Base.ht_keyindex($func_cachename, ($(memo_argnames...),))
                if $index_name >= 0
                    @inbounds return $func_cachename.vals[$index_name]
                else
                    $func_cachename[($(memo_argnames...),)] = $original_func_name($(argname_list...))
                end
            end
        )
        funcrett != nothing && map([original_func, func_main]) do func
            func.args[1] = :($(func.args[1])::$funcrett)
        end
        result = quote
            $original_func
            const $cache_struct = Core.Inference.return_type($original_func_name, ($(argtype_list...),))
            const $func_cachename = $dict_type()
            $func_main
            if !haskey(LocalMemoize.MemoizedFunctions, typeof($funcname))
                LocalMemoize.MemoizedFunctions[typeof($funcname)] = Any[]
            end
            push!(LocalMemoize.MemoizedFunctions[typeof($funcname)], $func_cachename)
            $funcname
        end
     else
        gettype_func_name = getsymbol("gettype")
        func1_name = getsymbol("1")
        func2_name = getsymbol("2")

        # For getting memoized type
        gettype_func = :(function $gettype_func_name($(argdef_list...)) end)
        # For first time run
        func1 = :(function $func1_name($func_cachename::$dict_type, $(argdef_list...)) end)
        # For memoized runs
        func2 = :(function $func2_name($cachename::$cache_struct, $(argdef_list...)) end)
        gettype_func_body = gettype_func.args[end].args
        func1_body = func1.args[end].args
        func2_body = func2.args[end].args

        for (i, expression) in enumerate(funcbody.args)
            if check_memocall(expression)
                if !check_memolist(expression.args[2:end])
                    push!(gettype_func_body, expression.args[2])
                    push!(func1_body, expression.args[2])
                end
            else
                push!(gettype_func_body, expression)
                push!(func1_body, expression)
            end
            if i == lines
                push!(gettype_func_body, :(
                    return ($(memolist...),)
                ))
                push!(func1_body, :(
                    $func_cachename[($(memo_argnames...),)] = $cache_struct($(memolist...))
                ))
                for memovar in memolist
                    push!(func2_body, :(
                        $memovar = getfield($cachename, $(QuoteNode(memovar)))
                    ))
                end
            elseif i > lines
                push!(func2_body, expression)
            end
        end
        func_main = :(function $funcname($(argdef_list...))
            $index_name = Base.ht_keyindex($func_cachename, ($(memo_argnames...),))
            if $index_name >= 0
                @inbounds $cachename = $func_cachename.vals[$index_name]
                $func2_name($cachename, $(argname_list...))
            else
                $func1_name($func_cachename, $(argname_list...))
            end
        end)
        funcrett != nothing && map([func1, func2, func_main]) do func
            func.args[1] = :($(func.args[1])::$funcrett)
        end
        result = quote
            let gettype_func = $gettype_func
                types = Core.Inference.return_type(gettype_func, ($(argtype_list...),))
                cache_struct = $(QuoteNode(cache_struct))
                struct_code = :(struct $cache_struct end)
                argnames = $memolist
                for (argname, typ) in zip(argnames, types.types)
                    push!(struct_code.args[end].args, :($argname::$typ))
                end
                eval(struct_code)
            end
            const $func_cachename = $dict_type()
            $func1
            $func2
            $func_main
            if !haskey(LocalMemoize.MemoizedFunctions, typeof($funcname))
                LocalMemoize.MemoizedFunctions[typeof($funcname)] = Any[]
            end
            push!(LocalMemoize.MemoizedFunctions[typeof($funcname)], $func_cachename)
            $funcname
        end
    end
    esc(result)
end

end # module
