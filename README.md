# Mini-REPL RPN en Lua

Esqueleto del componente práctico de la **Asignación #1 (Lenguajes de
Programación, CAO604)**: un evaluador postfijo con pila, variables con alcance
local y errores controlados, escrito en **Lua**.

> Estado actual: **estructura y stubs**. Los módulos están creados con sus
> contratos y TODOs, pero la lógica todavía no está implementada.

## Estructura

```
.
├── src/
│   ├── main.lua          # punto de entrada
│   ├── repl.lua          # bucle leer -> tokenizar -> evaluar -> imprimir
│   ├── tokenizer.lua     # lexemas -> tokens etiquetados
│   ├── evaluator.lua     # máquina de pila y operadores
│   ├── value.lua         # tagged union Int / Float / Bool
│   ├── environment.lua   # tabla de símbolos con begin/end (shadowing)
│   ├── result.lua        # convención idiomática (valor, error)
│   └── errors.lua        # códigos y formato de errores
├── tests/
│   └── test_evaluator.lua
└── docs/
    └── reporte.md        # outline del reporte técnico
```

## Requisitos

- **Lua 5.4** recomendado (5.3 también sirve; se usa `math.type` para
  distinguir `integer` de `float`). No hay dependencias externas.
- Lua es un lenguaje interpretado: no hay paso de compilación.

## Cómo ejecutar

Desde la raíz del proyecto:

```powershell
lua src/main.lua
```

Para ejecutar las pruebas (una vez implementadas):

```powershell
lua tests/test_evaluator.lua
```

## Sesión de prueba prevista (entradas RPN y salidas esperadas)

Una vez completados los stubs, la sesión debería verse así:

```
rpn> 5 2 +
7
rpn> x 5 2 + =
rpn> x
7
rpn> 5 true +
[type_mismatch] operación inválida entre int y bool
rpn> 5 0 /
[division_by_zero] división por cero
rpn> begin x 99 = x end
99
rpn> x
7
rpn> vars
x = 7
rpn> exit
```

## Notas de diseño (para el reporte)

- **Tipos:** Lua es de tipado dinámico; el evaluador refuerza sus propios
  tipos en tiempo de ejecución usando una *tagged union* en `value.lua`.
- **Errores:** se usa el mecanismo idiomático de Lua de múltiples retornos
  `(valor, error)` en lugar de excepciones para errores esperados.
- **Paso de parámetros:** la pila y el entorno se pasan explícitamente; las
  tablas de Lua se comportan como referencias, lo que permite mutarlas desde
  las subrutinas.
- **Alcance:** `environment.lua` encadena entornos mediante `parent` para
  implementar `begin` / `end` y *shadowing*.
