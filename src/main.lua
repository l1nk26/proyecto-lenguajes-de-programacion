-- main.lua
-- Punto de entrada del Mini-REPL RPN escrito en Lua.
-- Ajusta package.path para que `require` encuentre los módulos de src/
-- sin depender del directorio desde el que se invoque el script.

local script_dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

local REPL = require("repl")

REPL.run()
