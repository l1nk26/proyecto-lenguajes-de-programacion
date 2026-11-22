-- main.lua
-- Punto de entrada del Mini-REPL RPN escrito en Lua.
-- Ajusta package.path para que `require` encuentre los módulos de src/
-- sin depender del directorio desde el que se invoque el script.

local script_dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

-- En Windows la consola no usa UTF-8 por defecto y los mensajes con acentos
-- se verían mal. package.config empieza con "\" solo en Windows.
if package.config:sub(1, 1) == "\\" then
    os.execute("chcp 65001 > NUL")
end

local REPL = require("repl")

REPL.run()
