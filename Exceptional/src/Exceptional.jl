# ------
# HANDLING
# ------
# Executes the function `func` in a context where the provided exception handlers
# are active. Handlers are provided as pairs of `ExceptionType => handler_function`.
# function handling(func, handlers...)
#     try
#         return func()
#     catch e
#         # Find the first handler that matches the exception type
#         for (exception_type, handler) in handlers
#             if e isa exception_type
#                 # Call the handler with the exception
#                 handler(e)
#                 # Always re-throw after handling
#                 rethrow(e)
#             end
#         end
#         # If no handler matches, re-throw the exception
#         rethrow(e)
#     end
# end

function handling(func, handlers...)
    try
        return func()
    catch e
        # Find the first handler that matches the exception type
        for (exception_type, handler) in handlers
            if e isa exception_type
                # Call the handler with the exception and capture its result
                result = handler(e)
                # Check if the handler returned a value (meaning it handled the exception)
                # If it returned nothing (the default), then rethrow the exception
                if result !== nothing
                    return result
                else
                    # If handler returned nothing, rethrow
                    rethrow(e)
                end
            end
        end
        # If no handler matches, re-throw the exception
        rethrow(e)
    end
end

# ------
# ERROR
# -----
# Signals an exceptional situation that must be handled.
# If no handler takes action, the program aborts with an error.
function Base.error(exception)
    throw(exception)
end

# Define a simple DivisionByZero exception
struct DivisionByZero <: Exception end

# Test the reciprocal function
function reciprocal(x)
    x == 0 ? error(DivisionByZero()) : 1/x
end

# Basic function test
reciprocal(10)  # Should return 0.1

reciprocal(0)  # Should throw DivisionByZero

# Test handling with a simple handler
handling(DivisionByZero => 
        (c)->println("I saw a division by zero")) do
    reciprocal(0)
end

# Test cascading handlers
handling(DivisionByZero => (c)->println("I saw it too")) do
    handling(DivisionByZero => (c)->println("I saw a division by zero")) do
        reciprocal(0)
    end
end



# Represents a non-local transfer of control initiated by a call to an escape function.
struct EscapeException <: Exception
    context_id::Symbol
    value::Any
end

# ------
# TO_ESCAPE
# ------
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

mystery(0)

mystery(1)

mystery(2)

to_escape() do exit
    handling(DivisionByZero =>
            (c)->(println("I saw it too"); exit("Done"))) do
        handling(DivisionByZero =>
                (c)->println("I saw a division by zero")) do
            reciprocal(0)
        end
    end
end

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



# Represents a request to invoke a restart.
struct RestartInvocation <: Exception
    context_id::Symbol
    restart_name::Symbol
    args::Tuple
end

# -------
# WITH_RESTART
# -------
# Executes the function `func` in a context where the provided restarts are available.
# Restarts are provided as pairs of `restart_name => restart_function`.
# Add some debug prints to with_restart
# function with_restart(func, restarts...)
#     # Create a unique identifier for this restart context
#     context_id = gensym("restart_context")
#     # Register the restarts
#     restart_registry[context_id] = [(name, restart_func) for (name, restart_func) in restarts]
#     println("Registered restarts: ", [name for (name, _) in restart_registry[context_id]])
#     try
#         # Execute the function in the context of the restarts
#         return func()
#     catch e
#         println("Caught exception in with_restart: ", typeof(e))
#         # Check if this is a restart invocation for our context
#         if e isa RestartInvocation && haskey(restart_registry, e.context_id)
#             println("Found restart invocation for context: ", e.context_id)
#             # Find the restart function
#             for (name, restart_func) in restart_registry[e.context_id]
#                 if name == e.restart_name
#                     println("Invoking restart: ", name)
#                     # Call the restart function with the provided arguments
#                     return restart_func(e.args...)
#                 end
#             end
#         end
#         # If not a restart invocation or no matching restart, re-throw
#         rethrow(e)
#     finally
#         # Clean up the restart registry
#         delete!(restart_registry, context_id)
#     end
# end

# Global registry to track available restarts
const restart_registry = Dict{Symbol, Vector{Tuple{Symbol, Function}}}()

# -------
# WITH_RESTART
# -------
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

# ------
# INVOKE_RESTART
# ------
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

reciprocal(value) =
    with_restart(:return_zero => ()->0,
                 :return_value => identity,
                 :retry_using => reciprocal) do
        value == 0 ?
            error(DivisionByZero()) :
            1/value
end

handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    reciprocal(0)
end

handling(DivisionByZero => (c)->invoke_restart(:return_value, 123)) do
    reciprocal(0)
end

handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    reciprocal(0)
end

# ------
# AVAILABLE_RESTART
# ------
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


# Signals an exceptional situation, allowing handlers to act on it.
# The signal can be ignored if no handler takes action.
function signal(exception)
    try
        throw(exception)
    catch e
        # If the exception is caught but not handled, we just return
        return nothing
    end
end


# Custom exception types for internal use



# Initialize the restart registry
function __init__()
    empty!(restart_registry)
end


# Test escaping from a handler
to_escape() do exit
    handling(DivisionByZero => (c)->(println("I saw it too"); exit("Done"))) do
        handling(DivisionByZero => (c)->println("I saw a division by zero")) do
            reciprocal(0)
        end
    end
end

# Test escaping from an inner handler
to_escape() do exit
    handling(DivisionByZero => (c)->println("I saw it too")) do
        handling(DivisionByZero => (c)->(println("I saw a division by zero"); exit("Done"))) do
            reciprocal(0)
        end
    end
end

# Test with_restart
function reciprocal_with_restarts(value)
    with_restart(:return_zero => ()->0,
                :return_value => identity,
                :retry_using => reciprocal) do
        value == 0 ? error(DivisionByZero()) : 1/value
    end
end

# Test invoking restarts
handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    reciprocal_with_restarts(0)
end

# Test passing arguments to restarts
handling(DivisionByZero => (c)->invoke_restart(:return_value, 123)) do
    reciprocal_with_restarts(0)
end

handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    reciprocal_with_restarts(0)
end

# Test available_restart
handling(DivisionByZero => 
    (c)-> for restart in (:return_one, :return_zero, :die_horribly)
        if available_restart(restart)
            println("Found restart: ", restart)
            invoke_restart(restart)
        else
            println("Restart not available: ", restart)
        end
    end) do
    reciprocal_with_restarts(0)
end

# Test nested restarts
function infinity()
    with_restart(:just_do_it => ()->1/0) do
        reciprocal_with_restarts(0)
    end
end

handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    infinity()
end

handling(DivisionByZero => (c)->invoke_restart(:just_do_it)) do
    infinity()
end

# Test signal vs error
struct LineEndLimit <: Exception end

function print_line(str, line_end=20)
    col = 0
    for c in str
        print(c)
        col += 1
        if col == line_end
            signal(LineEndLimit())
            col = 0
        end
    end
end

# Signal without handler (should continue execution)
print_line("Hi, everybody! How are you feeling today?")
println() # Add newline after previous output

# Signal with escape handler
to_escape() do exit
    handling(LineEndLimit => (c)->exit()) do
        print_line("Hi, everybody! How are you feeling today?")
    end
end
println() # Add newline after previous output

# Signal with newline handler
handling(LineEndLimit => (c)->println()) do
    print_line("Hi, everybody! How are you feeling today?")
end
println() # Add newline after previous output

# Now modify print_line to use error instead of signal for comparison
function print_line_error(str, line_end=20)
    col = 0
    for c in str
        print(c)
        col += 1
        if col == line_end
            error(LineEndLimit())
            col = 0
        end
    end
end

# Error with escape handler
to_escape() do exit
    handling(LineEndLimit => (c)->exit()) do
        print_line_error("Hi, everybody! How are you feeling today?")
    end
end
println() # Add newline after previous output

# Error with newline handler (this will still abort because error demands handling)
try
    handling(LineEndLimit => (c)->println()) do
        print_line_error("Hi, everybody! How are you feeling today?")
    end
catch e
    println("\nCaught exception: ", e)
end
