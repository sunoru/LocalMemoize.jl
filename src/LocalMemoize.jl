module LocalMemoize

export @memo, @memoize

macro memo(expr)
    esc(expr)
end

macro memoize(args...)
    length(args) > 2 && error("@memoize supports at most 2 arguments.")
    if length(args) == 1
        expr = args[1]
        dict = :(ObjectIdDict)
    else
        expr = args[2]
        dict = args[1]
    end
    if typeof(expr) != Expr || !(expr.head == :function || expr.head == :(=) && expr.args[1].head == :call)
        error("@memoize must be used on a function declaration.")
    end
    funcdecl = expr.args[1]
    funcname = funcdecl.args[1]
    funcargs = funcdecl.args[2:end]
    funcbody = expr.args[2].args
    memoargs = Symbol[]
    argdef_list = []
    argname_list = []
    check_memocall = arg -> typeof(arg) == Expr && arg.head == :macrocall &&
        arg.args[1] == Symbol("@memo") && length(arg.args) == 2
    for arg in funcargs
        if check_memocall(arg)
            argdef = arg.args[2]
        else
            argdef = arg
        end
        if typeof(argdef) == Symbol
            argname = argdef
        elseif typeof(argdef) == Expr && arg.args[2].head == :(::)
            argname = arg.args[2].args[1]
        end
        if check_memocall(arg)
            push!(memoargs, argname)
        end
        push!(argdef_list, argdef)
        push!(argname_list, argname)
    end
    func_cachename = Symbol(string(gensym(), "_", funcname, "_memocache"))
    cachename = Symbol(string(gensym(), "_", funcname, "_cache"))
    func1_name = Symbol(string(gensym(), "_", funcname, "_1"))
    func2_name = Symbol(string(gensym(), "_", funcname, "_2"))

    func1 = :(
        function $func1_name($(argdef_list...))
            $cachename = $func_cachename[$(memoargs...)] = Dict{Symbol, Any}()
        end
    ) # for first time run
    func2 = :(
        function $func2_name($(argdef_list...))
            $cachename = $func_cachename[$(memoargs...)]
        end
    ) # for memoized runs
    func1_body = func1.args[end].args
    func2_body = func2.args[end].args
    lines = 0
    check_assignment = arg -> typeof(arg) == Expr && arg.head == :(=) &&
        typeof(arg.args[1]) == Symbol
    for (i, expression) in enumerate(funcbody)
        if check_memocall(expression)
            assignment = expression.args[2]
            check_assignment(expression.args[2]) || error("@memo in body must be used on an assignment")
            lines = i
        end
    end
    lines == 0 && error("No @memo found in function body.")
    for (i, expression) in enumerate(funcbody)
        if i > lines
            push!(func1_body, expression)
            push!(func2_body, expression)
            continue
        end
        if check_memocall(expression)
            push!(func1_body, expression.args[2])
            argname = expression.args[2].args[1]
            push!(func1_body, :(
                $cachename[$(QuoteNode(argname))] = $argname
            ))
            push!(func2_body, :(
                $argname = $cachename[$(QuoteNode(argname))]
            ))
        else
            push!(func1_body, expression)
        end
    end

    result = quote
        $func_cachename = $dict()
        $func1
        $func2
        function $funcname($(argdef_list...))
            haskey($func_cachename, $(memoargs...)) ? $func2_name($(argname_list...)) : $func1_name($(argname_list...))
        end
    end
    println(result)
    esc(result)
end

end # module
