module LocalMemoize

export @memo, @memoize, get_memos, clear_memos

get_memos(::Type) = error("No memoized cache found")
get_memos(func) = get_memos(typeof(func))
clear_memos(::Type) = error("No memoized cache found")
clear_memos(func) = clear_memos(typeof(func))

macro memo(expr)
    esc(expr)
end

macro memo(args...)
    nothing
end

macro memoize(expr)
    if typeof(expr) != Expr || expr.head != :function
        error("@memoize must be used on a function declaration in traditional syntax.")
    end
    funcdecl = expr.args[1]
    funcname = funcdecl.args[1]
    funcargs = funcdecl.args[2:end]
    funcbody = expr.args[2].args
    memo_argnames = Symbol[]
    memo_argtypes = Symbol[]
    argdef_list = []
    argname_list = Symbol[]
    argtype_list = Symbol[]
    check_memocall = arg -> typeof(arg) == Expr && arg.head == :macrocall &&
        arg.args[1] == Symbol("@memo") && length(arg.args) > 1
    for arg in funcargs
        if check_memocall(arg)
            length(arg.args) != 2 && error("@memo in argument list only must have one and only one argument.")
            argdef = arg.args[2]
        else
            argdef = arg
        end
        if typeof(argdef) == Symbol
            argname = argdef
            argtype = :Any
        elseif typeof(argdef) == Expr && (argdef.head == :(=) || argdef.head == :kw)
            argdef1 = argdef.args[1]
            if typeof(argdef1) == Symbol
                argname = argdef1
                argtype = :Any
            elseif typeof(argdef1) == Expr && argdef1.head == :(::)
                argname = argdef1.args[1]
                argtype = argdef2.args[2]
            end
        elseif typeof(argdef) == Expr && argdef.head == :(::)
            argname = argdef.args[1]
            argtype = argdef.args[2]
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
    length(memo_argnames) == 0 && error("At least one argument should be tagged with @memo.")

    lines = 0
    check_memolist = args -> all(arg -> typeof(arg) == Symbol, args)
    check_assignment = arg -> typeof(arg) == Expr && arg.head == :(=) &&
        typeof(arg.args[1]) == Symbol
    memolist = Symbol[]
    for (i, expression) in enumerate(funcbody)
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
    lines == 0 && error("No @memo found in function body.")

    getsymbol = name -> Symbol(string(gensym(), "_", funcname, "_", name))

    func_cachename = getsymbol("memocache")
    cachename = getsymbol("cache")
    gettype_func_name = getsymbol("gettype")
    func1_name = getsymbol("1")
    func2_name = getsymbol("2")
    cache_struct = getsymbol("cache_t")
    dict = :(Dict{Tuple{$(memo_argtypes...)}, $cache_struct})

    # For getting memoized type
    gettype_func = :(function $gettype_func_name($(argdef_list...)) end)
    # For first time run
    func1 = :(function $func1_name($func_cachename::$dict, $(argdef_list...)) end)
    # For memoized runs
    func2 = :(
        function $func2_name($func_cachename::$dict, $(argdef_list...))
            $cachename = $func_cachename[($(memo_argnames...),)]
        end
    )
    gettype_func_body = gettype_func.args[end].args
    func1_body = func1.args[end].args
    func2_body = func2.args[end].args

    for (i, expression) in enumerate(funcbody)
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

    result = quote
        let gettype_func = $gettype_func
            code_info = code_typed(gettype_func, ($(argtype_list...),))
            types = code_info[1].second
            cache_struct = $(QuoteNode(cache_struct))
            struct_code = :(struct $cache_struct end)
            argnames = $memolist
            for (argname, typ) in zip(argnames, types.types)
                push!(struct_code.args[end].args, :($argname::$typ))
            end
            eval(struct_code)
        end
        $func_cachename = $dict()
        $func1
        $func2
        function $funcname($(argdef_list...))
            haskey($func_cachename, ($(memo_argnames...),)) ?
                $func2_name($func_cachename, $(argname_list...)) :
                $func1_name($func_cachename, $(argname_list...))
        end
        LocalMemoize.get_memos(::Type{typeof($funcname)}) = $func_cachename
        LocalMemoize.clear_memos(::Type{typeof($funcname)}) = begin
            global $func_cachename
            $func_cachename = $dict()
        end
    end
    esc(result)
end

end # module
