-- evaluator.lua
-- Máquina de pila (RPN). La pila y el entorno se pasan explícitamente a cada
-- subrutina para hacer evidente en el código el paso de parámetros y la
-- mutabilidad de las tablas de Lua.

local Result = require("result")

local M = {}

--- Evalúa una lista de tokens.
--- @param tokens table
--- @param stack table pila de valores (Value)
--- @param env table entorno actual
--- @return table|nil valor_tope_o_nil
--- @return table|nil error_o_nil
function M.eval(tokens, stack, env)
    -- TODO: recorrer tokens y despachar según su clase:
    --   number  -> push_number
    --   ident   -> push_variable_get
    --   operator-> apply_operator
    --   keyword -> begin / end / vars / =
    return Result.fail("TODO: evaluator.eval no implementado")
end

function M.push_number(lexeme, stack)
    -- TODO: convertir el lexema en Value.int o Value.float y apilarlo
    return Result.fail("TODO: evaluator.push_number no implementado")
end

function M.push_variable(name, stack, env)
    -- TODO: consultar env y apilar el valor (error si no existe)
    return Result.fail("TODO: evaluator.push_variable no implementado")
end

function M.apply_operator(op, stack)
    -- TODO:
    --  - verificar profundidad de pila -> Errors.Code.STACK_UNDERFLOW
    --  - verificar tipos -> Errors.Code.TYPE_MISMATCH
    --  - + - * / == != < >  (división por cero -> DIVISION_BY_ZERO)
    return Result.fail("TODO: evaluator.apply_operator no implementado")
end

function M.assign(name, stack, env)
    -- TODO: desapilar un valor y escribirlo en el entorno
    return Result.fail("TODO: evaluator.assign no implementado")
end

return M
