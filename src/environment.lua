-- environment.lua
-- Tabla de símbolos con alcance léxico. Cada entorno apunta a su padre;
-- `begin` crea un hijo y `end` vuelve al padre (shadowing sin sobrescribir
-- permanentemente las variables globales).
--
-- En Lua las tablas se pasan como valores de referencia: el evaluador recibe
-- el entorno explícitamente y puede mutar sus campos.

local Result = require("result")
local Errors = require("errors")

local M = {}

-- depth: 0 para el entorno global, 1 para el primer bloque, etc.
function M.new(parent)
    return {
        parent = parent,
        vars = {},
        depth = parent and (parent.depth + 1) or 0,
    }
end

local function undefined(name)
    return Result.fail(Errors.new(
        Errors.Code.UNDEFINED_VARIABLE,
        string.format("la variable '%s' no está definida", name),
        name))
end

-- Busca `name` desde el entorno actual hacia el global.
-- Devuelve el valor y el entorno donde se encontró, o nil si no existe.
function M.lookup(env, name)
    local scope = env
    while scope ~= nil do
        local value = scope.vars[name]
        if value ~= nil then
            return value, scope
        end
        scope = scope.parent
    end
    return nil, nil
end

-- Contrato para todas las subrutinas: valor, nil | nil, error

function M.get(env, name)
    local value = M.lookup(env, name)
    if value == nil then
        return undefined(name)
    end
    return Result.ok(value)
end

-- Crea o actualiza la variable en el ámbito actual. Es la operación que usa
-- `=`: dentro de un bloque crea una variable local que oculta a la global.
function M.define(env, name, value)
    env.vars[name] = value
    return Result.ok(value)
end

-- Actualiza la variable en el ámbito donde ya existe, aunque sea un ámbito
-- exterior. El evaluador no la usa para `=` a propósito: si lo hiciera, una
-- asignación dentro de un bloque modificaría la variable global.
function M.set(env, name, value)
    local _, scope = M.lookup(env, name)
    if scope == nil then
        return undefined(name)
    end
    scope.vars[name] = value
    return Result.ok(value)
end

function M.open(current)
    return Result.ok(M.new(current))
end

function M.close(current)
    if current.parent == nil then
        return Result.fail(Errors.new(
            Errors.Code.NO_OPEN_BLOCK,
            "'end' sin 'begin': no hay ningún bloque abierto",
            "end"))
    end
    -- El bloque deja de estar referenciado y el recolector de basura de Lua
    -- libera su memoria más adelante.
    return Result.ok(current.parent)
end

-- Lista ordenada de los nombres visibles desde `env`. Un nombre que existe
-- en un bloque y también en el global aparece una sola vez.
function M.names(env)
    local seen, list = {}, {}
    local scope = env
    while scope ~= nil do
        for name in pairs(scope.vars) do
            if not seen[name] then
                seen[name] = true
                list[#list + 1] = name
            end
        end
        scope = scope.parent
    end
    table.sort(list)
    return Result.ok(list)
end

function M.scope_label(scope)
    if scope.depth == 0 then return "global" end
    return "bloque " .. scope.depth
end

return M
