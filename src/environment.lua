-- environment.lua
-- Tabla de símbolos con alcance léxico. Cada entorno apunta a su padre;
-- `begin` crea un hijo y `end` vuelve al padre (shadowing sin sobrescribir
-- permanentemente las variables globales).
--
-- En Lua las tablas se pasan como valores de referencia: el evaluador recibe
-- el entorno explícitamente y puede mutar sus campos.

local Result = require("result")

local M = {}

function M.new(parent)
    return { parent = parent, vars = {} }
end

-- Contrato para todas las subrutinas: valor, nil | nil, error

function M.get(env, name)
    -- TODO: buscar en env.vars y, si no está, subir por env.parent
    return Result.fail("TODO: environment.get no implementado")
end

function M.define(env, name, value)
    -- TODO: crear/actualizar la variable en el ámbito actual
    return Result.fail("TODO: environment.define no implementado")
end

function M.set(env, name, value)
    -- TODO: actualizar la variable más cercana (global o local)
    return Result.fail("TODO: environment.set no implementado")
end

function M.open(current)
    return M.new(current)
end

function M.close(current)
    return current.parent or current
end

function M.names(env)
    -- TODO: devolver la lista de nombres visibles para el comando `vars`
    return Result.fail("TODO: environment.names no implementado")
end

return M
