# Mini-REPL en notación polaca inversa escrito en Lua 5.4

## Reporte técnico (Parte I)

Universidad de Carabobo

Facultad Experimental de Ciencias y Tecnología

CAO604 Lenguajes de Programación

Asignación #1, semestre 1-2026

Integrantes: (completar)

Repositorio: https://github.com/l1nk26/proyecto-lenguajes-de-programacion

## 1. Cómo está armado el programa

El Mini-REPL es un programa de consola. Muestra un indicador (`rpn> `), espera a que el usuario escriba una línea, la evalúa e imprime el resultado; después vuelve a mostrar el indicador. Ese ciclo de leer, evaluar, imprimir y repetir es lo que da nombre a un REPL (por las siglas en inglés de *read, eval, print, loop*).

Las expresiones se escriben en notación polaca inversa, también llamada postfija: primero van los operandos y después el operador. Lo que en la escuela escribimos como `(x + 5) * 2` aquí se escribe `x 5 + 2 *`, tal como lo exige el enunciado (Universidad de Carabobo, 2026). Para evaluar esa notación se usa una pila, que funciona como una pila de platos: el último valor que se coloca encima es el primero que se retira. Cada número se coloca en la pila y cada operador retira los dos valores de arriba, hace la cuenta y coloca el resultado.

Separamos el programa en ocho archivos dentro de `src/`. Cada uno es un módulo, es decir, un archivo de Lua que agrupa funciones relacionadas y las entrega a quien lo pida con `require`.

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

(`src/repl.lua`, líneas 28 a 35.) El tokenizador convierte el texto en una lista de *tokens*, que son las palabras de la línea ya clasificadas. Si alguna palabra no encaja en ninguna clase, la línea se rechaza antes de evaluar nada. Si todas son válidas, el evaluador recorre los tokens de izquierda a derecha y, al terminar, devuelve el valor que quedó encima de la pila. El REPL lo imprime y espera la siguiente línea.

Decidimos que cada línea sea una expresión independiente: la pila se vacía antes de evaluar cada línea. Lo que sí sobrevive de una línea a otra es el entorno, o sea, las variables definidas y los bloques que sigan abiertos. Así `x 10 =` en una línea y `x 1 +` en la siguiente funcionan como uno espera, y un error en una línea no deja basura en la pila para la próxima.

Lua no tiene un paso de compilación separado. El intérprete carga cada archivo, lo traduce a instrucciones de su máquina virtual y las ejecuta en el mismo momento (Ierusalimschy et al., 2020, §3.3.2). Por eso basta con ejecutar, desde la raíz del repositorio:

```text
lua src/main.lua
```

Todas las pruebas de este reporte se hicieron con el intérprete Lua 5.4.6 en Windows 11. El archivo de pruebas se ejecuta con `lua tests/test_evaluator.lua` y en nuestra última corrida imprimió `86 pruebas correctas, 0 fallidas`.

## 2. Nombres, vinculación, estructuras de control y alcance

### 2.1 Nombres en Lua y en el proyecto

En Lua un nombre (o identificador) es cualquier secuencia de letras latinas, dígitos y guiones bajos que no empiece por un dígito y que no sea una palabra reservada (Ierusalimschy et al., 2020, §3.1). Copiamos esa misma regla para los nombres de variable del Mini-REPL. La función que la aplica es una línea con un patrón de texto:

```lua
local function is_identifier(lexeme)
    return lexeme:match("^[%a_][%w_]*$") ~= nil
end
```

(`src/tokenizer.lua`, líneas 45 a 47.) En los patrones de Lua, `%a` representa una letra y `%w` una letra o un dígito. El patrón exige entonces una letra o un guion bajo al principio, seguido de cualquier cantidad de letras, dígitos o guiones bajos. `contador_2` es un nombre válido; `5x` no lo es, y el programa lo rechaza con `[invalid_token] token inválido '5x' en la columna 1`.

Lua distingue tres clases de variables: globales, locales y campos de tabla (Ierusalimschy et al., 2020, §3.2). El detalle que más nos afectó es que todo nombre se considera global salvo que se declare con `local`. Un acceso a una global `x` equivale, según el manual, a leer `_ENV.x`, donde `_ENV` es la tabla que contiene el entorno global (§2.2). Esto quiere decir que un error de tipeo en el nombre de una variable no produce un error al cargar el archivo: Lua simplemente lee una global que no existe y obtiene `nil`.

Para no caer en eso declaramos con `local` todo lo que define cada archivo, y cada módulo construye una tabla local `M` que devuelve al final. Así empieza el evaluador:

```lua
local Result = require("result")
local Errors = require("errors")
local Value = require("value")
local Environment = require("environment")
local Tokenizer = require("tokenizer")

local M = {}
```

(`src/evaluator.lua`, líneas 6 a 12.) Quisimos comprobar que de verdad no se nos había escapado ninguna global. El compilador `luac`, que viene con el intérprete, puede listar las instrucciones de máquina virtual en las que se traduce cada archivo (`luac -p -l archivo.lua`). Las instrucciones que leen o escriben en la tabla global aparecen marcadas con `_ENV`. Al revisar los ocho archivos de `src/` no encontramos ninguna escritura en la tabla global. Las únicas lecturas son de nombres de la biblioteca estándar, como `require`, `string`, `table`, `math`, `pcall` o `print`.

`require` también tiene que ver con los nombres. La primera vez que se pide un módulo, Lua lo carga y guarda lo que devuelve en `package.loaded`; las siguientes veces devuelve ese mismo valor (Ierusalimschy et al., 2020, §6.3). Por eso el nombre `Value` en `evaluator.lua` y el nombre `Value` en `repl.lua` apuntan a la misma tabla, aunque cada archivo lo declare por su cuenta.

Las variables que escribe el usuario del Mini-REPL no son variables de Lua. Son claves de texto dentro de una tabla. Cuando alguien escribe `x 10 =`, el programa termina guardando el valor en `env.vars["x"]`. Por eso todo lo que sigue sobre vinculación y alcance tiene dos niveles: lo que hace Lua con los nombres de nuestro código y lo que hace nuestro código con los nombres del usuario.

### 2.2 Vinculación

La vinculación (*binding*) es la asociación entre un nombre y aquello que designa: un valor, un lugar de memoria, un tipo o una operación. También importa cuándo se hace esa asociación: antes de que el programa empiece a ejecutarse o mientras corre.

En Lua, cuando el intérprete carga un archivo ya decide si cada nombre se refiere a una variable local o a una global, porque eso depende solo de dónde está escrito el `local`. El valor, en cambio, se asocia al nombre durante la ejecución, y el tipo no se asocia al nombre nunca: el manual dice que las variables no tienen tipo, solo los valores (Ierusalimschy et al., 2020, §2.1). Una misma variable de Lua puede guardar un número y, una línea más abajo, una tabla.

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

(`src/environment.lua`, líneas 56 a 59.)

La tercera nos costó más decidirla: en qué momento se lee el valor de una variable que aparece en la expresión. La palabra `x` puede cumplir dos papeles. En `x 5 +` hace falta su valor. En `x 10 =` hace falta su nombre, y puede que `x` todavía no exista. Resolvimos los dos casos con una sola regla: cuando el evaluador encuentra un identificador, apila una ficha que lleva el nombre y el valor que la variable tiene en ese instante.

```lua
function M.push_variable(name, stack, env)
    local current = Environment.lookup(env, name)
    return push(stack, Value.name(name, current))
end
```

(`src/evaluator.lua`, líneas 117 a 120.) Si la variable no existe, la ficha lleva `nil` como valor y no pasa nada todavía. El error aparece solo si alguien necesita ese valor, que es justo lo que hace `resolve`:

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

(`src/evaluator.lua`, líneas 28 a 39.) Como el valor se fija en el momento de apilar, `x x 1 + =` funciona: las dos fichas de `x` se crean antes de la asignación y ambas llevan el valor viejo, así que `x` pasa de 7 a 8. Hay un efecto menos evidente que comprobamos en la consola. En `begin x 99 = x end`, la segunda `x` se apila cuando la variable local del bloque vale 99. Al cerrar el bloque esa variable desaparece, pero la ficha ya llevaba el 99, y eso es lo que se imprime:

```text
rpn> x 7 =
rpn> begin x 99 = x end
99
rpn> x
7
```

### 2.3 Estructuras de control

Lua tiene `if`, `while`, `repeat`, dos formas de `for` (una numérica y otra genérica que recorre lo que entrega una función iteradora), `break`, `return` y `goto` (Ierusalimschy et al., 2020, §3.3.4 y §3.3.5). No tiene `switch`. Hay una regla que conviene tener presente al leer código Lua: en una condición solo `nil` y `false` cuentan como falso; el número 0 y el texto vacío cuentan como verdadero (§3.3.4). Por eso en el proyecto casi todas las condiciones comparan de forma explícita, con `~= nil` o `== nil`, en lugar de confiar en que un valor "vacío" sea falso.

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

Para vaciar la pila usamos el `for` numérico con paso negativo, que recorre los índices desde el último hasta el primero:

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

(`src/tokenizer.lua`, línea 68.) `%S+` significa "uno o más caracteres que no sean espacio", y `()` es una captura especial que devuelve la posición actual dentro del texto (Ierusalimschy et al., 2020, §6.4.1). Con esa posición el mensaje de error puede decir en qué columna está el token inválido.

Como Lua no tiene `switch`, usamos dos sustitutos. El primero es una cadena de `if` y `elseif` en `eval`, la función principal del evaluador, que decide qué hacer según la clase de cada token:

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

(`src/evaluator.lua`, líneas 194 a 226.) El segundo sustituto es una tabla de despacho para los operadores, que veremos en la sección 3.4: en vez de preguntar "¿es `+`?, ¿es `-`?", se busca el operador como clave en una tabla y se obtiene directamente la función que lo implementa.

La línea `if err then return nil, err, env end` se repite con variaciones en casi todas las funciones. Es la forma en que propagamos los errores: en cuanto algo falla, la función se detiene y devuelve el error a quien la llamó. El manual exige que `return` sea la última instrucción de su bloque (§3.3.4); dentro de un `if ... end` lo es, así que el patrón es válido en cualquier punto de la función.

### 2.4 Reglas de alcance

El alcance de un nombre es la parte del programa en la que ese nombre se puede usar. Lua tiene alcance léxico: el alcance de una variable local empieza en la instrucción siguiente a su declaración y termina al final del bloque más interno que la contiene (Ierusalimschy et al., 2020, §3.5). "Léxico" quiere decir que basta con mirar el texto del programa para saber a qué variable se refiere cada nombre. El manual lo ilustra con este ejemplo, que copiamos tal cual porque no pertenece al proyecto:

```lua
x = 10                -- global variable
do                    -- new block
  local x = x         -- new 'x', with value 10
  print(x)            --> 10
  x = x+1
  do                  -- another block
    local x = x+1     -- another 'x'
    print(x)          --> 12
  end
  print(x)            --> 11
end
print(x)              --> 10  (the global one)
```

El ejemplo también muestra el ocultamiento (*shadowing*): cuando un bloque interno declara una variable con el mismo nombre que una externa, dentro del bloque el nombre se refiere a la nueva y la externa queda tapada, pero no modificada. Al salir del bloque la externa reaparece con su valor de siempre.

Las reglas de alcance de Lua no nos servían directamente, porque, como dijimos en 2.1, las variables del usuario no son variables de Lua. Tuvimos que construir nuestro propio sistema de bloques. Cada entorno es una tabla con sus variables, una referencia a su entorno padre y un número que indica la profundidad:

```lua
function M.new(parent)
    return {
        parent = parent,
        vars = {},
        depth = parent and (parent.depth + 1) or 0,
    }
end
```

(`src/environment.lua`, líneas 15 a 21.) El entorno global no tiene padre y su profundidad es 0. Cada `begin` crea un entorno hijo del actual, y `end` devuelve el padre:

```lua
function M.open(current)
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

(`src/environment.lua`, líneas 73 a 87.) Para buscar una variable se empieza por el entorno actual y se sube por la cadena de padres hasta encontrarla o llegar al final:

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

(`src/environment.lua`, líneas 32 a 42.) Esta búsqueda es la que produce el ocultamiento: si `x` existe en el bloque y en el global, se encuentra primero la del bloque y la búsqueda se detiene ahí.

La decisión importante fue qué debía hacer `=` dentro de un bloque cuando la variable ya existe afuera. Escribimos dos funciones. `define` (mostrada en 2.2) siempre escribe en el entorno actual. `set` busca dónde existe la variable y escribe allí, aunque sea en el global:

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

(`src/environment.lua`, líneas 64 a 71.) El evaluador usa `define` a propósito. Con `set`, escribir `x 99 =` dentro de un bloque cambiaría la `x` global, y eso es justo lo que el enunciado prohíbe. Dejamos `set` en el módulo y la probamos en `tests/test_evaluator.lua` porque muestra la otra semántica posible, pero ninguna instrucción del Mini-REPL la usa. Comparado con Lua, nuestro `=` se comporta como `local x = ...` dentro de un `do ... end`, y no como un `x = ...` sin `local`, que en Lua modificaría la variable externa.

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

Dentro del bloque se ve la `x` global hasta que el bloque define la suya. Al cerrar el bloque la `x` global sigue valiendo 7 y la `z` local ya no existe. El comando `vars` muestra cada nombre una sola vez, con el valor que se ve desde el bloque actual.

En el Mini-REPL no hay funciones definidas por el usuario, así que no se presenta la diferencia entre alcance léxico y alcance dinámico (en el dinámico el nombre se busca según quién llamó a quién durante la ejecución, no según el texto). Los bloques se anidan en el orden en que se escriben y la búsqueda sigue ese anidamiento.

Hay un comportamiento que discutimos bastante. Si una línea abre un bloque y después falla, el bloque queda abierto:

```text
rpn> begin 5 0 /
[division_by_zero] división por cero
rpn[1]>
```

Ocurre porque `eval` devuelve el entorno que estaba activo cuando apareció el error y el REPL lo adopta (`env = new_env`) aunque haya error. Lo dejamos así porque los tokens se ejecutan de izquierda a derecha y `begin` ya se había ejecutado cuando llegó la división. Deshacerlo habría exigido guardar una copia del entorno antes de cada línea. El indicador `rpn[1]>` deja claro que el bloque sigue abierto, y una prueba automática fija este comportamiento para que no cambie sin querer.

## 3. Sistema de tipos y chequeo de tipos

### 3.1 Los tipos de Lua

Lua es un lenguaje de tipado dinámico. El manual lo define en dos frases: las variables no tienen tipo, solo los valores, y no existen definiciones de tipos en el lenguaje (Ierusalimschy et al., 2020, §2.1). Dicho de otra forma, el programador nunca escribe "esta variable es un número"; cada valor sabe de qué tipo es y Lua lo comprueba en el momento de usarlo.

Hay ocho tipos básicos: `nil`, `boolean`, `number`, `string`, `function`, `userdata`, `thread` y `table`. Para este proyecto importan `number`, `boolean`, `string`, `function`, `table` y `nil`. El tipo `number` tiene dos subtipos, `integer` y `float`; en la versión estándar los enteros son de 64 bits y los decimales de doble precisión (§2.1). La función `math.type` dice cuál de los dos subtipos tiene un número (§6.7). Este ejemplo ilustrativo, que no pertenece al proyecto, muestra cómo se comportan:

```lua
print(math.type(7), math.type(7.0), 2 == 2.0, 7/2, 8/2, 7//2)
```

```text
integer	float	true	3.5	4.0	3
```

La división `/` siempre produce un decimal, aunque el resultado sea exacto: `8/2` da `4.0`. La división entera `//` redondea hacia abajo (§3.4.1). Cuando una operación mezcla un entero y un decimal, el entero se convierte a decimal (§3.4.3).

### 3.2 Cómo comprueba los tipos Lua

Lua no hace chequeo estático, es decir, no revisa los tipos antes de ejecutar el programa. Tampoco tiene inferencia de tipos en el sentido de lenguajes como Haskell o Rust, donde el compilador deduce el tipo de una variable que el programador no anotó: como las variables de Lua no tienen tipo, no hay nada que deducir. Toda la comprobación ocurre durante la ejecución. Si sumamos un número y un booleano, Lua lanza un error en ese momento. Lo verificamos con este ejemplo ilustrativo:

```lua
local ok, e = pcall(function() return 5 + true end) print(ok, e)
```

```text
false	(command line):1: attempt to perform arithmetic on a boolean value
```

La equivalencia de tipos (la regla que decide cuándo dos tipos se consideran "el mismo") en Lua es simple porque el programador no puede declarar tipos nuevos. El operador `==` primero compara los tipos de los dos valores: si son distintos, el resultado es `false` sin error. Si son del mismo tipo, compara los valores. Dos números son iguales si representan el mismo valor matemático, por eso `2 == 2.0` es verdadero aunque uno sea entero y el otro decimal. Las tablas se comparan por referencia: dos tablas son iguales solo si son la misma tabla (Ierusalimschy et al., 2020, §3.4.4). Dos tablas con los mismos campos son, para Lua, dos objetos distintos del mismo tipo `table`.

Para el Mini-REPL esto tiene una consecuencia directa. Si dejáramos que Lua comprobara los tipos, `5 true +` produciría un error interno con un mensaje en inglés, y `5 true ==` daría `false` sin quejarse. Preferimos que el evaluador tenga su propio sistema de tipos y lo compruebe antes de hacer cada operación.

### 3.3 Una unión etiquetada para los valores de la pila

Una unión etiquetada (*tagged union*) es un registro que puede contener una de varias variantes y que lleva un campo, la etiqueta, que dice cuál de ellas contiene. Lenguajes como Rust la ofrecen directamente con `enum`. Lua no tiene nada parecido, así que la construimos con una tabla que tiene un campo `kind` (la etiqueta) y un campo `value` (el dato):

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

(`src/value.lua`, líneas 26 a 39.) `assert` lanza un error si la condición es falsa. Estos `assert` no están pensados para los errores del usuario, sino para los nuestros: si alguna vez el evaluador intentara guardar un decimal en un `int`, el programa lo detectaría en el acto. `M.float` suma `0.0` al número para que Lua lo guarde siempre con el subtipo `float`, aunque reciba un entero.

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

(`src/tokenizer.lua`, líneas 10 a 16.) Usamos textos como etiquetas, y no números, porque al imprimir un valor durante la depuración se lee `int` en lugar de un 1 que habría que ir a buscar en una tabla.

### 3.4 Cómo comprueba los tipos el evaluador

Cada operador está descrito en una tabla con dos campos: `accepts`, que dice qué tipos admite, y `apply`, la función que hace la cuenta.

```lua
local OPERATORS = {
    ["+"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value + b.value)) end },
    ["-"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value - b.value)) end },
    ["*"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(number_result(a, b, a.value * b.value)) end },
    ["/"]  = { accepts = "numbers", apply = divide },
    ["=="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value == b.value)) end },
    ["!="] = { accepts = "comparable", apply = function(a, b) return Result.ok(Value.bool(a.value ~= b.value)) end },
    ["<"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value < b.value)) end },
    [">"]  = { accepts = "numbers", apply = function(a, b) return Result.ok(Value.bool(a.value > b.value)) end },
}
```

(`src/evaluator.lua`, líneas 63 a 72.) La comprobación la hace `check_types`, que mira solo las etiquetas:

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

(`src/evaluator.lua`, líneas 74 a 90.) La equivalencia de tipos del Mini-REPL es, entonces, por nombre de etiqueta: dos operandos son compatibles si sus etiquetas coinciden, con una excepción, que `int` y `float` se agrupan como "número". Es la misma relación que Lua establece entre sus subtipos `integer` y `float` dentro de `number`. La tabla siguiente resume las reglas que salen del código:

| Operador | Operandos que acepta | Tipo del resultado |
| --- | --- | --- |
| `+`, `-`, `*` | dos números | `int` si ambos son `int`; `float` si alguno es `float` |
| `/` | dos números | `int` si ambos son `int` y la división es exacta; `float` en otro caso; error si el divisor es 0 |
| `==`, `!=` | dos números o dos booleanos | `bool` |
| `<`, `>` | dos números | `bool` |

Elegimos ser más estrictos que Lua con `==`. En Lua, `5 == true` da `false` sin error. En el Mini-REPL, `5 true ==` es un error de tipos. Comparar un número con un booleano casi siempre indica que la expresión está mal escrita, y nos pareció más útil avisarlo que contestar `false`. `<` y `>` tampoco aceptan booleanos, porque ordenar `true` y `false` no tiene un significado claro.

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

    -- En postfijo el operando derecho es el último que se apiló.
    local right_item = table.remove(stack)
    local left_item = table.remove(stack)

    local a, err_a = M.resolve(left_item)
    if err_a then return nil, err_a end
    local b, err_b = M.resolve(right_item)
    if err_b then return nil, err_b end

    local _, type_err = check_types(op, operator.accepts, a, b)
    if type_err then return nil, type_err end

    local result, op_err = operator.apply(a, b)
    if op_err then return nil, op_err end
    return push(stack, result)
end
```

(`src/evaluator.lua`, líneas 122 a 147.) Primero se verifica que haya dos valores en la pila, después que las variables existan, después los tipos y, por último, la operación en sí, que es donde se detecta la división por cero. Estas son salidas reales del programa:

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

La regla del tipo del resultado para `+`, `-` y `*` vive en una función de cinco líneas:

```lua
local function number_result(a, b, n)
    if a.kind == Value.Kind.INT and b.kind == Value.Kind.INT then
        return Value.int(n)
    end
    return Value.float(n)
end
```

(`src/evaluator.lua`, líneas 42 a 47.) Lua ya calcula `n` con el subtipo correcto, porque opera dos enteros como entero y cualquier mezcla como decimal (Ierusalimschy et al., 2020, §3.4.1). La función solo traslada esa regla a nuestras etiquetas.

La división necesitó más cuidado. En Lua `/` siempre da decimal, y no queríamos que `8 2 /` mostrara `4.0`. Por eso, si los dos operandos son enteros y el resto es cero, usamos la división entera `//`:

```lua
local function divide(a, b)
    if b.value == 0 then
        return Result.fail(Errors.new(Errors.Code.DIVISION_BY_ZERO, "división por cero", "/"))
    end
    -- Entre enteros, si la división es exacta el resultado sigue siendo Int.
    if a.kind == Value.Kind.INT and b.kind == Value.Kind.INT and a.value % b.value == 0 then
        return Result.ok(Value.int(a.value // b.value))
    end
    return Result.ok(Value.float(a.value / b.value))
end
```

(`src/evaluator.lua`, líneas 49 a 58.) La condición `b.value == 0` también detecta `0.0`, porque para Lua `0.0 == 0` es verdadero. Así `5 0.0 /` da el mismo error que `5 0 /`, en lugar de devolver infinito, que es lo que daría la división decimal de Lua.

Para leer los números del texto usamos `tonumber`, que sigue las mismas reglas que el analizador léxico de Lua (Ierusalimschy et al., 2020, §3.4.3). Según esas reglas, un número escrito sin punto decimal que no cabe en un entero de 64 bits se convierte en decimal (§3.1). No queríamos que `99999999999999999999` se volviera decimal sin que nadie se enterara, así que `push_number` lo rechaza:

```lua
function M.push_number(lexeme, stack)
    local n = tonumber(lexeme)
    if n == nil then
        return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
            string.format("'%s' no es un número válido", lexeme), lexeme))
    end
    if math.type(n) == "integer" then
        return push(stack, Value.int(n))
    end
    if lexeme:find(".", 1, true) then
        return push(stack, Value.float(n))
    end
    -- Un literal sin punto que Lua no pudo guardar como entero (por ejemplo
    -- 99999999999999999999) se convertiría en Float sin avisar; se rechaza.
    return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
        string.format("el entero '%s' está fuera del rango permitido", lexeme), lexeme))
end
```

(`src/evaluator.lua`, líneas 92 a 108.) Al probar los límites encontramos un caso que no cubrimos. El literal se controla, pero el resultado de una operación no. El manual establece que, cuando una operación entre enteros se desborda, el resultado da la vuelta según la aritmética de complemento a dos (§2.1 y §3.4.1), y eso es lo que hace nuestro programa:

```text
rpn> 9223372036854775807 1 +
-9223372036854775808
```

Para el alcance de esta asignación lo dejamos así y lo documentamos aquí. Corregirlo exigiría comprobar el desbordamiento en `number_result` antes de crear el valor.

Por último, el tokenizador no acepta notación científica: `1e3` no encaja en los patrones de `is_integer_literal` ni de `is_float_literal` y se rechaza como token inválido. Sí acepta formas como `.5` y `5.`, que son decimales.

## 4. Subrutinas, paso de parámetros y manejo de memoria

### 4.1 Funciones en Lua

En Lua las funciones son valores como cualquier otro: se pueden guardar en variables y en tablas, pasar como argumento y devolver como resultado (Ierusalimschy et al., 2020, §2.1). La forma `function M.tokenize(line) ... end` es una abreviatura de `M.tokenize = function(line) ... end` (§3.4.11). Es decir, las funciones públicas de cada módulo son campos de la tabla `M`. Las privadas se declaran con `local function` y no se pueden usar desde otro archivo.

La tabla `OPERATORS` de la sección 3.4 aprovecha que las funciones son valores: cada entrada guarda una función anónima en el campo `apply`. Esas funciones usan `number_result`, `Value` y `Result`, que son variables locales del módulo declaradas fuera de ellas. Lua llama *upvalue* a una variable local de un nivel externo que una función interna usa (§3.5). Cada vez que se ejecuta `+`, la función anónima encuentra `number_result` a través de ese upvalue, sin que nadie se la pase como argumento.

### 4.2 Varios resultados y la convención (valor, error)

Una función de Lua puede devolver varios valores a la vez (Ierusalimschy et al., 2020, §3.3.4). Usamos esa capacidad para reportar errores sin excepciones. Todo el proyecto sigue un contrato que dejamos escrito en `result.lua`:

```lua
function M.ok(value)
    return value, nil
end

function M.fail(message)
    return nil, message
end
```

(`src/result.lua`, líneas 10 a 16.) Una función que sale bien devuelve el valor y `nil`; una que falla devuelve `nil` y el error. La biblioteca estándar de Lua usa la misma idea: muchas de sus funciones devuelven "fail" (que hoy es `nil`) seguido de un mensaje de error cuando algo sale mal; la biblioteca de entrada y salida, por ejemplo, lo hace en todas sus funciones (§6 y §6.8). Nos pareció más honesto seguir esa costumbre que inventar un objeto `Result` con métodos, que en Lua habría sido un adorno.

Cuando una función devuelve más valores de los que quien la llama recibe, los sobrantes se descartan, y si devuelve menos, los que faltan se rellenan con `nil` (§3.4.12). El proyecto se apoya en esa regla en varios sitios. `Environment.get` necesita solo el valor y escribe `local value = M.lookup(env, name)`, aunque `lookup` también devuelve el entorno donde encontró la variable. En sentido contrario, `apply_operator` recibe dos resultados de `check_types` y descarta el primero con el nombre `_`, una convención de Lua para "este valor no me interesa".

`Evaluator.eval` tiene un tercer resultado, el entorno activo al terminar. Explicamos por qué en la sección 4.3.

Para los errores que no esperamos, como un fallo de programación nuestro, el REPL envuelve la evaluación en `pcall`. `pcall` ejecuta una función en modo protegido: si dentro se lanza un error, no se propaga; `pcall` lo atrapa y devuelve `false` y el error (Ierusalimschy et al., 2020, §2.3 y §6.1). En el bucle de la sección 2.3 se ve cómo un fallo interno se convierte en un mensaje con el código `internal_error` y el REPL sigue funcionando. En las pruebas con entradas normales ese camino nunca se activó, que es lo esperable si los errores del usuario están bien cubiertos por el contrato `(valor, error)`.

### 4.3 Paso de parámetros

Pasar un parámetro por valor significa que la función recibe una copia y lo que haga con ella no afecta al original. Pasarlo por referencia significa que la función recibe acceso a la variable original y puede cambiarla.

Lua no encaja limpio en ninguna de las dos. El manual dice que los parámetros se comportan como variables locales inicializadas con los valores de los argumentos (Ierusalimschy et al., 2020, §3.4.11), lo que suena a paso por valor. Pero también dice que las tablas, las funciones y los hilos son objetos y que las variables no los contienen, sino que guardan referencias a ellos: la asignación, el paso de parámetros y el retorno de funciones manipulan esas referencias sin copiar nada (§2.1). El resultado combinado es que la función recibe una copia de la referencia. Puede modificar el contenido de una tabla recibida, y el cambio lo ve quien la llamó. Lo que no puede hacer es cambiar a qué tabla apunta la variable de quien la llamó.

Este ejemplo ilustrativo, que no pertenece al proyecto, muestra las dos caras:

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

El enunciado pide pasar la pila y la tabla de símbolos de forma explícita a las subrutinas (Universidad de Carabobo, 2026). Lo hicimos en todas las funciones que las usan: `push_number(lexeme, stack)`, `push_variable(name, stack, env)`, `apply_operator(op, stack)`, `assign(stack, env)` y `eval(tokens, stack, env)`. La pila muestra el primer caso del ejemplo. `push` agrega un elemento a la tabla que recibe:

```lua
local function push(stack, value)
    stack[#stack + 1] = value
    return Result.ok(value)
end
```

(`src/evaluator.lua`, líneas 21 a 24.) `#stack` es el operador de longitud, que en una tabla usada como arreglo da la posición del último elemento (Ierusalimschy et al., 2020, §3.4.7). Para retirar elementos usamos `table.remove(stack)`, que sin un segundo argumento quita el último (§6.6). Ninguna de estas funciones devuelve la pila: la modifican en su lugar y el REPL ve los cambios porque comparte la misma tabla. Por la misma razón `REPL.clear` borra los elementos uno por uno en vez de hacer `stack = {}`: esa asignación solo cambiaría la variable local de `clear` y dejaría intacta la pila del REPL. Las pruebas lo comprueban:

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

(`tests/test_evaluator.lua`, líneas 149 a 157.)

El entorno muestra el segundo caso del ejemplo. Agregar o cambiar una variable modifica la tabla `env.vars`, y eso se ve desde fuera. Pero `begin` y `end` no modifican el entorno: cambian cuál es el entorno activo. Dentro de `eval`, la línea `if new_env then env = new_env end` reasigna la variable local `env`, y esa reasignación no llega al REPL. Por eso `eval` devuelve el entorno como tercer resultado y el REPL lo guarda con `env = new_env`. Las pruebas verifican que la variable de quien llama queda igual:

```lua
local caller_env = Environment.new(nil)
local _, _, returned_env = Evaluator.eval(Tokenizer.tokenize("begin"), {}, caller_env)
check("eval no cambia la variable del llamador; devuelve el entorno nuevo",
    caller_env.depth == 0 and returned_env.parent == caller_env)
```

(`tests/test_evaluator.lua`, líneas 159 a 162.) En este punto la regla de Lua decidió el diseño. Si `begin` intentara "entrar" al bloque reasignando el parámetro `env`, el REPL nunca se enteraría, por lo mismo que en el ejemplo ilustrativo `numero` siguió valiendo 5. Devolver el entorno nuevo es la forma que tiene Lua de hacer llegar ese cambio a quien llama.

Compartir referencias tiene un riesgo: si dos partes del programa guardan la misma tabla y una la modifica, la otra ve el cambio sin esperarlo. Después de `y x =`, la variable `y` guarda exactamente la misma tabla de valor que `x`, no una copia. Lo evitamos tratando los valores como inmutables, es decir, una vez creados nunca se modifican. Lo dejamos escrito al principio de `value.lua`:

```lua
-- Los valores se tratan como inmutables: una vez creados nunca se modifican.
-- Por eso es seguro que la pila y el entorno compartan la misma tabla.
```

(`src/value.lua`, líneas 6 y 7.) Cuando `x` cambia, `define` guarda una tabla de valor nueva en `env.vars["x"]`, y la que comparte `y` queda como estaba. Lua no tiene forma de hacer cumplir esta regla; es una convención nuestra. Los textos de Lua, en cambio, sí son inmutables por definición del lenguaje (Ierusalimschy et al., 2020, §2.1).

### 4.4 Manejo de memoria

Lua administra la memoria de forma automática. El programador no reserva ni libera memoria: un recolector de basura busca los objetos que el programa ya no puede alcanzar y los libera (Ierusalimschy et al., 2020, §2.5). Un objeto es inalcanzable cuando ninguna variable ni ningún otro objeto vivo lo referencia. El manual aclara que no hay garantía sobre el momento exacto: solo promete que no liberará nada que todavía se pueda usar y que tarde o temprano liberará lo inalcanzable.

En el Mini-REPL se crean tablas todo el tiempo, por ejemplo una por cada token y otra por cada valor que pasa por la pila. No liberamos ninguna a mano. El caso interesante es el de los bloques. Cuando `end` ejecuta `Environment.close`, devuelve el padre y el REPL guarda ese padre como entorno activo. Nada apunta ya al bloque que se cerró (los hijos apuntan al padre, nunca al revés), así que el bloque y todas sus variables locales quedan disponibles para el recolector.

Quisimos comprobarlo en lugar de suponerlo. Para eso usamos una tabla débil: una tabla cuyas referencias el recolector ignora, de modo que si un objeto solo está referenciado desde una tabla débil, el recolector lo libera igual. La debilidad se activa con el campo `__mode` de su metatabla (§2.5.4). La prueba guarda el bloque en una tabla débil, lo cierra, fuerza el recolector con `collectgarbage` y verifica que el bloque desapareció:

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

(`tests/test_evaluator.lua`, líneas 165 a 177.) La prueba pasa. Llamamos a `collectgarbage("collect")` dos veces por precaución, para no depender de en qué fase del ciclo esté el recolector. La pila, en cambio, es una sola tabla que vive mientras dura la sesión; `clear` reutiliza la misma tabla en cada línea en lugar de crear una nueva.

## 5. Abstracción de datos y equivalente de la programación orientada a objetos

Lua no tiene clases ni interfaces como construcciones del lenguaje. Lo que tiene son tablas, que el manual describe como el único mecanismo para estructurar datos; con ellas se representan arreglos, registros, conjuntos y tablas de símbolos, y como sus campos pueden contener funciones, también pueden llevar métodos (Ierusalimschy et al., 2020, §2.1). A eso se suman las metatablas: tablas comunes que, asociadas a un valor, definen cómo se comporta ese valor ante ciertas operaciones (§2.4). Con estas dos piezas se puede imitar casi cualquier estilo de programación orientada a objetos. Nosotros usamos solo lo que el proyecto necesitaba.

La abstracción de datos consiste en ofrecer un tipo a través de un conjunto de operaciones, ocultando cómo está guardado por dentro. En el proyecto la unidad de abstracción es el módulo. `value.lua` es el mejor ejemplo: expone constructores (`int`, `float`, `bool`, `name`), preguntas sobre el tipo (`is_number`, `is_bool`, `is_name`, `type_name`) y la conversión a texto (`tostring`). La función `tagged`, que arma la tabla, es local y no se puede llamar desde fuera. Hay que admitir que el ocultamiento no es completo. Lua no impide leer los campos de una tabla, y el evaluador lee `a.value` y `a.kind` directamente cuando hace las cuentas. Lo aceptamos porque escribir una función para leer cada campo habría alargado el código sin protegerlo de nada.

Las metatablas cumplen el papel de un comportamiento compartido, parecido a un método definido una sola vez en una clase. Todos los valores comparten la metatabla `ValueMeta`, y todos los errores comparten `ErrorMeta`. Ambas definen `__tostring`, que es el campo que consulta la función `tostring` de Lua para convertir un valor a texto (Ierusalimschy et al., 2020, §6.1):

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

(`src/errors.lua`, líneas 18 a 35.) Sin esa metatabla, `print` sobre un valor mostraría algo como `table: 0x...`. Con ella muestra `2.5` o `[division_by_zero] división por cero`. Dos pruebas lo verifican (`tests/test_evaluator.lua`, líneas 180 a 182).

Lua ofrece una sintaxis con dos puntos para imitar métodos: `env:lookup(name)` equivale a `env.lookup(env, name)`, y al definir la función con `:` se agrega un parámetro oculto llamado `self` (§3.4.11). Decidimos no usarla. Escribimos `Environment.lookup(env, name)` con el entorno como primer argumento visible, porque el requisito 3 del enunciado pide que el entorno y la pila se pasen de forma explícita, y con los dos puntos ese paso queda escondido. El comportamiento sería idéntico; es una decisión de legibilidad.

Para el polimorfismo, que es la capacidad de tratar de la misma forma objetos distintos que responden a las mismas operaciones, usamos la tabla `OPERATORS`. Cada entrada tiene la misma forma, un campo `accepts` y una función `apply` que recibe dos valores y devuelve `(valor, error)`. `apply_operator` no sabe qué operador está aplicando: busca la entrada, consulta `accepts` y llama a `apply`. Agregar un operador nuevo, por ejemplo `<=`, sería agregar una línea a la tabla y su lexema al tokenizador, sin tocar `apply_operator`. Es lo que en otros lenguajes se haría con una interfaz; en Lua basta con que las tablas tengan los mismos campos.

El contrato `(valor, error)` funciona como una segunda interfaz, esta vez entre módulos. El tokenizador, el entorno y el evaluador cumplen la misma regla, y por eso el REPL puede tratar todos los errores igual sin importar dónde nacieron.

La herencia tiene un equivalente parcial en la cadena de entornos. Un bloque que no encuentra una variable se la pide a su padre, que es la misma idea de la delegación entre prototipos. Lua trae un mecanismo para eso, el campo `__index` de la metatabla (§2.4): si la tabla de variables de un bloque tuviera una metatabla con `__index` apuntando a la del padre, la búsqueda subiría sola cuando la clave no estuviera. Lo descartamos. Necesitábamos saber en qué entorno se encontró cada variable, para que `vars` pudiera mostrar si es global o de un bloque y para que `set` supiera dónde escribir, y con `__index` esa información se pierde. El bucle explícito de `lookup` la devuelve como segundo resultado.

## 6. Cumplimiento de los requisitos técnicos de la Parte II

Las secciones anteriores ya explicaron el código que cumple cada requisito. Aquí los recorremos en el orden del enunciado (Universidad de Carabobo, 2026), con lo que el programa hace al ejecutarse.

### 6.1 Evaluación en pila y manejo de errores

El Mini-REPL evalúa `+`, `-`, `*`, `/`, `==`, `!=`, `<` y `>` sobre la pila en orden postfijo. Cada error esperado se devuelve como un valor con el contrato `(valor, error)` de la sección 4.2 y el REPL lo imprime sin detenerse; `pcall` queda solo para fallos imprevistos. La tabla reúne una entrada de cada tipo de error con la salida real del programa:

| Entrada | Salida |
| --- | --- |
| `5 0 /` | `[division_by_zero] división por cero` |
| `5 +` | `[stack_underflow] el operador + necesita 2 valores y la pila tiene 1` |
| `x =` | `[stack_underflow] la asignación = necesita 2 valores y la pila tiene 1` |
| `3 #` | `[invalid_token] token inválido '#' en la columna 3` |
| `1 vars` | `[invalid_token] 'vars' es un comando y debe escribirse solo en la línea` |
| `99999999999999999999` | `[invalid_token] el entero '99999999999999999999' está fuera del rango permitido` |
| `y` (sin definir) | `[undefined_variable] la variable 'y' no está definida` |
| `5 3 =` | `[invalid_assignment] antes del valor debe ir el nombre de una variable, pero se encontró un int` |
| `end` (sin bloque) | `[no_open_block] 'end' sin 'begin': no hay ningún bloque abierto` |

Si una línea deja más de un valor en la pila, se imprime el de arriba: `1 2 3` imprime `3`.

### 6.2 Sistema de tipos del evaluador

Los tokens y los valores de la pila son uniones etiquetadas construidas con tablas (sección 3.3). El evaluador distingue `int`, `float` y `bool`, y `check_types` produce un error de tipos controlado antes de que Lua llegue a intentar la operación (sección 3.4). El caso que menciona el enunciado, `5 true +`, responde `[type_mismatch] el operador + no se puede aplicar a int y bool`.

### 6.3 Variables y paso de parámetros

`x 10 =` y `x 5 2 + =` declaran o actualizan una variable; la asignación no imprime nada. La función que la ejecuta recibe la pila y el entorno como parámetros:

```lua
function M.assign(stack, env)
    if #stack < 2 then
        return underflow("la asignación =", 2, #stack)
    end
    local value_item = table.remove(stack)
    local target = table.remove(stack)

    if not Value.is_name(target) then
        return Result.fail(Errors.new(Errors.Code.INVALID_ASSIGNMENT,
            string.format("antes del valor debe ir el nombre de una variable, pero se encontró un %s",
                Value.type_name(target)),
            "="))
    end

    local value, err = M.resolve(value_item)
    if err then return nil, err end
    return Environment.define(env, target.name, value)
end
```

(`src/evaluator.lua`, líneas 151 a 168.) El comando `vars` lista las variables visibles con su valor, su tipo y el ámbito donde viven:

```lua
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
```

(`src/repl.lua`, líneas 39 a 50.) `Environment.names` recorre la cadena de entornos, junta los nombres sin repetirlos y los ordena alfabéticamente. Para cada nombre, `lookup` devuelve el valor visible y el entorno donde está, con lo que `scope_label` escribe `global` o `bloque N`. Lo que el requisito pide demostrar sobre mutabilidad y paso por valor o por referencia está en la sección 4.3: la pila se modifica en su lugar porque las funciones reciben una referencia a la misma tabla, y el entorno activo se devuelve como resultado porque reasignar un parámetro no cambia la variable de quien llama.

### 6.4 Alcance local

`begin` crea un entorno hijo y `end` vuelve al padre (sección 2.4). Como `=` siempre escribe en el entorno actual, una variable asignada dentro de un bloque oculta a la global del mismo nombre mientras el bloque está abierto y desaparece al cerrarlo, sin haber tocado la global. Los bloques se pueden anidar, pueden abrirse y cerrarse en la misma línea o en líneas distintas, y el indicador muestra la profundidad actual.

### 6.5 Verificación automática

`tests/test_evaluator.lua` no depende de ninguna biblioteca externa. Define una función `check` que cuenta aciertos y fallos, y agrupa las pruebas por tema: aritmética y comparaciones, errores controlados, variables, alcance, paso de parámetros, memoria, metatablas y una sesión completa. Esa última prueba alimenta al REPL con una lista de líneas en lugar del teclado, porque `REPL.run` recibe como parámetros las funciones de entrada, salida e indicador:

```lua
function M.run(input, output, write_prompt)
    input = input or io.read
    output = output or print
    write_prompt = write_prompt or function(text)
        io.write(text)
        io.flush()
    end
```

(`src/repl.lua`, líneas 52 a 58.) Si no se le pasa nada, usa el teclado y la pantalla; en la prueba recibe funciones que leen de una lista y guardan lo impreso en otra. Así la prueba compara línea por línea la salida real con la esperada, y la sesión de ejemplo del `README.md` es exactamente la que verifica. La ejecución completa terminó con este resultado:

```text
86 pruebas correctas, 0 fallidas
```

## Bibliografía

Ierusalimschy, R., de Figueiredo, L. H., & Celes, W. (2020). *Lua 5.4 reference manual*. Lua.org; PUC-Rio. Recuperado el 22 de noviembre de 2026, de https://www.lua.org/manual/5.4/

Universidad de Carabobo, Facultad Experimental de Ciencias y Tecnología. (2026). *Asignación #1: CAO604 Lenguajes de Programación, semestre 1-2026* [Enunciado de la asignación].
