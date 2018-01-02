using LocalMemoize
using Base.Test

@memoize function test_simple(@memo(x), y)
    println("First run")
    c = 8x
    @memo a = c + 3
    @memo b = x * 2
    return a * b * y
end

@test test_simple(3, 5) == test_simple(3, 5)
@test test_simple(4, 5) != test_simple(3, 5)
