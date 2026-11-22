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

-- Lua 5.3+ usa enteros de 64 bits y hace wrap al desbordar. Estas cotas
-- permiten detectarlo antes de operar y devolver un error controlado.
local MAX_INT, MIN_INT = math.maxinteger, math.mininteger

local function int_pair(a, b)
    return a.kind == Value.Kind.INT and b.kind == Value.Kind.INT
end

local function arithmetic_overflow(op, message)
    return Result.fail(Errors.new(Errors.Code.ARITHMETIC_OVERFLOW, message, op))
end

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

-- Comprobaciones de rango para enteros. Devuelven nil si el resultado
-- estaría fuera de [math.mininteger, math.maxinteger].
local function checked_add(a, b)
    if b > 0 and a > MAX_INT - b then return nil end
    if b < 0 and a < MIN_INT - b then return nil end
    return a + b
end

local function checked_sub(a, b)
    if b < 0 and a > MAX_INT + b then return nil end
    if b > 0 and a < MIN_INT + b then return nil end
    return a - b
end

local function checked_mul(a, b)
    if a == 0 or b == 0 then return 0 end
    -- MIN_INT // -1 también desborda en Lua: se comprueba aparte antes de
    -- usar la división entera como mecanismo de verificación.
    if a == -1 then
        if b == MIN_INT then return nil end
        return -b
    end
    if b == -1 then
        if a == MIN_INT then return nil end
        return -a
    end
    local product = a * b -- puede venir con wrap; solo se usa para verificar
    if product // a ~= b then return nil end
    return product
end

local function add_values(a, b)
    if int_pair(a, b) then return checked_add(a.value, b.value) end
    return a.value + b.value
end

local function sub_values(a, b)
    if int_pair(a, b) then return checked_sub(a.value, b.value) end
    return a.value - b.value
end

local function mul_values(a, b)
    if int_pair(a, b) then return checked_mul(a.value, b.value) end
    return a.value * b.value
end

-- Int si ambos operandos son Int; Float si alguno es Float.
-- `n == nil` significa que la comprobación de enteros detectó desbordamiento.
local function number_value(op, a, b, n)
    if int_pair(a, b) then
        if n == nil then
            return arithmetic_overflow(op,
                string.format("el resultado de %s excede el rango de enteros", op))
        end
        return Result.ok(Value.int(n))
    end
    -- Los flotantes también pueden salirse de rango (inf / NaN).
    if n ~= n or n == math.huge or n == -math.huge then
        return arithmetic_overflow(op,
            string.format("el resultado de %s excede el rango de flotantes", op))
    end
    return Result.ok(Value.float(n))
end

local function divide(a, b)
    if b.value == 0 then
        return Result.fail(Errors.new(Errors.Code.DIVISION_BY_ZERO, "división por cero", "/"))
    end
    if int_pair(a, b) then
        if a.value == MIN_INT and b.value == -1 then
            return arithmetic_overflow("/", "math.mininteger / -1 excede el rango de enteros")
        end
        -- Entre enteros, si la división es exacta el resultado sigue siendo Int.
        if a.value % b.value == 0 then
            return Result.ok(Value.int(a.value // b.value))
        end
    end
    local quotient = a.value / b.value
    if quotient ~= quotient or quotient == math.huge or quotient == -math.huge then
        return arithmetic_overflow("/", "el resultado de / excede el rango de flotantes")
    end
    return Result.ok(Value.float(quotient))
end

-- Tabla de operadores. `accepts` indica qué tipos admite cada operador:
--   numbers:    ambos operandos deben ser números (Int o Float)
--   comparable: ambos números o ambos booleanos
local OPERATORS = {
    ["+"]  = { accepts = "numbers", apply = function(a, b) return number_value("+", a, b, add_values(a, b)) end },
    ["-"]  = { accepts = "numbers", apply = function(a, b) return number_value("-", a, b, sub_values(a, b)) end },
    ["*"]  = { accepts = "numbers", apply = function(a, b) return number_value("*", a, b, mul_values(a, b)) end },
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

    -- En postfijo el operando derecho es el último que se apiló. Solo se
    -- desapilan después de validar: un error deja la pila como estaba.
    local right_item = stack[#stack]
    local left_item = stack[#stack - 1]

    local a, err_a = M.resolve(left_item)
    if err_a then return nil, err_a end
    local b, err_b = M.resolve(right_item)
    if err_b then return nil, err_b end

    local _, type_err = check_types(op, operator.accepts, a, b)
    if type_err then return nil, type_err end

    local result, op_err = operator.apply(a, b)
    if op_err then return nil, op_err end

    table.remove(stack)
    table.remove(stack)
    return push(stack, result)
end

-- `nombre valor =`: desapila el valor y el nombre, y escribe la variable en
-- el entorno actual.
function M.assign(stack, env)
    if #stack < 2 then
        return underflow("la asignación =", 2, #stack)
    end
    local value_item = stack[#stack]
    local target = stack[#stack - 1]

    if not Value.is_name(target) then
        return Result.fail(Errors.new(Errors.Code.INVALID_ASSIGNMENT,
            string.format("antes del valor debe ir el nombre de una variable, pero se encontró un %s",
                Value.type_name(target)),
            "="))
    end

    local value, err = M.resolve(value_item)
    if err then return nil, err end

    table.remove(stack)
    table.remove(stack)
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
