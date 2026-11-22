-- repl.lua
-- Bucle interactivo: leer -> tokenizar -> evaluar -> imprimir.

local Tokenizer = require("tokenizer")
local Evaluator = require("evaluator")
local Environment = require("environment")
local Value = require("value")
local Errors = require("errors")

local M = {}

M.BANNER = "Mini-REPL RPN (Lua). Operadores: + - * / == != < > =  Comandos: begin, end, vars, exit"

-- "rpn> " en el entorno global; "rpn[1]> " dentro de un bloque, etc.
function M.prompt(env)
    if env.depth == 0 then return "rpn> " end
    return string.format("rpn[%d]> ", env.depth)
end

-- Vacía la pila sin crear una tabla nueva: el evaluador y el REPL comparten
-- la misma tabla, así que basta con borrar sus elementos.
function M.clear(stack)
    for i = #stack, 1, -1 do
        stack[i] = nil
    end
end

-- Contrato: valor|nil, error|nil, entorno_activo
function M.eval_line(line, stack, env)
    local tokens, tok_err = Tokenizer.tokenize(line)
    if tok_err then
        return nil, tok_err, env
    end
    return Evaluator.eval(tokens, stack, env)
end

-- Comando `vars`: muestra cada variable visible, su tipo y el ámbito donde
-- vive. Si un nombre existe en un bloque y en el global, se ve el del bloque.
function M.show_vars(env, output)
    local names = Environment.names(env)
    if #names == 0 then
        output("(no hay variables definidas)")
        return
    end
    for _, name in ipairs(names) do
        local value, scope = Environment.lookup(env, name)
        output(string.format("%s = %s (%s, %s)",
            name, Value.tostring(value), Value.type_name(value), Environment.scope_label(scope)))
    end
end

function M.run(input, output, write_prompt)
    input = input or io.read
    output = output or print
    write_prompt = write_prompt or function(text)
        io.write(text)
        io.flush()
    end

    local global_env = Environment.new(nil)
    local env = global_env
    local stack = {}

    output(M.BANNER)

    while true do
        write_prompt(M.prompt(env))

        local line = input()
        if line == nil then
            output("")
            break
        end

        local command = line:match("^%s*(.-)%s*$")

        if command == "exit" or command == "quit" then
            break
        elseif command == "vars" then
            M.show_vars(env, output)
        elseif command ~= "" then
            -- Cada línea es una expresión independiente: la pila empieza vacía.
            M.clear(stack)

            -- pcall es una red de seguridad para fallos no previstos (errores
            -- de programación). Los errores esperados llegan como `err`.
            local ok, value, err, new_env = pcall(M.eval_line, command, stack, env)
            if not ok then
                output(Errors.format(Errors.new(Errors.Code.INTERNAL_ERROR,
                    "fallo interno: " .. tostring(value))))
            else
                env = new_env
                if err then
                    output(Errors.format(err))
                elseif value ~= nil then
                    output(Value.tostring(value))
                end
            end
        end
    end
end

return M
