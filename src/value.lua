-- value.lua
-- Representación de los valores que viajan en la pila.
-- Lua no posee enums algebraicos: se usa una "tagged union" (tabla con un
-- campo `kind` que identifica la variante: int, float o bool).

local M = {}

M.Kind = {
    INT = "int",
    FLOAT = "float",
    BOOL = "bool",
}

local function tagged(kind, value)
    return { kind = kind, value = value }
end

function M.int(n)
    assert(math.type(n) == "integer", "value.int: se esperaba un entero")
    return tagged(M.Kind.INT, n)
end

function M.float(n)
    assert(type(n) == "number", "value.float: se esperaba un número")
    return tagged(M.Kind.FLOAT, n + 0.0)
end

function M.bool(b)
    assert(type(b) == "boolean", "value.bool: se esperaba un booleano")
    return tagged(M.Kind.BOOL, b)
end

function M.is_number(v)
    return v ~= nil
        and (v.kind == M.Kind.INT or v.kind == M.Kind.FLOAT)
end

function M.is_bool(v)
    return v ~= nil and v.kind == M.Kind.BOOL
end

function M.type_name(v)
    return (v ~= nil and v.kind) or "desconocido"
end

function M.tostring(v)
    -- TODO: definir el formato de salida definitivo (5, 2.5, true, ...)
    if v == nil then return "nil" end
    return tostring(v.value)
end

return M
