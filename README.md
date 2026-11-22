# Mini-REPL RPN en Lua

Componente práctico de la **Asignación #1 (Lenguajes de Programación,
CAO604)**: un evaluador postfijo con pila, variables con alcance local y
errores controlados, escrito en **Lua**. El reporte técnico está en
[`docs/reporte.md`](docs/reporte.md).

## Estructura

```
.
├── src/
│   ├── main.lua          # punto de entrada
│   ├── repl.lua          # bucle leer -> tokenizar -> evaluar -> imprimir
│   ├── tokenizer.lua     # lexemas -> tokens etiquetados
│   ├── evaluator.lua     # máquina de pila y operadores
│   ├── value.lua         # tagged union Int / Float / Bool / Name
│   ├── environment.lua   # tabla de símbolos con begin/end (shadowing)
│   ├── result.lua        # convención idiomática (valor, error)
│   └── errors.lua        # códigos y formato de errores
├── tests/
│   └── test_evaluator.lua
└── docs/
    └── reporte.md        # reporte técnico
```

## Requisitos

- **Lua 5.4** (probado con 5.4.6). No hay dependencias externas.
- En Windows se puede instalar con:

  ```powershell
  winget install --id DEVCOM.Lua -e
  ```

  Después de instalarlo hay que abrir una terminal nueva para que el comando
  `lua` esté disponible.
- Lua no necesita un paso de compilación aparte: el intérprete traduce el
  código a instrucciones de su máquina virtual al cargarlo y lo ejecuta.

## Cómo ejecutar

Desde la raíz del proyecto:

```powershell
lua src/main.lua
```

En Windows el programa cambia la consola a UTF-8 (`chcp 65001`) al arrancar
para que los mensajes con acentos se vean bien.

Para ejecutar las pruebas:

```powershell
lua tests/test_evaluator.lua
```

Al terminar se informa el total de comprobaciones correctas y fallidas (debe
terminar con `0 fallidas`).

## Uso

| Entrada | Significado |
| --- | --- |
| `5 2 +` | suma; también `-`, `*`, `/` |
| `5 3 <` | comparación; también `>`, `==`, `!=` (resultado `true` o `false`) |
| `x 10 =` | asigna 10 a `x` en el ámbito actual |
| `x 5 2 + =` | asigna el resultado de la expresión a `x` |
| `begin` / `end` | abre o cierra un bloque local (máximo **1000** bloques anidados) |
| `vars` | lista las variables visibles, su tipo y su ámbito |
| `exit` o `quit` | termina la sesión |

Cada línea es una expresión independiente: la pila empieza vacía en cada
línea y al final se imprime el valor que quedó en el tope. Una asignación no
imprime nada. La división entre enteros da un entero si es exacta (`8 2 /` da
`4`) y un decimal si no lo es (`7 2 /` da `3.5`).

## Sesión de prueba (entradas RPN y salidas esperadas)

```
Mini-REPL RPN (Lua). Operadores: + - * / == != < > =  Comandos: begin, end, vars, exit
rpn> 5 2 +
7
rpn> x 5 2 + =
rpn> x
7
rpn> x 5 + 2 *
24
rpn> 7 2 /
3.5
rpn> 3 4 <
true
rpn> 5 true +
[type_mismatch] el operador + no se puede aplicar a int y bool
rpn> 5 0 /
[division_by_zero] división por cero
rpn> 5 +
[stack_underflow] el operador + necesita 2 valores y la pila tiene 1
rpn> 9199999999999999999 1000000000000000000 +
[arithmetic_overflow] el resultado de + excede el rango de enteros
rpn> 3 #
[invalid_token] token inválido '#' en la columna 3
rpn> begin x 99 = x end
99
rpn> x
7
rpn> begin
rpn[1]> x 1 =
rpn[1]> y 2 =
rpn[1]> vars
x = 1 (int, bloque 1)
y = 2 (int, bloque 1)
rpn[1]> end
rpn> vars
x = 7 (int, global)
rpn> end
[no_open_block] 'end' sin 'begin': no hay ningún bloque abierto
rpn> exit
```

Esta misma sesión se verifica automáticamente en `tests/test_evaluator.lua`.

## Notas de diseño

- **Tipos:** Lua es de tipado dinámico; el evaluador comprueba sus propios
  tipos en tiempo de ejecución usando una *tagged union* en `value.lua`.
- **Errores:** se usa el mecanismo idiomático de Lua de múltiples retornos
  `(valor, error)` para los errores esperados; `pcall` en `repl.lua` solo
  protege contra fallos no previstos. Se agregó `arithmetic_overflow`: Lua
  hace *wrap* de los enteros al desbordar, pero el evaluador comprueba los
  límites antes de operar y rechaza el resultado en vez de devolver un número
  incorrecto.
- **Paso de parámetros:** la pila y el entorno se pasan explícitamente; las
  tablas de Lua se comportan como referencias, lo que permite mutarlas desde
  las subrutinas. Como `begin` y `end` cambian cuál es el entorno activo,
  `Evaluator.eval` lo devuelve como tercer resultado.
- **Alcance:** `environment.lua` encadena entornos mediante `parent` para
  implementar `begin` / `end` y *shadowing*. La asignación siempre escribe en
  el ámbito actual, por lo que no modifica las variables globales. El número
  de bloques anidados está limitado a 1000 (`Environment.MAX_DEPTH`); abrir
  el bloque 1001 responde
  `[max_depth_exceeded] se alcanzó el límite de 1000 bloques anidados` en vez
  de seguir consumiendo memoria.
