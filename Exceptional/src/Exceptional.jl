# GLOBAL VARIABLES AND EXCEPTIONS

# Track state and maintain registries for handlers and restarts
global in_handler_context = false
const restart_registry = Dict{Symbol, Vector{Tuple{Symbol, Function}}}()
# Global registry for signal handlers
global signal_handlers = Dict{Type, Vector{Function}}()

# Custom Exception Types
struct DivisionByZero <: Exception end

struct LineEndLimit <: Exception
end

# Represents a non-local control transfer initiated by an escape function.
# Tracks a unique context identifier and an optional return value.
struct EscapeException <: Exception
    context_id::Symbol
    value::Any
end

# Represents a request to invoke a specific restart strategy.
# Includes context identifier, restart name, and arguments.
struct RestartInvocation <: Exception
    context_id::Symbol
    restart_name::Symbol
    args::Tuple
end

# ----------------
# Helper functions
# ----------------

# Register a new signal handler for a specific exception type
function register_signal_handler(signal_type, handler)
    if !haskey(signal_handlers, signal_type)
        signal_handlers[signal_type] = Function[]
    end
    push!(signal_handlers[signal_type], handler)
    return length(signal_handlers[signal_type])
end

# Remove a specific signal handler from the registry
function remove_signal_handler(signal_type, handler_id)
    if haskey(signal_handlers, signal_type) && handler_id <= length(signal_handlers[signal_type])
        deleteat!(signal_handlers[signal_type], handler_id)
    end
end

# --------
# HANDLING
# --------
# Flexible handling mechanism for exceptions and signals with nested support
function handling(func, handlers...)
    handler_ids = []
    for (exception_type, handler) in handlers
        wrapped_handler = (e) -> begin
            result = handler(e)
            return result !== nothing
        end
        id = register_signal_handler(exception_type, wrapped_handler)
        push!(handler_ids, (exception_type, id))
    end
    try
        return func()
    catch e
        for (exception_type, handler) in handlers
            if e isa exception_type
                result = handler(e)
                if result !== nothing
                    return result
                else
                    rethrow(e)
                end
            end
        end
        rethrow(e)
    finally
        for (exception_type, id) in handler_ids
            remove_signal_handler(exception_type, id)
        end
    end
end

# -----
# ERROR
# -----
# Throw an exception that must be handled
function Base.error(exception)
    throw(exception)
end

# -------------
# Test of ERROR
# -------------

function reciprocal(x)
    x == 0 ? error(DivisionByZero()) : 1/x
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
        (c)->println("I saw a division by zero")) do
    reciprocal(0)
end

# Expected:
# I saw a division by zero
# I saw it too
# ERROR: DivisionByZero()
handling(DivisionByZero => (c)->println("I saw it too")) do
    handling(DivisionByZero => (c)->println("I saw a division by zero")) do
        reciprocal(0)
    end
end




# ---------
# TO_ESCAPE
# ---------
# Create a non-local exit point with controlled value return
function to_escape(func)
    context_id = gensym("escape_context")
    escape_func = (value=nothing) -> throw(EscapeException(context_id, value))
    try
        return func(escape_func)
    catch e
        if e isa EscapeException && e.context_id == context_id
            return e.value
        else
            rethrow(e)
        end
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
            (c)->(println("I saw it too"); exit("Done"))) do
        handling(DivisionByZero =>
                (c)->println("I saw a division by zero")) do
            reciprocal(0)
        end
    end
end

# Expected:
# I saw a division by zero
# "Done"
to_escape() do exit
    handling(DivisionByZero =>
            (c)->println("I saw it too")) do
        handling(DivisionByZero =>
                (c)->(println("I saw a division by zero");
                    exit("Done"))) do
            reciprocal(0)
        end
    end
end


# ------------
# WITH_RESTART
# ------------
# Create a context with available restart strategies
function with_restart(func, restarts...)
    context_id = gensym("restart_context")
    restart_registry[context_id] = [(name, restart_func) for (name, restart_func) in restarts]
    try
        return func()
    catch e
        rethrow(e)
    end
end

# --------------
# INVOKE_RESTART
# --------------
# Invoke a specific restart strategy from available restarts
function invoke_restart(name, args...)
    for (context_id, restarts) in restart_registry
        for (restart_name, restart_func) in restarts
            if restart_name == name
                return restart_func(args...)
            end
        end
    end
    throw(ArgumentError("No restart named $name is available"))
end

# ------------------------------------
# Test cases for restart functionality
# ------------------------------------

reciprocal(value) =
    with_restart(:return_zero => ()->0,
                 :return_value => identity,
                 :retry_using => reciprocal) do
        value == 0 ?
            error(DivisionByZero()) :
            1/value
end

# Expected:
# 0
handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    reciprocal(0)
end

# Expected:
# 123
handling(DivisionByZero => (c)->invoke_restart(:return_value, 123)) do
    reciprocal(0)
end

# Expected:
# 0.1
handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    reciprocal(0)
end


# -----------------
# AVAILABLE_RESTART
# -----------------
# Checks if a restart with the given name is available in the current execution context.
function available_restart(name)
    for (context_id, restarts) in restart_registry
        for (restart_name, _) in restarts
            if restart_name == name
                return true
            end
        end
    end
    return false
end

# ---------------------------------
# Test cases for AVAILABLE_RESTARTS
# ---------------------------------

# TODO: added an explicit return compared to the test from the project description
#       to match out code. Needs to either be this way or to rewrite previous code
handling(DivisionByZero =>
        (c)-> for restart in (:return_one, :return_zero, :die_horribly)
                if available_restart(restart)
                    return(invoke_restart(restart))
                end
            end) do
    reciprocal(0)
end

infinity() =
    with_restart(:just_do_it => ()->1/0) do
        reciprocal(0)
    end

# Expected:
# 0
handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    infinity()
end

# Expected:
# 1
handling(DivisionByZero => (c)->invoke_restart(:return_value, 1)) do
    infinity()
end

# Expected:
# 0.1
handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    infinity()
end

# Expected:
# Inf
handling(DivisionByZero => (c)->invoke_restart(:just_do_it)) do
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
    handling(LineEndLimit => (c)->exit()) do
        print_line("Hi, everybody! How are you feeling today?")
    end
end

# Expected:
# Hi, everybody! How a
# ERROR: LineEndLimit()
# Stacktrace: 
# ...
handling(LineEndLimit => (c)->println()) do
    print_line("Hi, everybody! How are you feeling today?")
end


# -------
# SIGNAL
# -------
# Signal an exceptional situation with flexible handler processing
function signal(exception)
    if haskey(signal_handlers, typeof(exception))
        for handler in signal_handlers[typeof(exception)]
            result = handler(exception)
            if result === true
                return true
            end
        end
    end
    return false
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
    handling(LineEndLimit => (c)->exit()) do
        print_line("Hi, everybody! How are you feeling today?")
    end
end

# Expected:
# Hi, everybody! How a
# re you feeling today
# ?
handling(LineEndLimit => (c)->println()) do
    print_line("Hi, everybody! How are you feeling today?")
end
