-- tests/test_evaluator.lua
-- Pruebas del Mini-REPL sin dependencias externas.
-- Ejecutar desde la raíz del proyecto:  lua tests/test_evaluator.lua

local script_dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./"
package.path = script_dir .. "../src/?.lua;" .. "./src/?.lua;" .. package.path

local Tokenizer = require("tokenizer")
local Evaluator = require("evaluator")
local Environment = require("environment")
local Value = require("value")
local Errors = require("errors")
local REPL = require("repl")

local passed, failed = 0, 0

local function check(description, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print("FALLA: " .. description .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

-- Evalúa una línea con una pila nueva. Devuelve valor, error, entorno.
local function run(line, env)
    env = env or Environment.new(nil)
    return REPL.eval_line(line, {}, env)
end

local function expect_value(line, text, kind, env)
    local value, err, new_env = run(line, env)
    check(string.format("'%s' -> %s (%s)", line, text, kind),
        err == nil and value ~= nil and Value.tostring(value) == text and value.kind == kind,
        err and Errors.format(err) or (value and (Value.tostring(value) .. " " .. value.kind) or "sin valor"))
    return new_env
end

local function expect_error(line, code, env)
    local value, err, new_env = run(line, env)
    check(string.format("'%s' -> error %s", line, code),
        err ~= nil and err.code == code,
        err and Errors.format(err) or ("sin error, valor " .. Value.tostring(value)))
    return new_env
end

-- 1. Aritmética y comparaciones
expect_value("5 2 +", "7", "int")
expect_value("5 2 -", "3", "int")
expect_value("2 5 -", "-3", "int")
expect_value("4 3 *", "12", "int")
expect_value("8 2 /", "4", "int")
expect_value("7 2 /", "3.5", "float")
expect_value("1.5 2 +", "3.5", "float")
expect_value("2.0 2 *", "4.0", "float")
expect_value("-5 3 +", "-2", "int")
expect_value("3 4 + 2 *", "14", "int")
expect_value("9223372036854775806 1 +", "9223372036854775807", "int")
expect_value("-9223372036854775808 1 +", "-9223372036854775807", "int")
expect_value("1 2 3", "3", "int")
expect_value("5 5 ==", "true", "bool")
expect_value("2 2.0 ==", "true", "bool")
expect_value("5 3 !=", "true", "bool")
expect_value("2 3 <", "true", "bool")
expect_value("2 3 >", "false", "bool")
expect_value("true false ==", "false", "bool")
expect_value("true true !=", "false", "bool")
expect_value("1 2 < 3 4 < ==", "true", "bool")

-- 2. Errores controlados
expect_error("5 0 /", Errors.Code.DIVISION_BY_ZERO)
expect_error("5 0.0 /", Errors.Code.DIVISION_BY_ZERO)
expect_error("5 +", Errors.Code.STACK_UNDERFLOW)
expect_error("*", Errors.Code.STACK_UNDERFLOW)
expect_error("5 true +", Errors.Code.TYPE_MISMATCH)
expect_error("true 1 <", Errors.Code.TYPE_MISMATCH)
expect_error("5 true ==", Errors.Code.TYPE_MISMATCH)
expect_error("5 @", Errors.Code.INVALID_TOKEN)
expect_error("5x 2 +", Errors.Code.INVALID_TOKEN)
expect_error("99999999999999999999", Errors.Code.INVALID_TOKEN)
expect_error("y", Errors.Code.UNDEFINED_VARIABLE)
expect_error("y 1 +", Errors.Code.UNDEFINED_VARIABLE)
expect_error("5 3 =", Errors.Code.INVALID_ASSIGNMENT)
expect_error("x =", Errors.Code.STACK_UNDERFLOW)
expect_error("end", Errors.Code.NO_OPEN_BLOCK)
expect_error("1 vars", Errors.Code.INVALID_TOKEN)
-- Desbordamiento: Lua haría wrap, pero el evaluador lo reporta como error.
expect_error("9223372036854775807 1 +", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("9199999999999999999 1000000000000000000 +", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("-9223372036854775808 -1 +", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("9223372036854775807 -1 -", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("-9223372036854775808 1 -", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("9223372036854775807 2 *", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("-9223372036854775808 -1 *", Errors.Code.ARITHMETIC_OVERFLOW)
expect_error("-9223372036854775808 -1 /", Errors.Code.ARITHMETIC_OVERFLOW)

local _, tok_err = Tokenizer.tokenize("1 2 $ +")
check("el error de token indica la columna", tok_err and tok_err.message:find("columna 5") ~= nil,
    tok_err and tok_err.message)

-- 3. Variables
local env = Environment.new(nil)
local value = run("x 10 =", env)
check("una asignación no deja valor para imprimir", value == nil)
expect_value("x", "10", "int", env)
run("x 5 2 + =", env)
expect_value("x", "7", "int", env)
expect_value("x 5 + 2 *", "24", "int", env)
run("x x 1 + =", env)
expect_value("x", "8", "int", env)
run("y x =", env)
expect_value("y", "8", "int", env)
run("b 1 2 < =", env)
expect_value("b", "true", "bool", env)
expect_value("a 1 = b 2 = a b +", "3", "int", Environment.new(nil))
local names = Environment.names(env)
check("vars lista los nombres ordenados", table.concat(names, ",") == "b,x,y", table.concat(names, ","))

-- 4. Alcance local y shadowing
local g = Environment.new(nil)
run("x 7 =", g)
expect_value("begin x 99 = x end", "99", "int", g)
expect_value("x", "7", "int", g)

local inside = select(3, run("begin", g))
check("begin abre un bloque hijo del global", inside ~= g and inside.parent == g and inside.depth == 1)
expect_value("x", "7", "int", inside)        -- se ve la global desde el bloque
run("x 1 =", inside)
expect_value("x", "1", "int", inside)        -- la local oculta a la global
run("z 3 =", inside)
local outside = select(3, run("end", inside))
check("end devuelve el entorno global", outside == g)
expect_value("x", "7", "int", g)
expect_error("z", Errors.Code.UNDEFINED_VARIABLE, g)

local after_error = select(3, run("begin 5 0 /", g))
check("si la línea falla, el bloque abierto antes del error sigue abierto",
    after_error.depth == 1)

local nested = select(3, run("begin x 1 = begin x 2 =", g))
check("los bloques se pueden anidar", nested.depth == 2)
expect_value("x", "2", "int", nested)
nested = select(3, run("end", nested))
expect_value("x", "1", "int", nested)
nested = select(3, run("end", nested))
expect_value("x", "7", "int", nested)

-- Límite de profundidad: 1000 bloques permitidos, el 1001 se rechaza.
local deep = Environment.new(nil)
for _ = 1, Environment.MAX_DEPTH do
    deep = Environment.open(deep)
end
check("se pueden abrir 1000 bloques anidados", deep.depth == Environment.MAX_DEPTH)
local _, depth_err = Environment.open(deep)
check("el bloque 1001 se rechaza con error controlado",
    depth_err ~= nil and depth_err.code == Errors.Code.MAX_DEPTH_EXCEEDED,
    depth_err and Errors.format(depth_err))
expect_error("begin", Errors.Code.MAX_DEPTH_EXCEEDED, deep)

local h = Environment.new(nil)
run("x 7 =", h)
local block = Environment.open(h)
Environment.set(block, "x", Value.int(50))
check("Environment.set modifica la variable donde existe (aquí, la global)",
    h.vars.x.value == 50 and block.vars.x == nil)
local _, set_err = Environment.set(block, "w", Value.int(1))
check("Environment.set falla si la variable no existe",
    set_err and set_err.code == Errors.Code.UNDEFINED_VARIABLE)

-- 5. Paso de parámetros: las tablas se pasan como referencia
local stack = {}
Evaluator.push_number("5", stack)
Evaluator.push_number("2", stack)
check("push_number modifica la pila del llamador", #stack == 2)
Evaluator.apply_operator("+", stack)
check("apply_operator deja un solo valor en la misma pila",
    #stack == 1 and stack[1].value == 7)

local overflow_stack = {}
Evaluator.push_number("9223372036854775807", overflow_stack)
Evaluator.push_number("1", overflow_stack)
local _, overflow_err = Evaluator.apply_operator("+", overflow_stack)
check("un desbordamiento no desapila los operandos",
    overflow_err ~= nil and overflow_err.code == Errors.Code.ARITHMETIC_OVERFLOW
        and #overflow_stack == 2)
REPL.clear(stack)
check("clear vacía la misma tabla", #stack == 0)

local caller_env = Environment.new(nil)
local _, _, returned_env = Evaluator.eval(Tokenizer.tokenize("begin"), {}, caller_env)
check("eval no cambia la variable del llamador; devuelve el entorno nuevo",
    caller_env.depth == 0 and returned_env.parent == caller_env)

-- 6. Memoria: un bloque cerrado queda sin referencias y el recolector lo libera
local weak = setmetatable({}, { __mode = "v" })
local function open_and_close()
    local global_env = Environment.new(nil)
    local block_env = Environment.open(global_env)
    Environment.define(block_env, "x", Value.int(99))
    weak.block = block_env
    return (Environment.close(block_env))
end
local survivor = open_and_close()
collectgarbage("collect")
collectgarbage("collect")
check("el entorno del bloque cerrado fue liberado", weak.block == nil)
check("el entorno global sigue vivo", survivor ~= nil and survivor.depth == 0)

-- 7. Metatablas: tostring sobre valores y errores
check("tostring(Value) usa __tostring", tostring(Value.float(2.5)) == "2.5")
check("tostring(error) usa __tostring",
    tostring(Errors.new("x", "mensaje")) == "[x] mensaje")

-- 8. Sesión completa del REPL con entrada simulada
local session = {
    "5 2 +",
    "x 5 2 + =",
    "x",
    "x 5 + 2 *",
    "7 2 /",
    "3 4 <",
    "5 true +",
    "5 0 /",
    "5 +",
    "9199999999999999999 1000000000000000000 +",
    "3 #",
    "begin x 99 = x end",
    "x",
    "begin",
    "x 1 =",
    "y 2 =",
    "vars",
    "end",
    "vars",
    "end",
    "exit",
}
local expected = {
    REPL.BANNER,
    "7",
    "7",
    "24",
    "3.5",
    "true",
    "[type_mismatch] el operador + no se puede aplicar a int y bool",
    "[division_by_zero] división por cero",
    "[stack_underflow] el operador + necesita 2 valores y la pila tiene 1",
    "[arithmetic_overflow] el resultado de + excede el rango de enteros",
    "[invalid_token] token inválido '#' en la columna 3",
    "99",
    "7",
    "x = 1 (int, bloque 1)",
    "y = 2 (int, bloque 1)",
    "x = 7 (int, global)",
    "[no_open_block] 'end' sin 'begin': no hay ningún bloque abierto",
}

local i = 0
local function scripted_input()
    i = i + 1
    return session[i]
end
local printed = {}
local prompts = {}
REPL.run(scripted_input, function(text) printed[#printed + 1] = text end,
    function(text) prompts[#prompts + 1] = text end)

check("la sesión imprime el número esperado de líneas", #printed == #expected,
    #printed .. " en lugar de " .. #expected)
for k = 1, math.max(#printed, #expected) do
    check("sesión, salida " .. k, printed[k] == expected[k],
        tostring(printed[k]) .. "  vs  " .. tostring(expected[k]))
end
check("el prompt indica el bloque abierto", prompts[15] == "rpn[1]> ", tostring(prompts[15]))

print(string.format("%d pruebas correctas, %d fallidas", passed, failed))
os.exit(failed == 0 and 0 or 1)
