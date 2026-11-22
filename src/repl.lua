-- repl.lua
-- Bucle interactivo: leer -> tokenizar -> evaluar -> imprimir.

local Tokenizer = require("tokenizer")
local Evaluator = require("evaluator")
local Environment = require("environment")
local Value = require("value")
local Errors = require("errors")

local M = {}

function M.run(input, output)
    input = input or io.read
    output = output or print

    local global_env = Environment.new(nil)
    local env = global_env
    local stack = {}

    output("Mini-REPL RPN (Lua) - esqueleto. Comandos: begin, end, vars, exit")

    while true do
        io.write("rpn> ")
        io.flush()

        local line = input()
        if line == nil then break end

        if line == "exit" or line == "quit" then
            break
        end

        -- TODO: atender aquí los comandos `begin`, `end` y `vars`, que
        -- modifican el entorno actual antes de tokenizar la expresión.

        local tokens, tok_err = Tokenizer.tokenize(line)
        if tok_err then
            output(Errors.format(tok_err))
        else
            local value, eval_err = Evaluator.eval(tokens, stack, env)
            if eval_err then
                output(Errors.format(eval_err))
            else
                output(Value.tostring(value))
            end
        end
    end
end

return M
