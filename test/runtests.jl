using LocalMemoize
using Base.Test

@memoize function test_simple(@memo(x), @memo(y), z=8)
    println("First run: $((x, y, z))")
    c = 8x
    @memo a = c + 3
    @memo b = x * 2
    @memo d = a * b * y
    return a + b + d + z
end
@test test_simple(3, 5, 8) == test_simple(3, 5)
@test test_simple(4, 5, 9) != test_simple(3, 5, 9)
cache = get_memos(test_simple)[1]
cache_struct = typeof(cache).parameters[2]
@test fieldnames(cache_struct) == [:a, :b, :d]
@test sort([keys(cache)...]) == [(3, 5), (4, 5)]
@test cache[(3, 5)] == cache_struct(27, 6, 810)
@test cache[(4, 5)] == cache_struct(35, 8, 1400)
@test [fieldtype(cache_struct, i) for i in 1:3] == [Any, Any, Any]
clear_memos(test_simple)
cache = get_memos(test_simple)[1]
@test length(keys(cache)) == 0


@memoize function test_static_type(@memo(x::Float64), y::Float64)
    println("First run: $((x, y))")
    c = x / 2
    @memo a = c + 3
    b = x * 2
    @memo b
    return a * b * y
end
@test test_static_type(1.0, 2.0) == test_static_type(1.0, 2.0)
@test test_static_type(1.0, 2.0) != test_static_type(3.0, 2.0)
cache = get_memos(test_static_type)[1]
cache_struct = typeof(cache).parameters[2]
@test fieldnames(cache_struct) == [:a, :b]
@test sort([keys(cache)...]) == [(1.0,), (3.0,)]
@test cache[(1.0,)] == cache_struct(3.5, 2.0)
@test cache[(3.0,)] == cache_struct(4.5, 6.0)
@test [fieldtype(cache_struct, i) for i in 1:2] == [Float64, Float64]
clear_memos(test_static_type)
cache = get_memos(test_static_type)[1]
@test length(keys(cache)) == 0

@memoize function test_dispatch(@memo(x::Float64), y::Float64)
    @memo a = 2x
    a * y
end
@memoize function test_dispatch(@memo(x::Int64), y::Float64)
    @memo a = 3x
    a * y
end
@test test_dispatch(1.0, 2.0) == test_dispatch(1.0, 2.0)
@test test_dispatch(Int64(1), 2.0) == test_dispatch(Int64(1), 2.0)

@memoize test_return(x::Int64) = x < 3 ? 1 : (test_return(x - 1) + test_return(x - 2))
@test test_return(Int64(5)) == 5
@test test_return(Int64(100)) == 3736710778780434371
