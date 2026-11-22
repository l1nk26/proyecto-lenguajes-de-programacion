-- errors.lua
-- Errores controlados del evaluador. Se representan como tablas (registros)
-- con código, mensaje y detalle opcional (el lexema que causó el error).

local M = {}

M.Code = {
    STACK_UNDERFLOW     = "stack_underflow",
    DIVISION_BY_ZERO    = "division_by_zero",
    ARITHMETIC_OVERFLOW = "arithmetic_overflow",
    TYPE_MISMATCH       = "type_mismatch",
    INVALID_TOKEN       = "invalid_token",
    UNDEFINED_VARIABLE  = "undefined_variable",
    INVALID_ASSIGNMENT  = "invalid_assignment",
    NO_OPEN_BLOCK       = "no_open_block",
    MAX_DEPTH_EXCEEDED  = "max_depth_exceeded",
    INTERNAL_ERROR      = "internal_error",
}

local ErrorMeta = {}

function M.new(code, message, detail)
    return setmetatable({
        code = code,
        message = message,
        detail = detail,
    }, ErrorMeta)
end

function M.format(err)
    if type(err) ~= "table" then
        return tostring(err)
    end
    return string.format("[%s] %s", err.code or "?", err.message or "")
end

ErrorMeta.__tostring = M.format

return M
