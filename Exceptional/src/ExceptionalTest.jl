# Custom Exception Types
struct DivisionByZero <: Exception end

struct LineEndLimit <: Exception end

# -------------
# Test of ERROR
# -------------

function reciprocal(x)
    x == 0 ? error(DivisionByZero()) : 1 / x
end

# Expected:
# 0.1
reciprocal(10)

# Expected:
# ERROR: DivisionByZero()
reciprocal(0)

# ----------------
# Test of HANDLING
# ----------------

# Expected:
# I saw a division by zero
# ERROR: DivisionByZero()
handling(DivisionByZero =>
    (c) -> println("I saw a division by zero")) do
    reciprocal(0)
end

# Expected:
# I saw a division by zero
# I saw it too
# ERROR: DivisionByZero()
handling(DivisionByZero => (c) -> println("I saw it too")) do
    handling(DivisionByZero => (c) -> println("I saw a division by zero")) do
        reciprocal(0)
    end
end

# ------------------
# Tests of TO_ESCAPE
# ------------------

mystery(n) =
    1 +
    to_escape() do outer
        1 +
        to_escape() do inner
            1 +
            if n == 0
                inner(1)
            elseif n == 1
                outer(1)
            else
                1
            end
        end
    end

# Expected:
# 3
mystery(0)

# Expected:
# 2
mystery(1)

# Expected:
# 4
mystery(2)

# Expected:
# I saw a division by zero
# I saw it too
# "Done"
to_escape() do exit
    handling(DivisionByZero =>
        (c) -> (println("I saw it too"); exit("Done"))) do
        handling(DivisionByZero =>
            (c) -> println("I saw a division by zero")) do
            reciprocal(0)
        end
    end
end

# Expected:
# I saw a division by zero
# "Done"
to_escape() do exit
    handling(DivisionByZero =>
        (c) -> println("I saw it too")) do
        handling(DivisionByZero =>
            (c) -> (println("I saw a division by zero");
            exit("Done"))) do
            reciprocal(0)
        end
    end
end

# ------------------------------------
# Test cases for restart functionality
# ------------------------------------

reciprocal(value) =
    with_restart(:return_zero => () -> 0,
        :return_value => identity,
        :retry_using => reciprocal) do
        value == 0 ?
        error(DivisionByZero()) :
        1 / value
    end

# Expected:
# 0
handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
    reciprocal(0)
end

# Expected:
# 123
handling(DivisionByZero => (c) -> invoke_restart(:return_value, 123)) do
    reciprocal(0)
end

# Expected:
# 0.1
handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
    reciprocal(0)
end

# ---------------------------------
# Test cases for AVAILABLE_RESTARTS
# ---------------------------------

# Expected:
# 0
handling(DivisionByZero =>
    (c) -> for restart in (:return_one, :return_zero, :die_horribly)
        if available_restart(restart)
            return (invoke_restart(restart))
        end
    end) do
    reciprocal(0)
end

infinity() =
    with_restart(:just_do_it => () -> 1 / 0) do
        reciprocal(0)
    end

# Expected:
# 0
handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
    infinity()
end

# Expected:
# 1
handling(DivisionByZero => (c) -> invoke_restart(:return_value, 1)) do
    infinity()
end

# Expected:
# 0.1
handling(DivisionByZero => (c) -> invoke_restart(:retry_using, 10)) do
    infinity()
end

# Expected:
# Inf
handling(DivisionByZero => (c) -> invoke_restart(:just_do_it)) do
    infinity()
end

# ------------------------------------------------------
# Test cases for print_line with ERROR instead of SIGNAL
# ------------------------------------------------------

print_line(str, line_end=20) =
    let col = 0
        for c in str
            print(c)
            col += 1
            if col == line_end
                error(LineEndLimit())
                col = 0
            end
        end
    end

# Expected:
# Hi, everybody! How a
to_escape() do exit
    handling(LineEndLimit => (c) -> exit()) do
        print_line("Hi, everybody! How are you feeling today?")
    end
end

# Expected:
# Hi, everybody! How a
# ERROR: LineEndLimit()
# Stacktrace: 
# ...
handling(LineEndLimit => (c) -> println()) do
    print_line("Hi, everybody! How are you feeling today?")
end

# -------------------------
# Test cases for SIGNAL
# -------------------------

print_line(str, line_end=20) =
    let col = 0
        for c in str
            print(c)
            col += 1
            if col == line_end
                signal(LineEndLimit())
                col = 0
            end
        end
    end

# Expected:
# Hi, everybody! How are you feeling today?
print_line("Hi, everybody! How are you feeling today?")

# Expected:
# Hi, everybody! How a
to_escape() do exit
    handling(LineEndLimit => (c) -> exit()) do
        print_line("Hi, everybody! How are you feeling today?")
    end
end

# Expected:
# Hi, everybody! How a
# re you feeling today
# ?
handling(LineEndLimit => (c) -> println()) do
    print_line("Hi, everybody! How are you feeling today?")
end
