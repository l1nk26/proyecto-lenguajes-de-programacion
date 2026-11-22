-- tokenizer.lua
-- Convierte una línea de entrada en una lista de tokens.
-- La notación postfija permite separar por espacios y clasificar cada lexema.

local Result = require("result")
local Errors = require("errors")

local M = {}

M.Kind = {
    NUMBER = "number",
    BOOLEAN = "boolean",
    IDENT = "ident",
    OPERATOR = "operator",
    KEYWORD = "keyword",
}

-- Conjuntos de lexemas fijos. En Lua un conjunto se escribe como una tabla
-- cuyas claves son los elementos: OPERATORS["+"] vale true.
local OPERATORS = {
    ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
    ["=="] = true, ["!="] = true, ["<"] = true, [">"] = true,
}

local KEYWORDS = {
    ["="] = true, ["begin"] = true, ["end"] = true,
    ["vars"] = true, ["exit"] = true, ["quit"] = true,
}

local BOOLEANS = { ["true"] = true, ["false"] = true }

function M.new(kind, lexeme, column)
    return { kind = kind, lexeme = lexeme, column = column }
end

local function is_integer_literal(lexeme)
    return lexeme:match("^[+-]?%d+$") ~= nil
end

local function is_float_literal(lexeme)
    return lexeme:match("^[+-]?%d+%.%d*$") ~= nil
        or lexeme:match("^[+-]?%.%d+$") ~= nil
end

local function is_identifier(lexeme)
    return lexeme:match("^[%a_][%w_]*$") ~= nil
end

-- Devuelve la clase del lexema o nil si no pertenece a ninguna.
-- El orden importa: "-" es operador, pero "-5" es número; "end" es palabra
-- reservada aunque también cumpla la forma de un identificador.
function M.classify(lexeme)
    if OPERATORS[lexeme] then return M.Kind.OPERATOR end
    if KEYWORDS[lexeme] then return M.Kind.KEYWORD end
    if BOOLEANS[lexeme] then return M.Kind.BOOLEAN end
    if is_integer_literal(lexeme) or is_float_literal(lexeme) then
        return M.Kind.NUMBER
    end
    if is_identifier(lexeme) then return M.Kind.IDENT end
    return nil
end

-- Contrato: tokens, nil  |  nil, error
function M.tokenize(line)
    local tokens = {}
    -- "()" captura la columna donde empieza cada lexema; "%S+" toma cada
    -- secuencia de caracteres que no son espacios.
    for column, lexeme in line:gmatch("()(%S+)") do
        local kind = M.classify(lexeme)
        if kind == nil then
            return Result.fail(Errors.new(
                Errors.Code.INVALID_TOKEN,
                string.format("token inválido '%s' en la columna %d", lexeme, column),
                lexeme))
        end
        tokens[#tokens + 1] = M.new(kind, lexeme, column)
    end
    return Result.ok(tokens)
end

return M
