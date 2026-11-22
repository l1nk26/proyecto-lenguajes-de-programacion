-- result.lua
-- Convención idiomática de errores en Lua: múltiples retornos (valor, error).
--   éxito: return valor, nil
--   fallo: return nil, mensaje_o_tabla_de_error
-- De esta forma ninguna subrutina necesita lanzar excepciones para errores
-- esperados (división por cero, stack underflow, tipo inválido, etc.).

local M = {}

function M.ok(value)
    return value, nil
end

function M.fail(message)
    return nil, message
end

return M
