-- evaluator.lua
-- Máquina de pila (RPN). La pila y el entorno se pasan explícitamente a cada
-- subrutina para hacer evidente en el código el paso de parámetros y la
-- mutabilidad de las tablas de Lua.

local Result = require("result")
local Errors = require("errors")
local Value = require("value")
local Environment = require("environment")
local Tokenizer = require("tokenizer")

local M = {}

local function underflow(what, needed, available)
    return Result.fail(Errors.new(
        Errors.Code.STACK_UNDERFLOW,
        string.format("%s necesita %d valores y la pila tiene %d", what, needed, available),
        what))
end

local function push(stack, value)
    stack[#stack + 1] = value
    return Result.ok(value)
end

--- Convierte la ficha de un nombre en el valor de la variable.
--- Un número o booleano se devuelve tal cual.
function M.resolve(item)
    if Value.is_name(item) then
        if item.value == nil then
            return Result.fail(Errors.new(
                Errors.Code.UNDEFINED_VARIABLE,
                string.format("la variable '%s' no está definida", item.name),
                item.name))
        end
        return Result.ok(item.value)
    end
    return Result.ok(item)
end

-- Int si ambos operandos son Int; Float si alguno es Float.
local function number_result(a, b, n)
    if a.kind == Value.Kind.INT and b.kind == Value.Kind.INT then
        return Value.int(n)
    end
    return Value.float(n)
end

local function divide(a, b)
    if b.value == 0 then
        return Result.fail(Errors.new(Errors.Code.DIVISION_BY_ZERO, "división por cero", "/"))
    end
    -- Entre enteros, si la división es exacta el resultado sigue siendo Int.
    if a.kind == Value.Kind.INT and b.kind == Value.Kind.INT and a.value % b.value == 0 then
        return Result.ok(Value.int(a.value // b.value))
    end
    return Result.ok(Value.float(a.value / b.value))
end

-- Tabla de operadores. `accepts` indica qué tipos admite cada operador:
--   numbers:    ambos operandos deben ser números (Int o Float)
--   comparable: ambos números o ambos booleanos
local OPERATORS = {
    ["+"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value + b.value)) end },
    ["-"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value - b.value)) end },
    ["*"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value * b.value)) end },
    ["/"]  = { accepts = "numbers", apply = divide },
    ["=="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value == b.value)) end },
    ["!="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value ~= b.value)) end },
    ["<"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value < b.value)) end },
    [">"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value > b.value)) end },
}

local function check_types(op, accepts, a, b)
    local valid
    if accepts == "numbers" then
        valid = Value.is_number(a) and Value.is_number(b)
    else
        valid = (Value.is_number(a) and Value.is_number(b))
            or (Value.is_bool(a) and Value.is_bool(b))
    end
    if valid then
        return Result.ok(true)
    end
    return Result.fail(Errors.new(
        Errors.Code.TYPE_MISMATCH,
        string.format("el operador %s no se puede aplicar a %s y %s",
            op, Value.type_name(a), Value.type_name(b)),
        op))
end

function M.push_number(lexeme, stack)
    local n = tonumber(lexeme)
    if n == nil then
        return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
            string.format("'%s' no es un número válido", lexeme), lexeme))
    end
    if math.type(n) == "integer" then
        return push(stack, Value.int(n))
    end
    if lexeme:find(".", 1, true) then
        return push(stack, Value.float(n))
    end
    -- Un literal sin punto que Lua no pudo guardar como entero (por ejemplo
    -- 99999999999999999999) se convertiría en Float sin avisar; se rechaza.
    return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
        string.format("el entero '%s' está fuera del rango permitido", lexeme), lexeme))
end

function M.push_bool(lexeme, stack)
    return push(stack, Value.bool(lexeme == "true"))
end

-- Apila una ficha con el nombre y el valor actual de la variable (nil si aún
-- no existe). El error por variable inexistente se reporta solo cuando el
-- valor se necesita, porque `x 10 =` usa `x` antes de que exista.
function M.push_variable(name, stack, env)
    local current = Environment.lookup(env, name)
    return push(stack, Value.name(name, current))
end

function M.apply_operator(op, stack)
    local operator = OPERATORS[op]
    if operator == nil then
        return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
            string.format("operador desconocido '%s'", op), op))
    end
    if #stack < 2 then
        return underflow("el operador " .. op, 2, #stack)
    end

    -- En postfijo el operando derecho es el último que se apiló.
    local right_item = table.remove(stack)
    local left_item = table.remove(stack)

    local a, err_a = M.resolve(left_item)
    if err_a then return nil, err_a end
    local b, err_b = M.resolve(right_item)
    if err_b then return nil, err_b end

    local _, type_err = check_types(op, operator.accepts, a, b)
    if type_err then return nil, type_err end

    local result, op_err = operator.apply(a, b)
    if op_err then return nil, op_err end
    return push(stack, result)
end

-- `nombre valor =`: desapila el valor y el nombre, y escribe la variable en
-- el entorno actual.
function M.assign(stack, env)
    if #stack < 2 then
        return underflow("la asignación =", 2, #stack)
    end
    local value_item = table.remove(stack)
    local target = table.remove(stack)

    if not Value.is_name(target) then
        return Result.fail(Errors.new(Errors.Code.INVALID_ASSIGNMENT,
            string.format("antes del valor debe ir el nombre de una variable, pero se encontró un %s",
                Value.type_name(target)),
            "="))
    end

    local value, err = M.resolve(value_item)
    if err then return nil, err end
    return Environment.define(env, target.name, value)
end

-- Palabras reservadas que aparecen dentro de una expresión.
-- Devuelve el entorno que queda activo después de ejecutarla.
local function run_keyword(lexeme, stack, env)
    if lexeme == "=" then
        local _, err = M.assign(stack, env)
        if err then return nil, err end
        return Result.ok(env)
    elseif lexeme == "begin" then
        return Environment.open(env)
    elseif lexeme == "end" then
        return Environment.close(env)
    end
    return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
        string.format("'%s' es un comando y debe escribirse solo en la línea", lexeme),
        lexeme))
end

--- Evalúa una lista de tokens.
--- @param tokens table
--- @param stack table pila de valores (Value)
--- @param env table entorno actual
--- @return table|nil valor_tope_o_nil
--- @return table|nil error_o_nil
--- @return table entorno activo al terminar (cambia con begin / end)
function M.eval(tokens, stack, env)
    for _, token in ipairs(tokens) do
        local kind, lexeme = token.kind, token.lexeme
        local _, err

        if kind == Tokenizer.Kind.NUMBER then
            _, err = M.push_number(lexeme, stack)
        elseif kind == Tokenizer.Kind.BOOLEAN then
            _, err = M.push_bool(lexeme, stack)
        elseif kind == Tokenizer.Kind.IDENT then
            _, err = M.push_variable(lexeme, stack, env)
        elseif kind == Tokenizer.Kind.OPERATOR then
            _, err = M.apply_operator(lexeme, stack)
        elseif kind == Tokenizer.Kind.KEYWORD then
            local new_env
            new_env, err = run_keyword(lexeme, stack, env)
            if new_env then env = new_env end
        else
            err = Errors.new(Errors.Code.INVALID_TOKEN,
                string.format("token de clase desconocida '%s'", tostring(kind)), lexeme)
        end

        if err then
            return nil, err, env
        end
    end

    if #stack == 0 then
        return nil, nil, env
    end
    local top, err = M.resolve(stack[#stack])
    return top, err, env
end

return M
