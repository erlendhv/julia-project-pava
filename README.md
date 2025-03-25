# julia-project-pava

These functions together implement a sophisticated condition system inspired by Common Lisp, providing flexible mechanisms for detecting, signaling, and handling exceptional situations. The system supports both traditional exception handling (where execution is diverted to an error handler) and more advanced concepts like restarts (which allow the signaler to provide recovery strategies that handlers can invoke).

## HANDLING
Executes the function func in a context where the provided exception handlers are active. Handlers are provided as pairs of ExceptionType => handler_function.
This function establishes a dynamic environment where exceptions can be caught and processed by appropriate handlers. When an exception is thrown within func, handling searches for a matching handler based on the exception type. If found, the handler is called with the exception as its argument.
The handler can:

Return a value (non-nothing), in which case execution stops and that value becomes the return value of the handling call
Return nothing, which causes the exception to continue propagating
Perform a non-local transfer of control using mechanisms like to_escape or invoke restarts

For signals (as opposed to errors), the handler is registered separately to allow the signal to be handled without interrupting normal execution flow.

## ERROR
Signals an exceptional situation that must be handled. If no handler takes action, the program aborts with an error.
This function is used when the current computation cannot proceed and requires intervention. It throws the provided exception, which will propagate up the call stack until it's either caught by a handler or causes the program to terminate.

## TO_ESCAPE
Establishes a named exit point that can be used for non-local transfers of control. The provided function func will be called with an escape function as its argument.
This mechanism allows code to exit from multiple levels of nested function calls in a single step. The escape function, when called, immediately transfers control back to the to_escape call site, optionally returning a value.
This is useful for handling exceptional situations by abandoning the current computation and returning to a known safe point in the program.

## WITH_RESTART
Executes the function func in a context where the provided restarts are available. Restarts are provided as pairs of restart_name => restart_function.
This function establishes a dynamic environment with named recovery strategies (restarts) that can be invoked by exception handlers. Unlike traditional exception handling, restarts allow the code that detects an error to be separate from the code that decides how to recover.
Restarts remain available in the registry even after exceptions are thrown, allowing handlers to find and invoke them.

## INVOKE_RESTART
Invokes a restart with the given name and arguments.
This function searches the restart registry for a restart with the specified name and, if found, calls the associated restart function with the provided arguments. The result of the restart function becomes the return value of the invoke_restart call.
Invoking a restart typically performs a non-local transfer of control back to the point where the restart was established, allowing execution to continue with an alternative strategy.

## AVAILABLE_RESTART
Checks if a restart with the given name is available in the current execution context.
This function allows code to determine whether a specific recovery strategy is available before attempting to invoke it. It returns true if a restart with the given name exists in the registry, and false otherwise.

## SIGNAL
Signals an exceptional situation, allowing handlers to act on it. The signal can be ignored if no handler takes action.
Unlike error, which requires the exceptional situation to be handled, signal allows execution to continue if no handler exists or if handlers choose not to intervene. It directly calls registered signal handlers without disrupting the normal control flow unless a handler explicitly does so.
This is useful for situations where the program can reasonably continue execution even if the exceptional situation is not addressed.

# Condition System Architecture

## Overview

This implementation creates a flexible condition system with separate mechanisms for errors, signals, and restarts. The architecture is inspired by Common Lisp's condition system, fundamentally separating the detection of exceptional situations from their handling strategies.

## Core Components

### 1. Exception Handling

- Establishes a dynamic environment for catching and processing exceptions
- Supports both traditional error handling and signal processing
- Utilizes a dual-registry approach for handling exceptions and signals

### 2. Non-local Exits

- Provides a mechanism for escaping from deeply nested function calls
- Implements controlled jumps in control flow using custom exception types (EscapeException)
- Maintains context identifiers to ensure precise escape point management

### 3. Restart System

- Implements a global registry of recovery strategies
- Allows error-signaling code to define potential recovery mechanisms
- Enables handlers to invoke strategies without knowing implementation details
- Maintains restart availability even after exception propagation

### 4. Signal Mechanism

- Provides lightweight signaling that doesn't necessarily interrupt control flow
- Uses a separate registry for signal handlers
- Allows handling without exception propagation
- Returns values to help callers make informed decisions

## Key Design Decisions

### Global State Management

The implementation leverages global state to:
- Enable handler and restart coordination across different call sites
- Create a consistent environment for handlers
- Facilitate complex error handling scenarios

**Trade-off**: Introduces potential concurrency challenges and increases code complexity.

### Exception Handling Approach

- Uses Julia's built-in exception mechanism for traditional exceptions
- Employs direct handler calls for signals
- Supports different handling behaviors for various exceptional situations

### Exception Type Usage

Utilizes custom exception types (EscapeException, RestartInvocation) to:
- Implement advanced control flow mechanisms
- Leverage Julia's exception handling infrastructure beyond error reporting

## Implementation Challenges

### Signal Continuation

Addressed by:
- Maintaining a separate handler registry for signals
- Returning values that indicate handler invocation
- Allowing handlers to return boolean values for partial handling

### Restart Invocation

Solved through:
- Persistent global restart registry
- Avoiding automatic registry cleanup during exceptions
- Creating unique context identifiers

### Handler Return Values

Designed to distinguish between:
- Handlers that fully resolve exceptions
- Handlers that merely observe exceptional situations

## Design Patterns Employed

- **Command Pattern**: Restart functions encapsulate recoverable actions
- **Chain of Responsibility**: Sequential handler evaluation
- **Observer Pattern**: Signal observation without flow interruption
- **Dynamic Dispatch**: Runtime handler and restart selection

## Conclusion

This architecture provides a powerful, flexible system for managing exceptional situations, extending beyond traditional try/catch mechanisms by separating detection, handling, and recovery aspects of exception management.
