# GLOBAL VARIABLES AND EXCEPTIONS

# Global flag to track if we're inside a handling block
global in_handler_context = false
# Global registry to track available restarts
const restart_registry = Dict{Symbol, Vector{Tuple{Symbol, Function}}}()
# Define a simple DivisionByZero exception
struct DivisionByZero <: Exception end
# Represents a non-local transfer of control initiated by a call to an escape function.
struct EscapeException <: Exception
    context_id::Symbol
    value::Any
end
# Represents a request to invoke a restart.
struct RestartInvocation <: Exception
    context_id::Symbol
    restart_name::Symbol
    args::Tuple
end
struct LineEndLimit <: Exception
end
# Global registry for signal handlers
global signal_handlers = Dict{Type, Vector{Function}}()

# Register a signal handler
function register_signal_handler(signal_type, handler)
    if !haskey(signal_handlers, signal_type)
        signal_handlers[signal_type] = Function[]
    end
    push!(signal_handlers[signal_type], handler)
    return length(signal_handlers[signal_type])
end

# Remove a signal handler
function remove_signal_handler(signal_type, handler_id)
    if haskey(signal_handlers, signal_type) && handler_id <= length(signal_handlers[signal_type])
        deleteat!(signal_handlers[signal_type], handler_id)
    end
end

# --------
# HANDLING
# --------
# Modified handling to register signal handlers
function handling(func, handlers...)
    # Register handlers for signals
    handler_ids = []
    for (exception_type, handler) in handlers
        # For signals, register a handler that returns true if the handler returns non-nothing
        wrapped_handler = (e) -> begin
            result = handler(e)
            return result !== nothing
        end
        id = register_signal_handler(exception_type, wrapped_handler)
        push!(handler_ids, (exception_type, id))
    end
    try
        # Execute the function with the registered signal handlers
        return func()
    catch e
        # Traditional exception handling
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
        # Clean up signal handlers
        for (exception_type, id) in handler_ids
            remove_signal_handler(exception_type, id)
        end
    end
end

# -----
# ERROR
# -----
# Signals an exceptional situation that must be handled.
# If no handler takes action, the program aborts with an error.
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
#Establishes a named exit point that can be used for non-local transfers of control.
#The provided function `func` will be called with an escape function as its argument.
function to_escape(func)
    # Create a unique context identifier for this escape point
    context_id = gensym("escape_context")
    # Define the escape function
    escape_func = (value=nothing) -> throw(EscapeException(context_id, value))
    try
        # Call the function with the escape function as argument
        return func(escape_func)
    catch e
        # Check if this is an escape exception for our context
        if e isa EscapeException && e.context_id == context_id
            # If so, return the value that was passed to the escape function
            return e.value
        else
            # Otherwise, re-throw the exception
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
function with_restart(func, restarts...)
    # Create a unique identifier for this restart context
    context_id = gensym("restart_context")
    # Register the restarts
    restart_registry[context_id] = [(name, restart_func) for (name, restart_func) in restarts]
    # Print the restarts for debugging
    println("Registered restarts for context ", context_id, ": ", [name for (name, _) in restart_registry[context_id]])
    try
        # Execute the function in the context of the restarts
        return func()
    catch e
        # Just rethrow the exception - don't clean up
        rethrow(e)
    end
    # No cleanup! Leave the restarts in the registry
    # This means they'll be available to handlers even after exceptions propagate
end

# --------------
# INVOKE_RESTART
# --------------
function invoke_restart(name, args...)
    println("Looking for restart: ", name)
    println("Available contexts: ", keys(restart_registry))
    # Find the restart function
    for (context_id, restarts) in restart_registry
        println("Context ", context_id, " has restarts: ", [r[1] for r in restarts])
        for (restart_name, restart_func) in restarts
            if restart_name == name
                println("Found restart ", name, " in context ", context_id)
                # Call the restart function with the provided arguments
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



# ------------------
# Test cases for print_line with ERROR instead of SIGNAL
# ------------------

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
# Signals an exceptional situation, allowing handlers to act on it.
# The signal can be ignored if no handler takes action.
# Signal function that calls handlers directly
function signal(exception)
    # Check if we have handlers for this exception type
    if haskey(signal_handlers, typeof(exception))
        # Call each handler until one returns true (fully handled)
        for handler in signal_handlers[typeof(exception)]
            result = handler(exception)
            if result === true
                # Handler fully handled the signal
                return true
            end
        end
    end
    # No handlers or none fully handled it
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
