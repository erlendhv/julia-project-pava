# GLOBAL VARIABLES AND EXCEPTIONS

# Track state and maintain registries for handlers and restarts
const restart_registry = Dict{Symbol,Vector{Tuple{Symbol,Function}}}()
# Global registry for signal handlers
const signal_handlers = Dict{Type,Vector{Function}}()

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

# ---------
# TO_ESCAPE
# ---------
# Create a non-local exit point with controlled value return
function to_escape(func)
    context_id = gensym("escape_context")
    escape_func = (value = nothing) -> throw(EscapeException(context_id, value))
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
