-- errors.lua
-- Errores controlados del evaluador. Se representan como tablas (registros)
-- con código, mensaje y detalle opcional.

local M = {}

M.Code = {
    STACK_UNDERFLOW    = "stack_underflow",
    DIVISION_BY_ZERO   = "division_by_zero",
    TYPE_MISMATCH      = "type_mismatch",
    INVALID_TOKEN      = "invalid_token",
    UNDEFINED_VARIABLE = "undefined_variable",
}

function M.new(code, message, detail)
    return {
        code = code,
        message = message,
        detail = detail,
    }
end

function M.format(err)
    if type(err) ~= "table" then
        return tostring(err)
    end
    return string.format("[%s] %s", err.code or "?", err.message or "")
end

return M
