-- tests/test_evaluator.lua
-- Harness de pruebas (pendiente). Casos previstos:
--   "5 2 +"        -> 7
--   "x 5 2 + ="    -> x = 7
--   "x"            -> 7
--   "5 0 /"        -> error division_by_zero
--   "5 +"          -> error stack_underflow
--   "5 true +"     -> error type_mismatch
--   "begin x 1 = end x" -> valor global de x sin cambios

package.path = "./src/?.lua;" .. package.path

print("TODO: suite de pruebas no implementada")
