-- tokenizer.lua
-- Convierte una línea de entrada en una lista de tokens.
-- La notación postfija permite separar por espacios y clasificar cada lexema.

local Result = require("result")

local M = {}

M.Kind = {
    NUMBER = "number",
    IDENT = "ident",
    OPERATOR = "operator",
    KEYWORD = "keyword",
}

function M.new(kind, lexeme)
    return { kind = kind, lexeme = lexeme }
end

-- Contrato: tokens, nil  |  nil, error
function M.tokenize(line)
    -- TODO:
    --  1. recorrer los lexemas separados por espacios (string.gmatch)
    --  2. clasificarlos en NUMBER / IDENT / OPERATOR / KEYWORD
    --  3. rechazar lexemas inválidos con Errors.Code.INVALID_TOKEN
    return Result.fail("TODO: tokenizer.tokenize no implementado")
end

return M
