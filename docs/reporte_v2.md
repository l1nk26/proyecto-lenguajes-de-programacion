# Mini-REPL en notación polaca inversa escrito en Lua 5.4

## Reporte técnico (Partes I y II)

Universidad de Carabobo

Facultad Experimental de Ciencias y Tecnología

CAO604 Lenguajes de Programación

Asignación #1, semestre 1-2026

Integrantes: Fabián Tovar y Saúl Vargas

Repositorio: https://github.com/l1nk26/proyecto-lenguajes-de-programacion

## 1. Cómo está armado el programa

El Mini-REPL es un programa de consola. Muestra un indicador (`rpn> `), espera a que el usuario escriba una línea, la evalúa e imprime el resultado; después vuelve a mostrar el indicador. Ese ciclo de leer, evaluar, imprimir y repetir es lo que da nombre a un REPL (por las siglas en inglés de *read, eval, print, loop*).

Las expresiones se escriben en notación polaca inversa, también llamada postfija (Hamblin, 1962): primero van los operandos y después el operador. Lo que en notación infija se escribe como `(x + 5) * 2` aquí se escribe `x 5 + 2 *`, tal como lo exige el enunciado. Para evaluar esa notación se usa una pila: cada número se apila y cada operador toma los dos valores superiores, aplica la operación y apila el resultado.

El programa se organiza en ocho archivos dentro de `src/`. Cada uno es un módulo, es decir, un archivo de Lua que agrupa funciones relacionadas y las entrega a quien lo pida con `require`.

| Archivo | Responsabilidad |
| --- | --- |
| `main.lua` | Punto de entrada. Ajusta la ruta de búsqueda de módulos, activa UTF-8 en la consola de Windows y arranca el REPL. |
| `repl.lua` | Bucle interactivo, comandos `vars` y `exit`, impresión de resultados y de errores. |
| `tokenizer.lua` | Corta la línea en palabras y clasifica cada una (número, booleano, identificador, operador o palabra reservada). |
| `evaluator.lua` | Máquina de pila: apila valores, aplica operadores, comprueba tipos y ejecuta `=`, `begin` y `end`. |
| `value.lua` | Representación de los valores que viajan en la pila (`int`, `float`, `bool` y `name`). |
| `environment.lua` | Tabla de símbolos: guarda las variables y encadena los bloques abiertos con `begin`. |
| `result.lua` | Convención para devolver éxito o fallo con dos resultados `(valor, error)`. |
| `errors.lua` | Códigos de error y formato de los mensajes. |

Una línea escrita por el usuario recorre siempre el mismo camino. `repl.lua` la recibe, le quita los espacios de los extremos y, si no es `exit`, `quit` ni `vars`, se la entrega a `eval_line`:

```lua
-- Contrato: valor|nil, error|nil, entorno_activo
function M.eval_line(line, stack, env)
    local tokens, tok_err = Tokenizer.tokenize(line)
    if tok_err then
        return nil, tok_err, env
    end
    return Evaluator.eval(tokens, stack, env)
end
```

(`src/repl.lua`, líneas 29 a 35.) Una palabra que no encaja en ninguna clase rechaza la línea antes de evaluarla.

Cada línea se trata como una expresión independiente: la pila se vacía antes de evaluarla. El entorno, en cambio, persiste entre líneas, de modo que `x 10 =` y `x 1 +` pueden escribirse por separado. Un error no desapila los operandos: la pila sigue como estaba hasta que `clear` la vacía en la siguiente línea.

Lua no tiene un paso de compilación separado. El intérprete carga cada archivo, lo traduce a instrucciones de su máquina virtual y las ejecuta en el mismo momento (Ierusalimschy et al., 2020, sección 3.3.2). Por eso basta con ejecutar, desde la raíz del repositorio:

```text
lua src/main.lua
```

Todas las pruebas de este reporte se hicieron con el intérprete Lua 5.4.6 en Windows 11. El archivo de pruebas se ejecuta con `lua tests/test_evaluator.lua` y al terminar informa el total de comprobaciones correctas y fallidas (debe ser cero fallidas). Los ejemplos de código que no llevan ruta de archivo son ilustrativos del manual, no parte del proyecto.

## 2. Nombres, vinculación, estructuras de control y alcance

### 2.1 Nombres en Lua y en el proyecto

En Lua un nombre (o identificador) es cualquier secuencia de letras latinas, dígitos y guiones bajos que no empiece por un dígito y que no sea una palabra reservada (Ierusalimschy et al., 2020, sección 3.1). El Mini-REPL adopta esa misma regla para sus nombres de variable. La función que la aplica es una línea con un patrón de texto:

```lua
local function is_identifier(lexeme)
    return lexeme:match("^[%a_][%w_]*$") ~= nil
end
```

(`src/tokenizer.lua`, líneas 45 a 47.) En los patrones de Lua, `%a` representa una letra y `%w` una letra o un dígito. El patrón exige entonces una letra o un guion bajo al principio, seguido de cualquier cantidad de letras, dígitos o guiones bajos. `contador_2` es un nombre válido; `5x` no lo es, y el programa lo rechaza con `[invalid_token] token inválido '5x' en la columna 1`.

Lua distingue tres clases de variables: globales, locales y campos de tabla (Ierusalimschy et al., 2020, sección 3.2). El detalle con mayor impacto en el proyecto es que todo nombre se considera global salvo que se declare con `local`. Un acceso a una global `x` equivale, según el manual, a leer `_ENV.x`, donde `_ENV` es la tabla que contiene el entorno global (sección 2.2). Esto quiere decir que un error de tipeo en el nombre de una variable no produce un error al cargar el archivo: Lua simplemente lee una global que no existe y obtiene `nil`.

Cada archivo declara con `local` todo lo que define y construye una tabla local `M` que devuelve al final. Así empieza el evaluador:

```lua
local Result = require("result")
local Errors = require("errors")
local Value = require("value")
local Environment = require("environment")
local Tokenizer = require("tokenizer")

local M = {}
```

(`src/evaluator.lua`, líneas 6 a 12.) La revisión de los ocho archivos con `luac -p -l` no muestra escrituras en la tabla global: las únicas lecturas marcadas con `_ENV` son nombres de la biblioteca estándar, como `require`, `string`, `table`, `math`, `pcall` o `print`.

`require` también tiene que ver con los nombres. La primera vez que se pide un módulo, Lua lo carga y guarda lo que devuelve en `package.loaded`; las siguientes veces devuelve ese mismo valor (Ierusalimschy et al., 2020, sección 6.3). Por eso el nombre `Value` en `evaluator.lua` y el nombre `Value` en `repl.lua` apuntan a la misma tabla, aunque cada archivo lo declare por su cuenta.

Las variables que escribe el usuario del Mini-REPL no son variables de Lua. Son claves de texto dentro de una tabla. Cuando alguien escribe `x 10 =`, el programa termina guardando el valor en `env.vars["x"]`. Por eso todo lo que sigue sobre vinculación y alcance tiene dos niveles: lo que hace Lua con los nombres del programa y lo que hace el programa con los nombres del usuario.

### 2.2 Vinculación

La vinculación (*binding*) es la asociación entre un nombre y aquello que designa: un valor, un lugar de memoria, un tipo o una operación. También importa cuándo se hace esa asociación: antes de que el programa empiece a ejecutarse o mientras corre.

En Lua, cuando el intérprete carga un archivo ya decide si cada nombre se refiere a una variable local o a una global, porque eso depende solo de dónde está escrito el `local`. El valor, en cambio, se asocia al nombre durante la ejecución, y el tipo no se asocia al nombre nunca: el manual dice que las variables no tienen tipo, solo los valores (Ierusalimschy et al., 2020, sección 2.1). Una misma variable de Lua puede guardar un número y, una línea más abajo, una tabla.

En el Mini-REPL hay tres vinculaciones que vale la pena separar.

La primera la hace el tokenizador al decidir qué clase de palabra es cada lexema (un lexema es el texto crudo de una palabra, por ejemplo `"-5"` o `"begin"`):

```lua
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
```

(`src/tokenizer.lua`, líneas 52 a 61.) El orden de las preguntas es deliberado. `end` cumple la forma de un identificador, pero se pregunta antes si es palabra reservada, así que nunca podrá usarse como nombre de variable; Lua hace lo mismo con sus propias palabras reservadas. `-` es operador, pero `-5` no está en la tabla de operadores y termina clasificado como número negativo.

La segunda vinculación asocia el nombre de una variable a su valor dentro del entorno. Ocurre en una sola función:

```lua
function M.define(env, name, value)
    env.vars[name] = value
    return Result.ok(value)
end
```

(`src/environment.lua`, líneas 60 a 63.)

La tercera decisión concierne al momento en que se lee el valor de una variable que aparece en la expresión. La palabra `x` puede cumplir dos papeles. En `x 5 +` hace falta su valor. En `x 10 =` hace falta su nombre, y puede que `x` todavía no exista. Ambos casos se resuelven con una sola regla: cuando el evaluador encuentra un identificador, apila una ficha que lleva el nombre y el valor que la variable tiene en ese instante.

```lua
function M.push_variable(name, stack, env)
    local current = Environment.lookup(env, name)
    return push(stack, Value.name(name, current))
end
```

(`src/evaluator.lua`, líneas 194 a 197.) Si la variable no existe, la ficha lleva `nil` como valor y no pasa nada todavía. El error aparece solo si alguien necesita ese valor, que es justo lo que hace `resolve`:

```lua
function M.resolve(item)
    if Value.is_name(item) then
        if item.value == nil then
            return Result.fail(Errors.new(
                Errors.Code.UNDEFINED_VARIABLE,
                string.format("la variable '%s' no está definida", item.name),
                item.name))
        end
        return Result.ok(item.value)
    end
    return Result.ok(item)
end
```

(`src/evaluator.lua`, líneas 40 a 51.) Como el valor se fija en el momento de apilar, `x x 1 + =` funciona: las dos fichas de `x` se crean antes de la asignación y ambas llevan el valor viejo, así que `x` pasa de 7 a 8. Un efecto menos evidente se observa en la consola. En `begin x 99 = x end`, la segunda `x` se apila cuando la variable local del bloque vale 99. Al cerrar el bloque esa variable desaparece, pero la ficha ya llevaba el 99, y eso es lo que se imprime:

```text
rpn> x 7 =
rpn> begin x 99 = x end
99
rpn> x
7
```

### 2.3 Estructuras de control

Lua tiene `if`, `while`, `repeat`, dos formas de `for` (una numérica y otra genérica que recorre lo que entrega una función iteradora), `break`, `return` y `goto` (Ierusalimschy et al., 2020, secciones 3.3.4 y 3.3.5). No tiene `switch`. Hay una regla que conviene tener presente al leer código Lua: en una condición solo `nil` y `false` cuentan como falso; el número 0 y el texto vacío cuentan como verdadero (sección 3.3.4). Por eso en el proyecto casi todas las condiciones comparan de forma explícita, con `~= nil` o `== nil`, en lugar de confiar en que un valor "vacío" sea falso.

El bucle principal del REPL usa `while true` y sale con `break`:

```lua
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
```

(`src/repl.lua`, líneas 66 a 100.) Hay dos salidas del bucle. Una es el comando `exit` (o `quit`). La otra es que `io.read` devuelva `nil`, cosa que pasa cuando se acaba la entrada; gracias a eso el programa termina limpio si se le pasa un archivo por tubería o si el usuario cierra la entrada (en la consola de Windows, con Ctrl+Z seguido de Enter).

La pila se vacía con este `for` numérico:

```lua
function M.clear(stack)
    for i = #stack, 1, -1 do
        stack[i] = nil
    end
end
```

(`src/repl.lua`, líneas 22 a 26.) El `for` genérico aparece en el tokenizador, donde `gmatch` entrega en cada vuelta la posición y el texto de la siguiente palabra:

```lua
    for column, lexeme in line:gmatch("()(%S+)") do
```

(`src/tokenizer.lua`, línea 68.) `%S+` significa "uno o más caracteres que no sean espacio", y `()` es una captura especial que devuelve la posición actual dentro del texto (Ierusalimschy et al., 2020, sección 6.4.1). Con esa posición el mensaje de error puede decir en qué columna está el token inválido.

Ante la ausencia de `switch` en Lua, el programa emplea dos sustitutos. El primero es una cadena de `if` y `elseif` en `eval`, la función principal del evaluador, que decide qué hacer según la clase de cada token:

```lua
function M.eval(tokens, stack, env)
    for _, token in ipairs(tokens) do
        local kind, lexeme = token.kind, token.lexeme
        local _, err

        if kind == Tokenizer.Kind.NUMBER then
            _, err = M.push_number(lexeme, stack)
        elseif kind == Tokenizer.Kind.BOOLEAN then
            _, err = M.push_bool(lexeme, stack)
        elseif kind == Tokenizer.Kind.IDENT then
            _, err = M.push_variable(lexeme, stack, env)
        elseif kind == Tokenizer.Kind.OPERATOR then
            _, err = M.apply_operator(lexeme, stack)
        elseif kind == Tokenizer.Kind.KEYWORD then
            local new_env
            new_env, err = run_keyword(lexeme, stack, env)
            if new_env then env = new_env end
        else
            err = Errors.new(Errors.Code.INVALID_TOKEN,
                string.format("token de clase desconocida '%s'", tostring(kind)), lexeme)
        end

        if err then
            return nil, err, env
        end
    end

    if #stack == 0 then
        return nil, nil, env
    end
    local top, err = M.resolve(stack[#stack])
    return top, err, env
end
```

(`src/evaluator.lua`, líneas 278 a 310.) El segundo sustituto es la tabla `OPERATORS` (sección 3.4), que asocia cada lexema con su función de aplicación.

La línea `if err then return nil, err, env end` se repite con variaciones en casi todas las funciones y es la forma en que se propaga el error. Dado que `return` debe ser la última instrucción de su bloque (sección 3.3.4), dentro de `if ... end` puede aparecer en cualquier punto de la función.

### 2.4 Reglas de alcance

El alcance de un nombre es la parte del programa en la que ese nombre se puede usar. Lua tiene alcance léxico: el alcance de una variable local empieza en la instrucción siguiente a su declaración y termina al final del bloque más interno que la contiene (Ierusalimschy et al., 2020, sección 3.5). "Léxico" quiere decir que basta con mirar el texto del programa para saber a qué variable se refiere cada nombre. El manual lo ilustra con varios `local x = x` anidados: cada bloque declara su propia `x` y la externa reaparece al cerrar.

Eso es el ocultamiento (*shadowing*): la variable del bloque tapa a la exterior mientras el bloque está abierto, pero no la modifica. Más abajo se muestra cómo se reproduce con `begin` y `end`.

Las variables del usuario no son variables de Lua (sección 2.1), por lo que el Mini-REPL construye su propio sistema de bloques. Cada entorno es una tabla con sus variables, una referencia a su entorno padre y un número que indica la profundidad:

```lua
function M.new(parent)
    return {
        parent = parent,
        vars = {},
        depth = parent and (parent.depth + 1) or 0,
    }
end
```

(`src/environment.lua`, líneas 19 a 25.) El entorno global no tiene padre y su profundidad es 0. Cada `begin` crea un entorno hijo del actual, y `end` devuelve el padre:

```lua
function M.open(current)
    if current.depth >= M.MAX_DEPTH then
        return Result.fail(Errors.new(
            Errors.Code.MAX_DEPTH_EXCEEDED,
            string.format("se alcanzó el límite de %d bloques anidados", M.MAX_DEPTH),
            "begin"))
    end
    return Result.ok(M.new(current))
end

function M.close(current)
    if current.parent == nil then
        return Result.fail(Errors.new(
            Errors.Code.NO_OPEN_BLOCK,
            "'end' sin 'begin': no hay ningún bloque abierto",
            "end"))
    end
    -- El bloque deja de estar referenciado y el recolector de basura de Lua
    -- libera su memoria más adelante.
    return Result.ok(current.parent)
end
```

`Environment.MAX_DEPTH` fija en 1000 el número máximo de bloques anidados: el bloque 1001 responde `[max_depth_exceeded]` en lugar de agotar la memoria y provocar un `internal_error`. El límite además acota el recorrido de `lookup` y `vars`.

(`src/environment.lua`, líneas 77 a 97.) Para buscar una variable se empieza por el entorno actual y se sube por la cadena de padres hasta encontrarla o llegar al final:

```lua
function M.lookup(env, name)
    local scope = env
    while scope ~= nil do
        local value = scope.vars[name]
        if value ~= nil then
            return value, scope
        end
        scope = scope.parent
    end
    return nil, nil
end
```

(`src/environment.lua`, líneas 36 a 46.) Esta búsqueda es la que produce el ocultamiento: si `x` existe en el bloque y en el global, se encuentra primero la del bloque y la búsqueda se detiene ahí.

La decisión central concierne al comportamiento de `=` dentro de un bloque cuando la variable ya existe afuera. El módulo define dos funciones. `define` (mostrada en 2.2) siempre escribe en el entorno actual. `set` busca dónde existe la variable y escribe allí, aunque sea en el global:

```lua
function M.set(env, name, value)
    local _, scope = M.lookup(env, name)
    if scope == nil then
        return undefined(name)
    end
    scope.vars[name] = value
    return Result.ok(value)
end
```

(`src/environment.lua`, líneas 68 a 75.) El evaluador emplea `define` deliberadamente. Con `set`, escribir `x 99 =` dentro de un bloque cambiaría la `x` global, lo cual está prohibido por el enunciado. `set` permanece en el módulo y se prueba en `tests/test_evaluator.lua` para mostrar la otra semántica posible, pero ninguna instrucción del Mini-REPL la usa. Comparado con Lua, el `=` del Mini-REPL se comporta como `local x = ...` dentro de un `do ... end`, y no como un `x = ...` sin `local`, que en Lua modificaría la variable externa.

Una sesión real con bloques anidados se ve así (el número entre corchetes del indicador es la profundidad del bloque):

```text
rpn> x 7 =
rpn> begin
rpn[1]> x
7
rpn[1]> x 1 =
rpn[1]> z 3 =
rpn[1]> x
1
rpn[1]> vars
x = 1 (int, bloque 1)
z = 3 (int, bloque 1)
rpn[1]> end
rpn> x
7
rpn> z
[undefined_variable] la variable 'z' no está definida
rpn> begin x 1 = begin x 2 =
rpn[2]> vars
x = 2 (int, bloque 2)
rpn[2]> end
rpn[1]> x
1
rpn[1]> end
rpn> x
7
```

El comando `vars` muestra cada nombre una sola vez, con el valor visible desde el bloque actual.

Hay un comportamiento que conviene señalar. Si una línea abre un bloque y después falla, el bloque queda abierto:

```text
rpn> begin 5 0 /
[division_by_zero] división por cero
rpn[1]>
```

El bloque queda abierto porque `eval` devuelve el entorno activo y el REPL lo adopta (`env = new_env`) aun con error: los tokens se ejecutan en orden y `begin` ya se había procesado. Revertirlo exigiría conservar una copia del entorno previo; una prueba automática fija este comportamiento.

## 3. Sistema de tipos y chequeo de tipos

### 3.1 Los tipos de Lua

Lua es un lenguaje de tipado dinámico (Scott, 2015; Sebesta, 2019). El manual lo define en dos frases: las variables no tienen tipo, solo los valores, y no existen definiciones de tipos en el lenguaje (Ierusalimschy et al., 2020, sección 2.1).

Hay ocho tipos básicos: `nil`, `boolean`, `number`, `string`, `function`, `userdata`, `thread` y `table`. Para este proyecto importan `number`, `boolean`, `string`, `function`, `table` y `nil`. El tipo `number` tiene dos subtipos, `integer` y `float`; en la versión estándar los enteros son de 64 bits y los decimales de doble precisión (sección 2.1). La función `math.type` dice cuál de los dos subtipos tiene un número (sección 6.7). Este ejemplo muestra cómo se comportan:

```lua
print(math.type(7), math.type(7.0), 2 == 2.0, 7/2, 8/2, 7//2)
```

```text
integer	float	true	3.5	4.0	3
```

La división `/` siempre produce un decimal, aunque el resultado sea exacto: `8/2` da `4.0`. La división entera `//` redondea hacia abajo (sección 3.4.1). Cuando una operación mezcla un entero y un decimal, el entero se convierte a decimal (sección 3.4.3).

### 3.2 Cómo comprueba los tipos Lua

Lua no hace chequeo estático: la comprobación ocurre durante la ejecución y no hay inferencia de tipos posible, porque las variables no tienen tipo (sección 2.1). La operación `5 + true` falla en ese instante:

```lua
local ok, e = pcall(function() return 5 + true end) print(ok, e)
```

```text
false	(command line):1: attempt to perform arithmetic on a boolean value
```

La equivalencia de tipos (la regla que decide cuándo dos tipos se consideran "el mismo") en Lua es simple porque el programador no puede declarar tipos nuevos. El operador `==` primero compara los tipos de los dos valores: si son distintos, el resultado es `false` sin error. Si son del mismo tipo, compara los valores. Dos números son iguales si representan el mismo valor matemático, por eso `2 == 2.0` es verdadero aunque uno sea entero y el otro decimal. Las tablas se comparan por referencia: dos tablas son iguales solo si son la misma tabla (Ierusalimschy et al., 2020, sección 3.4.4). Dos tablas con los mismos campos son, para Lua, dos objetos distintos del mismo tipo `table`.

Para el Mini-REPL esto tiene una consecuencia directa. Si la comprobación quedara en manos de Lua, `5 true +` produciría un error interno con un mensaje en inglés y `5 true ==` daría `false` sin aviso. El evaluador, en cambio, valida sus propias etiquetas antes de operar.

### 3.3 Una unión etiquetada para los valores de la pila

Una unión etiquetada (*tagged union*) es un registro que puede contener una de varias variantes y que lleva un campo, la etiqueta, que dice cuál de ellas contiene. Lenguajes como Rust la ofrecen directamente con `enum`. Lua no dispone de esa construcción, por lo que se representa con una tabla:

```lua
M.Kind = {
    INT = "int",
    FLOAT = "float",
    BOOL = "bool",
    NAME = "name",
}

-- Metatabla compartida por todos los valores. Define __tostring para que
-- tostring(v) y print(v) muestren el valor en lugar de "table: 0x...".
local ValueMeta = {}

local function tagged(kind, value)
    return setmetatable({ kind = kind, value = value }, ValueMeta)
end
```

(`src/value.lua`, líneas 11 a 24.) Nadie fuera de `value.lua` construye estas tablas a mano. Para crear un valor se usan funciones constructoras que, antes de crearlo, comprueban que el dato de Lua corresponda a la etiqueta:

```lua
function M.int(n)
    assert(math.type(n) == "integer", "value.int: se esperaba un entero")
    return tagged(M.Kind.INT, n)
end

function M.float(n)
    assert(type(n) == "number", "value.float: se esperaba un número")
    return tagged(M.Kind.FLOAT, n + 0.0)
end

function M.bool(b)
    assert(type(b) == "boolean", "value.bool: se esperaba un booleano")
    return tagged(M.Kind.BOOL, b)
end
```

(`src/value.lua`, líneas 26 a 39.) `assert` lanza un error si la condición es falsa. Estos `assert` no están pensados para los errores del usuario, sino para fallos de programación: si el evaluador intentara guardar un decimal en un `int`, el programa lo detectaría en el acto. `M.float` suma `0.0` al número para que Lua lo guarde siempre con el subtipo `float`, aunque reciba un entero.

La cuarta variante, `name`, es la ficha que se apila al encontrar un identificador (sección 2.2). No es un tipo del lenguaje del usuario en el mismo sentido que `int` o `bool`; existe para que la asignación pueda saber a qué variable escribir. Antes de cualquier operación, `resolve` la reemplaza por el valor que lleva dentro.

Los tokens usan la misma idea. Cada token es una tabla con una etiqueta de clase, el texto y la columna donde empieza:

```lua
M.Kind = {
    NUMBER = "number",
    BOOLEAN = "boolean",
    IDENT = "ident",
    OPERATOR = "operator",
    KEYWORD = "keyword",
}
```

(`src/tokenizer.lua`, líneas 10 a 16.) Las etiquetas son textos y no números, de modo que al imprimir un valor durante la depuración se lee `int` en lugar de un 1 que habría que buscar en una tabla.

### 3.4 Cómo comprueba los tipos el evaluador

Cada operador está descrito en una tabla con dos campos: `accepts`, que dice qué tipos admite, y `apply`, la función que hace la cuenta.

```lua
local OPERATORS = {
    ["+"]  = { accepts = "numbers", apply = function(a, b) return number_value("+", a, b, add_values(a, b)) end },
    ["-"]  = { accepts = "numbers", apply = function(a, b) return number_value("-", a, b, sub_values(a, b)) end },
    ["*"]  = { accepts = "numbers", apply = function(a, b) return number_value("*", a, b, mul_values(a, b)) end },
    ["/"]  = { accepts = "numbers", apply = divide },
    ["=="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value == b.value)) end },
    ["!="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value ~= b.value)) end },
    ["<"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value < b.value)) end },
    [">"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value > b.value)) end },
}
```

(`src/evaluator.lua`, líneas 140 a 149.) La comprobación la hace `check_types`, que mira solo las etiquetas:

```lua
local function check_types(op, accepts, a, b)
    local valid
    if accepts == "numbers" then
        valid = Value.is_number(a) and Value.is_number(b)
    else
        valid = (Value.is_number(a) and Value.is_number(b))
            or (Value.is_bool(a) and Value.is_bool(b))
    end
    if valid then
        return Result.ok(true)
    end
    return Result.fail(Errors.new(
        Errors.Code.TYPE_MISMATCH,
        string.format("el operador %s no se puede aplicar a %s y %s",
            op, Value.type_name(a), Value.type_name(b)),
        op))
end
```

(`src/evaluator.lua`, líneas 151 a 167.) La equivalencia de tipos del Mini-REPL es, entonces, por nombre de etiqueta: dos operandos son compatibles si sus etiquetas coinciden, con una excepción, que `int` y `float` se agrupan como "número". Es la misma relación que Lua establece entre sus subtipos `integer` y `float` dentro de `number`. La tabla siguiente resume las reglas que salen del código:

| Operador | Operandos que acepta | Tipo del resultado |
| --- | --- | --- |
| `+`, `-`, `*` | dos números | `int` si ambos son `int`; `float` si alguno es `float` |
| `/` | dos números | `int` si ambos son `int` y la división es exacta; `float` en otro caso; error si el divisor es 0 |
| `==`, `!=` | dos números o dos booleanos | `bool` |
| `<`, `>` | dos números | `bool` |

El evaluador es más estricto que Lua con `==`: en Lua `5 == true` da `false`, pero en el Mini-REPL `5 true ==` es un error de tipos, ya que comparar un número con un booleano suele indicar una expresión mal escrita. `<` y `>` tampoco aceptan booleanos, porque ordenar `true` y `false` carece de significado claro.

El orden de las comprobaciones dentro de `apply_operator` determina qué error ve el usuario cuando hay más de un problema:

```lua
function M.apply_operator(op, stack)
    local operator = OPERATORS[op]
    if operator == nil then
        return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
            string.format("operador desconocido '%s'", op), op))
    end
    if #stack < 2 then
        return underflow("el operador " .. op, 2, #stack)
    end

    -- En postfijo el operando derecho es el último que se apiló. Solo se
    -- desapilan después de validar: un error deja la pila como estaba.
    local right_item = stack[#stack]
    local left_item = stack[#stack - 1]

    local a, err_a = M.resolve(left_item)
    if err_a then return nil, err_a end
    local b, err_b = M.resolve(right_item)
    if err_b then return nil, err_b end

    local _, type_err = check_types(op, operator.accepts, a, b)
    if type_err then return nil, type_err end

    local result, op_err = operator.apply(a, b)
    if op_err then return nil, op_err end

    table.remove(stack)
    table.remove(stack)
    return push(stack, result)
end
```

(`src/evaluator.lua`, líneas 199 a 228.) Primero se verifica que haya dos valores en la pila, después que las variables existan, después los tipos y, por último, la operación en sí, que es donde se detecta la división por cero. Estas son salidas reales del programa:

```text
rpn> 5 true +
[type_mismatch] el operador + no se puede aplicar a int y bool
rpn> true 1 <
[type_mismatch] el operador < no se puede aplicar a bool y int
rpn> 5 true ==
[type_mismatch] el operador == no se puede aplicar a int y bool
rpn> true false <
[type_mismatch] el operador < no se puede aplicar a bool y bool
rpn> 2 2.0 ==
true
rpn> true false ==
false
```

### 3.5 Enteros y decimales

La regla del tipo del resultado para `+`, `-` y `*` vive en `number_value`, que además verifica el rango:

```lua
local function number_value(op, a, b, n)
    if int_pair(a, b) then
        if n == nil then
            return arithmetic_overflow(op,
                string.format("el resultado de %s excede el rango de enteros", op))
        end
        return Result.ok(Value.int(n))
    end
    if n ~= n or n == math.huge or n == -math.huge then
        return arithmetic_overflow(op,
            string.format("el resultado de %s excede el rango de flotantes", op))
    end
    return Result.ok(Value.float(n))
end
```

Lua calcula `n` con el subtipo correcto, porque opera dos enteros como entero y cualquier mezcla como decimal (Ierusalimschy et al., 2020, sección 3.4.1). La función traslada esa regla a las etiquetas del evaluador y convierte un resultado fuera de rango en el error `arithmetic_overflow`.

La división requiere un tratamiento aparte. En Lua `/` produce siempre un decimal, de modo que `8 2 /` daría `4.0`. El evaluador emplea la división entera `//` cuando ambos operandos son enteros y la división es exacta; además rechaza `math.mininteger / -1` y cualquier cociente `inf` o `NaN`:

```lua
local function divide(a, b)
    if b.value == 0 then
        return Result.fail(Errors.new(Errors.Code.DIVISION_BY_ZERO, "división por cero", "/"))
    end
    if int_pair(a, b) then
        if a.value == MIN_INT and b.value == -1 then
            return arithmetic_overflow("/", "math.mininteger / -1 excede el rango de enteros")
        end
        if a.value % b.value == 0 then
            return Result.ok(Value.int(a.value // b.value))
        end
    end
    local quotient = a.value / b.value
    if quotient ~= quotient or quotient == math.huge or quotient == -math.huge then
        return arithmetic_overflow("/", "el resultado de / excede el rango de flotantes")
    end
    return Result.ok(Value.float(quotient))
end
```

(`src/evaluator.lua`, líneas 117 a 135.) La condición `b.value == 0` también detecta `0.0`, porque para Lua `0.0 == 0` es verdadero. Así `5 0.0 /` da el mismo error que `5 0 /`, en lugar de devolver infinito.

Los números se leen con `tonumber`; un literal sin punto que no cabe en un entero de 64 bits se convierte en decimal (Ierusalimschy et al., 2020, sección 3.1), así que `push_number` lo rechaza para evitar que un entero se convierta silenciosamente en `float`.

El resultado de una operación también puede salirse del rango. Cuando una operación entre enteros se desborda, Lua hace que el resultado dé la vuelta (secciones 2.1 y 3.4.1). El Mini-REPL prefiere avisar:

```text
rpn> 9199999999999999999 1000000000000000000 +
[arithmetic_overflow] el resultado de + excede el rango de enteros
```

La revisión usa `math.maxinteger` y `math.mininteger` antes de operar; la resta, la multiplicación y la división entera cubren sus propios casos. El tokenizador no acepta notación científica, pero sí `.5` y `5.`.

## 4. Subrutinas, paso de parámetros y manejo de memoria

### 4.1 Funciones en Lua

En Lua las funciones son valores como cualquier otro: se pueden guardar en variables y en tablas, pasar como argumento y devolver como resultado (Ierusalimschy, 2016; Ierusalimschy et al., 2020, sección 2.1). La forma `function M.tokenize(line) ... end` es una abreviatura de `M.tokenize = function(line) ... end` (sección 3.4.11). Es decir, las funciones públicas de cada módulo son campos de la tabla `M`. Las privadas se declaran con `local function` y no se pueden usar desde otro archivo.

La tabla `OPERATORS` de la sección 3.4 aprovecha que las funciones son valores: cada entrada guarda una función anónima en el campo `apply`. Esas funciones usan `number_value`, `Value` y `Result`, que son variables locales del módulo declaradas fuera de ellas. Lua llama *upvalue* a una variable local de un nivel externo que una función interna usa (sección 3.5). Cada vez que se ejecuta `+`, la función anónima encuentra `number_value` a través de ese upvalue, sin que nadie se la pase como argumento.

### 4.2 Varios resultados y la convención (valor, error)

Una función de Lua puede devolver varios valores a la vez (Ierusalimschy et al., 2020, sección 3.3.4). Esa capacidad permite reportar errores sin excepciones. El contrato se resume en `result.lua`:

```lua
function M.ok(value)
    return value, nil
end

function M.fail(message)
    return nil, message
end
```

(`src/result.lua`, líneas 10 a 16.) La biblioteca estándar de Lua usa la misma idea: muchas de sus funciones devuelven "fail" (que hoy es `nil`) seguido de un mensaje de error cuando algo sale mal; la biblioteca de entrada y salida, por ejemplo, lo hace en todas sus funciones (secciones 6 y 6.8). Se sigue esa costumbre en lugar de introducir un objeto `Result` con métodos, que en Lua habría resultado superfluo.

Cuando una función devuelve más valores de los que quien la llama recibe, los sobrantes se descartan, y si devuelve menos, los que faltan se rellenan con `nil` (sección 3.4.12). El proyecto se apoya en esa regla en varios sitios. `Environment.get` necesita solo el valor y escribe `local value = M.lookup(env, name)`, aunque `lookup` también devuelve el entorno donde encontró la variable. En sentido contrario, `apply_operator` recibe dos resultados de `check_types` y descarta el primero con el nombre `_`, una convención de Lua para indicar que el valor se descarta.

`Evaluator.eval` tiene un tercer resultado, el entorno activo al terminar, necesario porque reasignar el parámetro `env` no altera la variable del llamador (sección 4.3).

Para los errores no previstos, como un fallo de programación, el REPL envuelve la evaluación en `pcall`. `pcall` ejecuta una función en modo protegido: si dentro se lanza un error, no se propaga; `pcall` lo atrapa y devuelve `false` y el error (Ierusalimschy et al., 2020, secciones 2.3 y 6.1). En el bucle de la sección 2.3 se ve cómo un fallo interno se convierte en un mensaje con el código `internal_error` y el REPL sigue funcionando.

### 4.3 Paso de parámetros

Pasar un parámetro por valor significa que la función recibe una copia y lo que haga con ella no afecta al original. Pasarlo por referencia significa que la función recibe acceso a la variable original y puede cambiarla.

Lua no encaja limpio en ninguna de las dos. El manual dice que los parámetros se comportan como variables locales inicializadas con los valores de los argumentos (Ierusalimschy et al., 2020, sección 3.4.11), lo que suena a paso por valor. Pero también dice que las tablas, las funciones y los hilos son objetos y que las variables no los contienen, sino que guardan referencias a ellos: la asignación, el paso de parámetros y el retorno de funciones manipulan esas referencias sin copiar nada (sección 2.1). El resultado combinado es que la función recibe una copia de la referencia. Puede modificar el contenido de una tabla recibida, y el cambio lo ve quien la llamó. Lo que no puede hacer es cambiar a qué tabla apunta la variable de quien la llamó.

Este ejemplo muestra las dos caras:

```lua
local function cambiar(n, t)
    n = n + 1
    t[1] = "modificado"
end

local numero, tabla = 5, { "original" }
cambiar(numero, tabla)
print(numero, tabla[1])
```

```text
5	modificado
```

El número no cambió; el contenido de la tabla sí. Lua no tiene punteros a variables ni un mecanismo de préstamo como el de Rust, así que no hay forma de pasar "la variable misma".

El enunciado pide pasar la pila y la tabla de símbolos de forma explícita a las subrutinas. El paso explícito se mantiene en todas las funciones que las usan: `push_number(lexeme, stack)`, `push_variable(name, stack, env)`, `apply_operator(op, stack)`, `assign(stack, env)` y `eval(tokens, stack, env)`. La pila muestra el primer caso del ejemplo. `push` agrega un elemento a la tabla que recibe:

```lua
local function push(stack, value)
    stack[#stack + 1] = value
    return Result.ok(value)
end
```

(`src/evaluator.lua`, líneas 33 a 36.) `#stack` es el operador de longitud, que en una tabla usada como arreglo da la posición del último elemento (Ierusalimschy et al., 2020, sección 3.4.7). Para retirar elementos se usa `table.remove(stack)`, que sin un segundo argumento quita el último (sección 6.6). En `apply_operator` y `assign` los operandos se leen antes de retirarse. Ninguna de estas funciones devuelve la pila: la modifican en su lugar y el REPL ve los cambios porque comparte la misma tabla. Por la misma razón `REPL.clear` borra los elementos uno por uno en vez de hacer `stack = {}`: esa asignación solo cambiaría la variable local de `clear` y dejaría intacta la pila del REPL. Las pruebas lo confirman:

```lua
local stack = {}
Evaluator.push_number("5", stack)
Evaluator.push_number("2", stack)
check("push_number modifica la pila del llamador", #stack == 2)
Evaluator.apply_operator("+", stack)
check("apply_operator deja un solo valor en la misma pila",
    #stack == 1 and stack[1].value == 7)
REPL.clear(stack)
check("clear vacía la misma tabla", #stack == 0)
```

(`tests/test_evaluator.lua`, líneas 172 a 178 y 187 a 188.)

El entorno muestra el segundo caso del ejemplo. Agregar o cambiar una variable modifica la tabla `env.vars`, y el cambio es visible desde fuera. Pero `begin` y `end` no modifican el entorno: cambian cuál es el entorno activo. Dentro de `eval`, la línea `if new_env then env = new_env end` reasigna la variable local `env`, y esa reasignación no llega al REPL. Por eso `eval` devuelve el entorno como tercer resultado y el REPL lo guarda con `env = new_env`. Las pruebas verifican que la variable de quien llama queda igual:

```lua
local caller_env = Environment.new(nil)
local _, _, returned_env = Evaluator.eval(Tokenizer.tokenize("begin"), {}, caller_env)
check("eval no cambia la variable del llamador; devuelve el entorno nuevo",
    caller_env.depth == 0 and returned_env.parent == caller_env)
```

(`tests/test_evaluator.lua`, líneas 190 a 193.)

Compartir referencias tiene un riesgo: si dos partes del programa guardan la misma tabla y una la modifica, la otra ve el cambio inesperadamente. Después de `y x =`, la variable `y` guarda exactamente la misma tabla de valor que `x`, no una copia. El riesgo se evita tratando los valores como inmutables: una vez creados no se modifican. La convención está registrada al principio de `value.lua`:

```lua
-- Los valores se tratan como inmutables: una vez creados nunca se modifican.
-- Por eso es seguro que la pila y el entorno compartan la misma tabla.
```

(`src/value.lua`, líneas 6 y 7.) Cuando `x` cambia, `define` guarda una tabla de valor nueva en `env.vars["x"]`, y la que comparte `y` queda como estaba. Lua no tiene forma de hacer cumplir esta regla; es una convención del proyecto. Los textos de Lua, en cambio, sí son inmutables por definición del lenguaje (Ierusalimschy et al., 2020, sección 2.1).

### 4.4 Manejo de memoria

Lua administra la memoria de forma automática. El programador no reserva ni libera memoria: un recolector de basura busca los objetos que el programa ya no puede alcanzar y los libera (Ierusalimschy et al., 2020, sección 2.5). Un objeto es inalcanzable cuando ninguna variable ni ningún otro objeto vivo lo referencia. El manual aclara que no hay garantía sobre el momento exacto: solo promete que no liberará nada que todavía se pueda usar y que tarde o temprano liberará lo inalcanzable.

En el Mini-REPL se crea una tabla por token y otra por valor apilado, sin liberación manual. El caso interesante es el de los bloques. Cuando `end` ejecuta `Environment.close`, devuelve el padre y el REPL guarda ese padre como entorno activo. Nada apunta ya al bloque que se cerró (los hijos apuntan al padre, nunca al revés), así que el bloque y todas sus variables locales quedan disponibles para el recolector.

La liberación se comprobó con una tabla débil: una tabla cuyas referencias el recolector ignora, de modo que si un objeto solo está referenciado desde una tabla débil, el recolector lo libera igual. La debilidad se activa con el campo `__mode` de su metatabla (sección 2.5.4). La prueba guarda el bloque en una tabla débil, lo cierra, fuerza el recolector con `collectgarbage` y verifica que el bloque desapareció:

```lua
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
```

(`tests/test_evaluator.lua`, líneas 196 a 208.) Se invoca dos veces a `collectgarbage` para no depender de la fase del ciclo. La pila, en cambio, es una sola tabla que `clear` reutiliza en cada línea.

## 5. Abstracción de datos y equivalente de la programación orientada a objetos

Lua no tiene clases ni interfaces como construcciones del lenguaje. Lo que tiene son tablas, que el manual describe como el único mecanismo para estructurar datos; con ellas se representan arreglos, registros, conjuntos y tablas de símbolos, y como sus campos pueden contener funciones, también pueden llevar métodos (Ierusalimschy et al., 2020, sección 2.1). A eso se suman las metatablas: tablas comunes que, asociadas a un valor, definen cómo se comporta ese valor ante ciertas operaciones (sección 2.4). Con estas dos piezas se puede imitar casi cualquier estilo de programación orientada a objetos. El proyecto emplea solo lo que necesita.

La abstracción de datos consiste en ofrecer un tipo a través de un conjunto de operaciones, ocultando cómo está guardado por dentro. En el proyecto la unidad de abstracción es el módulo. `value.lua` es el mejor ejemplo: expone constructores (`int`, `float`, `bool`, `name`), preguntas sobre el tipo (`is_number`, `is_bool`, `is_name`, `type_name`) y la conversión a texto (`tostring`). La función `tagged`, que arma la tabla, es local y no se puede llamar desde fuera. El ocultamiento no es completo: Lua no impide leer campos, y el evaluador lee `a.value` y `a.kind` directamente. Escribir un getter para cada campo solo habría alargado el código.

Las metatablas cumplen el papel de un comportamiento compartido, parecido a un método definido una sola vez en una clase. Todos los valores comparten la metatabla `ValueMeta`, y todos los errores comparten `ErrorMeta`. Ambas definen `__tostring`, que es el campo que consulta la función `tostring` de Lua para convertir un valor a texto (Ierusalimschy et al., 2020, sección 6.1):

```lua
ValueMeta.__tostring = M.tostring
```

(`src/value.lua`, línea 81.)

```lua
local ErrorMeta = {}

function M.new(code, message, detail)
    return setmetatable({
        code = code,
        message = message,
        detail = detail,
    }, ErrorMeta)
end

function M.format(err)
    if type(err) ~= "table" then
        return tostring(err)
    end
    return string.format("[%s] %s", err.code or "?", err.message or "")
end

ErrorMeta.__tostring = M.format
```

(`src/errors.lua`, líneas 20 a 37.) Sin esa metatabla, `print` sobre un valor mostraría algo como `table: 0x...`. Con ella muestra `2.5` o `[division_by_zero] división por cero`. Dos pruebas lo verifican (`tests/test_evaluator.lua`, líneas 211 a 213).

Lua ofrece una sintaxis con dos puntos para imitar métodos: `env:lookup(name)` equivale a `env.lookup(env, name)`, y al definir la función con `:` se agrega un parámetro oculto llamado `self` (sección 3.4.11). No se emplea esa sintaxis: al escribir `Environment.lookup(env, name)` el entorno queda como primer argumento visible, como pide el requisito 3 del enunciado. Con los dos puntos, ese paso quedaría oculto.

El polimorfismo —tratar de la misma forma objetos distintos que responden a las mismas operaciones— se apoya en la tabla `OPERATORS`. Cada entrada tiene la misma forma, un campo `accepts` y una función `apply` que recibe dos valores y devuelve `(valor, error)`. `apply_operator` no sabe qué operador está aplicando: busca la entrada, consulta `accepts` y llama a `apply`. Agregar un operador nuevo, por ejemplo `<=`, sería agregar una línea a la tabla y su lexema al tokenizador, sin tocar `apply_operator`. Es lo que en otros lenguajes se haría con una interfaz; en Lua basta con que las tablas tengan los mismos campos.

El contrato `(valor, error)` funciona como una segunda interfaz, esta vez entre módulos. El tokenizador, el entorno y el evaluador cumplen la misma regla, y por eso el REPL puede tratar todos los errores igual sin importar dónde nacieron.

La herencia tiene un equivalente parcial en la cadena de entornos. Un bloque que no encuentra una variable se la pide a su padre, que es la misma idea de la delegación entre prototipos. Lua trae un mecanismo para eso, el campo `__index` de la metatabla (sección 2.4): si la tabla de variables de un bloque tuviera una metatabla con `__index` apuntando a la del padre, la búsqueda subiría sola cuando la clave no estuviera. Se descartó: era necesario saber en qué entorno se encontró cada variable, para que `vars` pudiera mostrar si es global o de un bloque y para que `set` supiera dónde escribir, y con `__index` esa información se pierde. El bucle explícito de `lookup` la devuelve como segundo resultado.

## 6. Cumplimiento de los requisitos técnicos de la Parte II

Las secciones 2 a 5 explican el código que cumple cada punto del enunciado. A continuación se reúnen con una salida real:

| Requisito | Dónde está | Ejemplo |
| --- | --- | --- |
| Evaluación en pila y errores | secciones 2.3 y 4.2 | `5 0 /` → `[division_by_zero] división por cero` |
| Tipos del evaluador | sección 3.4 | `5 true +` → `[type_mismatch] ... int y bool` |
| Variables y paso de parámetros | secciones 2.2 y 4.3 | `x 5 2 + =`, y `eval` devuelve el entorno nuevo |
| Alcance local | sección 2.4 | `begin x 99 = x end` → `99`, y `x` vuelve a 7 al cerrar |

Los errores esperados son estos:

| Entrada | Salida |
| --- | --- |
| `5 0 /` | `[division_by_zero] división por cero` |
| `5 +` | `[stack_underflow] el operador + necesita 2 valores y la pila tiene 1` |
| `x =` | `[stack_underflow] la asignación = necesita 2 valores y la pila tiene 1` |
| `9199999999999999999 1000000000000000000 +` | `[arithmetic_overflow] el resultado de + excede el rango de enteros` |
| `3 #` | `[invalid_token] token inválido '#' en la columna 3` |
| `1 vars` | `[invalid_token] 'vars' es un comando y debe escribirse solo en la línea` |
| `99999999999999999999` | `[invalid_token] el entero '99999999999999999999' está fuera del rango permitido` |
| `y` (sin definir) | `[undefined_variable] la variable 'y' no está definida` |
| `5 3 =` | `[invalid_assignment] antes del valor debe ir el nombre de una variable, pero se encontró un int` |
| `end` (sin bloque) | `[no_open_block] 'end' sin 'begin': no hay ningún bloque abierto` |
| 1001 `begin` seguidos | `[max_depth_exceeded] se alcanzó el límite de 1000 bloques anidados` |

Si una línea deja más de un valor en la pila se imprime el de arriba: `1 2 3` imprime `3`. Las pruebas de `tests/test_evaluator.lua` son la misma sesión que aparece en el `README.md`: `REPL.run` recibe las funciones de entrada, salida e indicador como parámetros, así que la prueba puede alimentar el REPL con una lista de líneas en lugar del teclado.

## 7. Bibliografía

Hamblin, C. L. (1962). Translation to and from Polish notation. *The Computer Journal, 5*(3), 210-212.

Ierusalimschy, R. (2016). *Programming in Lua* (4.ª ed.). Lua.org.

Ierusalimschy, R., de Figueiredo, L. H., & Celes, W. (2020). *Lua 5.4 reference manual*. Lua.org; PUC-Rio. Recuperado el 22 de noviembre de 2026, de https://www.lua.org/manual/5.4/

Scott, M. L. (2015). *Programming language pragmatics* (4.ª ed.). Morgan Kaufmann.

Sebesta, R. W. (2019). *Concepts of programming languages* (12.ª ed.). Pearson.

Universidad de Carabobo, Facultad Experimental de Ciencias y Tecnología. (2026). *Asignación #1: CAO604 Lenguajes de Programación, semestre 1-2026* [Enunciado de la asignación].
