-- value.lua
-- Representación de los valores que viajan en la pila.
-- Lua no posee enums algebraicos: se usa una "tagged union" (tabla con un
-- campo `kind` que identifica la variante: int, float, bool o name).
--
-- Los valores se tratan como inmutables: una vez creados nunca se modifican.
-- Por eso es seguro que la pila y el entorno compartan la misma tabla.

local M = {}

M.Kind = {
    INT = "int",
    FLOAT = "float",
    BOOL = "bool",
    NAME = "name",
}

-- Metatabla compartida por todos los valores. Define __tostring para que
-- tostring(v) y print(v) muestren el valor en lugar de "table: 0x...".
local ValueMeta = {}

local function tagged(kind, value)
    return setmetatable({ kind = kind, value = value }, ValueMeta)
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

-- Variante `name`: la apila un identificador como `x`. Guarda el nombre
-- (lo necesita la asignación `=`) y el valor que tenía la variable en el
-- momento de apilarse, o nil si la variable todavía no existe.
function M.name(identifier, current)
    assert(type(identifier) == "string", "value.name: se esperaba un texto")
    return setmetatable({ kind = M.Kind.NAME, name = identifier, value = current }, ValueMeta)
end

function M.is_number(v)
    return v ~= nil
        and (v.kind == M.Kind.INT or v.kind == M.Kind.FLOAT)
end

function M.is_bool(v)
    return v ~= nil and v.kind == M.Kind.BOOL
end

function M.is_name(v)
    return v ~= nil and v.kind == M.Kind.NAME
end

function M.type_name(v)
    return (v ~= nil and v.kind) or "desconocido"
end

-- Formato de salida: 7, 3.5, 4.0, true, false.
function M.tostring(v)
    if v == nil then return "nil" end
    if v.kind == M.Kind.INT then
        return string.format("%d", v.value)
    end
    if v.kind == M.Kind.NAME then
        if v.value == nil then return v.name end
        return M.tostring(v.value)
    end
    -- float: Lua escribe 3.5 o 4.0 (siempre con parte decimal)
    -- bool: true o false
    return tostring(v.value)
end

ValueMeta.__tostring = M.tostring

return M
