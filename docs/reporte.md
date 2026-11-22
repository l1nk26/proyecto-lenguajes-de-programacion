# Reporte técnico: Mini-REPL RPN en Lua

**Universidad de Carabobo, Facultad Experimental de Ciencias y Tecnología**
**CAO604 Lenguajes de Programación, Asignación #1, semestre 1-2026**

Integrantes: (completar)

Repositorio: https://github.com/l1nk26/proyecto-lenguajes-de-programacion

## 1. Lenguaje, versión y organización del proyecto

### 1.1 Lua y su forma de ejecución

El proyecto está escrito en Lua 5.4 y fue probado con el intérprete oficial en su versión 5.4.6. La especificación de referencia que se usa en todo el reporte es el *Lua 5.4 Reference Manual* (Ierusalimschy et al., 2020). Las citas a ese manual indican la sección con el símbolo §, por ejemplo §2.1.

El programa se inicia con la orden `lua src/main.lua`. Lua no exige un paso de compilación separado como C o Rust: el intérprete lee el archivo, lo traduce a instrucciones de su propia máquina virtual y ejecuta esas instrucciones de inmediato (Ierusalimschy et al., 2020, §3.3.2). Esa traducción comprueba que la sintaxis sea correcta, pero no revisa tipos. Las consecuencias de esa decisión del lenguaje se explican en la sección 4.

### 1.2 Módulos del programa

El código está dividido en ocho archivos dentro de `src/`. Cada archivo es un módulo, es decir, una unidad que agrupa funciones relacionadas y las entrega al resto del programa. La responsabilidad de cada uno es la siguiente.

| Archivo | Responsabilidad |
| --- | --- |
| `main.lua` | Prepara la búsqueda de módulos, ajusta la consola de Windows y arranca el REPL. |
| `repl.lua` | Bucle interactivo: lee una línea, la evalúa e imprime el resultado. Atiende los comandos `vars` y `exit`. |
| `tokenizer.lua` | Separa la línea en palabras y clasifica cada una (número, booleano, nombre, operador o palabra reservada). |
| `evaluator.lua` | Recorre los tokens, opera sobre la pila y aplica las reglas de tipos. |
| `value.lua` | Define cómo se representan los valores de la pila: Int, Float, Bool y Name. |
| `environment.lua` | Tabla de símbolos: guarda las variables y maneja los bloques `begin` y `end`. |
| `result.lua` | Funciones `ok` y `fail` que expresan la convención `(valor, error)`. |
| `errors.lua` | Códigos de error y formato con que se muestran al usuario. |

Las dependencias van en una sola dirección. `repl.lua` usa al tokenizador, al evaluador y al entorno; el evaluador usa al entorno, a los valores y a los errores; ningún módulo de nivel inferior conoce al REPL. Esta separación permite probar el evaluador sin abrir una consola, que es lo que hace el archivo de pruebas.

Cada módulo crea una tabla local llamada `M`, le agrega funciones y la devuelve al final del archivo. Otro módulo la obtiene con `require`:

```lua
local Result = require("result")
local Errors = require("errors")

local M = {}

function M.new(kind, lexeme, column)
    return { kind = kind, lexeme = lexeme, column = column }
end

return M
```

La función `require` busca el archivo en las rutas que indica la variable `package.path`, lo ejecuta una sola vez y guarda en `package.loaded` la tabla que el archivo devolvió (Ierusalimschy et al., 2020, §6.3). Si dos módulos piden `require("value")`, ambos reciben exactamente la misma tabla. Para que la búsqueda funcione sin importar desde qué carpeta se lance el programa, `main.lua` agrega la carpeta donde está el propio archivo al principio de esas rutas:

```lua
local script_dir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./"
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path

if package.config:sub(1, 1) == "\\" then
    os.execute("chcp 65001 > NUL")
end
```

`arg[0]` contiene la ruta con que se invocó el programa, por ejemplo `src/main.lua`, y el patrón extrae la parte de la carpeta, `src/`. La segunda instrucción existe porque la consola de Windows no usa UTF-8 por defecto y mostraría mal palabras como "división". El primer carácter de `package.config` es el separador de carpetas del sistema, y solo es una barra invertida en Windows, así que el cambio de codificación se hace únicamente allí.

## 2. Evaluación en pila

### 2.1 Notación postfija

En la notación habitual el operador va entre los operandos, como en `(x + 5) × 2`, y los paréntesis indican qué se calcula primero. En la notación postfija, también llamada notación polaca inversa o RPN, el operador se escribe después de sus dos operandos. La misma expresión queda como `x 5 + 2 *`. Los paréntesis dejan de ser necesarios, porque el orden en que aparecen los operadores ya fija el orden de cálculo (Hamblin, 1962).

Esta notación se evalúa con una pila, una lista donde solo se agrega y se quita por un extremo, llamado tope. La regla es simple: cada número se coloca en el tope; cada operador retira los dos valores del tope, los combina y coloca el resultado en su lugar. La siguiente tabla muestra el estado de la pila después de cada palabra de `3 4 + 2 *`, con el tope a la derecha.

| Palabra leída | Acción | Pila después |
| --- | --- | --- |
| `3` | se apila 3 | 3 |
| `4` | se apila 4 | 3 4 |
| `+` | se retiran 3 y 4, se apila 7 | 7 |
| `2` | se apila 2 | 7 2 |
| `*` | se retiran 7 y 2, se apila 14 | 14 |

Al terminar, el único valor en la pila es el resultado, 14.

### 2.2 La pila en Lua

Lua no trae un tipo "pila". Su única estructura de datos es la tabla (Ierusalimschy et al., 2020, §2.1), que puede usarse como lista si sus claves son los enteros 1, 2, 3 y siguientes sin huecos. El operador `#` devuelve la cantidad de elementos de una lista así (§3.4.7), de modo que el tope es el elemento `stack[#stack]`. Apilar consiste en escribir en la posición siguiente al tope, y desapilar consiste en llamar a `table.remove`, que sin indicar posición quita y devuelve el último elemento (§6.6):

```lua
local function push(stack, value)
    stack[#stack + 1] = value
    return Result.ok(value)
end
```

```lua
    local right_item = stack[#stack]
    local left_item = stack[#stack - 1]
    -- ... validaciones ...
    table.remove(stack)
    table.remove(stack)
```

### 2.3 Recorrido de una línea por el programa

Cuando el usuario escribe una línea y pulsa Enter, el bucle de `repl.lua` la recibe y le quita los espacios del principio y del final. Si la línea es `exit` o `quit`, el bucle termina. Si es `vars`, muestra las variables. En cualquier otro caso vacía la pila y entrega la línea a `eval_line`:

```lua
        local command = line:match("^%s*(.-)%s*$")

        if command == "exit" or command == "quit" then
            break
        elseif command == "vars" then
            M.show_vars(env, output)
        elseif command ~= "" then
            -- Cada línea es una expresión independiente: la pila empieza vacía.
            M.clear(stack)

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
```

`eval_line` llama primero al tokenizador y, si este no encontró problemas, al evaluador. El evaluador devuelve tres cosas: el valor que quedó en el tope, un error si lo hubo y el entorno que quedó activo. El REPL imprime el error o el valor, guarda el entorno para la línea siguiente y vuelve a mostrar el indicador `rpn> `. La función `pcall` y el tercer resultado se explican en las secciones 5.3 y 5.4.

`vars` y `exit` se atienden en el REPL y no en el evaluador porque no producen un valor para la pila: uno escribe en pantalla y el otro termina la sesión. Por eso deben escribirse solos en la línea. Si aparecen dentro de una expresión, como en `1 vars`, el evaluador responde `[invalid_token] 'vars' es un comando y debe escribirse solo en la línea`.

### 2.4 Tokenizador

El tokenizador convierte la línea en una lista de tokens. Un token es una tabla con tres campos: la clase de la palabra, el texto original (llamado lexema) y la columna donde empieza. Para recorrer las palabras usa `string.gmatch` con el patrón `"()(%S+)"`. `%S+` significa "uno o más caracteres que no sean espacio", y la captura vacía `()` devuelve la posición en que empieza cada coincidencia (Ierusalimschy et al., 2020, §6.4.1):

```lua
function M.tokenize(line)
    local tokens = {}
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
```

La clasificación sigue un orden fijo, y ese orden resuelve dos casos que de otro modo serían ambiguos. Primero se comparan los operadores, luego las palabras reservadas, luego `true` y `false`, después los números y al final los nombres:

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

El primer caso es el signo menos. `-` solo es el operador de resta, pero `-5` es un número negativo; como la tabla de operadores solo contiene el lexema exacto `-`, el texto `-5` no coincide con ella y llega a la prueba de números. El segundo caso son las palabras reservadas: `end` tiene la forma de un nombre de variable, pero se revisa antes como palabra reservada, así que nunca puede usarse como variable.

Los conjuntos de palabras fijas se escriben como tablas cuyas claves son los elementos, por ejemplo `OPERATORS["+"] = true`. Preguntar si una palabra pertenece al conjunto es una sola consulta a la tabla, sin recorrer una lista. Los números se reconocen con patrones: `^[+-]?%d+$` para enteros y `^[+-]?%d+%.%d*$` o `^[+-]?%.%d+$` para decimales. Los símbolos `^` y `$` obligan a que el patrón cubra la palabra completa, de modo que `5x` no pasa por número.

Si una palabra no pertenece a ninguna clase, el tokenizador se detiene y devuelve un error que indica la palabra y su columna. Con la entrada `3 #` la respuesta es `[invalid_token] token inválido '#' en la columna 3`. La línea completa se rechaza antes de tocar la pila, así que un error de escritura nunca deja cálculos a medias.

### 2.5 Aplicación de operadores

`apply_operator` concentra el trabajo de los ocho operadores. Lo hace en cinco pasos: busca el operador en la tabla, comprueba que haya al menos dos valores, **lee** los operandos sin quitarlos, verifica sus tipos y su rango y, solo si todo es válido, los desapila y apila el resultado:

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

El orden de los operandos importa en la resta, la división y las comparaciones. En `2 5 -` el 2 entra primero y el 5 queda en el tope, así que `stack[#stack]` es el 5, el operando derecho. El cálculo es 2 menos 5 y la respuesta es `-3`. Validar antes de desapilar tiene una consecuencia útil: si una operación falla, los operandos siguen en la pila y el estado no queda a medias.

La comprobación de profundidad evita el error que en inglés se llama *stack underflow*: intentar sacar de la pila más valores de los que tiene. Con `5 +` hay un solo valor y el operador necesita dos, por lo que la respuesta es `[stack_underflow] el operador + necesita 2 valores y la pila tiene 1`. Con `*` solo, la pila tiene cero.

### 2.6 Resultado de cada línea

Cada línea es una expresión independiente. Antes de evaluarla, el REPL vacía la pila, y al terminar imprime el valor que quedó en el tope. Si quedaron varios valores, como en `1 2 3`, solo se muestra el último, `3`. Si la pila quedó vacía, como después de una asignación, no se imprime nada. Se eligió vaciar la pila en cada línea porque así el resultado de una línea depende solo de lo que se escribió en ella, y los valores que pasan de una línea a otra son únicamente las variables, que se consultan con `vars`.

Cuando una línea produce un error, la evaluación se detiene en ese punto y el resto de la línea no se ejecuta. Lo que ya se había hecho antes del error se conserva. Por ejemplo, en `x 5 = 1 0 /` la variable `x` queda asignada aunque la división falle después. La pila no conserva nada, porque se vacía al empezar la línea siguiente.

## 3. Nombres, vinculación, estructuras de control y alcance

### 3.1 Nombres en Lua

En Lua un nombre puede contener letras sin acentos, dígitos y el guion bajo; no puede empezar con un dígito ni ser una palabra reservada del lenguaje, como `local`, `function` o `end`. Las mayúsculas y minúsculas se distinguen, así que `Value` y `value` son nombres diferentes (Ierusalimschy et al., 2020, §3.1). El Mini-REPL adopta la misma regla para sus variables mediante el patrón `^[%a_][%w_]*$`: una letra o guion bajo seguida de letras, dígitos o guiones bajos. También tiene sus propias palabras reservadas, `begin`, `end`, `vars`, `exit`, `quit`, `true` y `false`, que el tokenizador clasifica antes de considerar que algo es un nombre.

Lua distingue entre variables locales y globales. Una variable es local si se declara con la palabra `local`; cualquier otro nombre se considera global. Los nombres globales no son un mecanismo aparte: el lenguaje traduce cada nombre global `x` a una consulta en una tabla especial, de modo que `x` equivale a `_ENV.x` (§2.2). Escribir una variable global es, en el fondo, escribir un campo en esa tabla compartida por todo el programa.

En el proyecto todas las variables y funciones auxiliares son locales, y lo único que cada módulo hace visible son los campos de su tabla `M`. Esto evita que dos módulos usen por accidente el mismo nombre global. Un ejemplo concreto del riesgo está en el evaluador. Allí se escribe `local _, err` antes de las asignaciones `_, err = M.push_number(lexeme, stack)`. Sin el `local`, Lua crearía una variable global llamada `_` en cada evaluación, visible desde todo el programa, sin mostrar ningún aviso.

### 3.2 Vinculación

La vinculación (en inglés *binding*) es la asociación entre un nombre y aquello que representa: un valor, una posición de memoria o un tipo. Interesa saber cuándo se establece esa asociación, si al escribir el programa, al traducirlo o mientras se ejecuta.

En Lua las variables no tienen tipo; los tipos pertenecen a los valores (Ierusalimschy et al., 2020, §2.1). Por eso un nombre nunca queda vinculado a un tipo y la misma variable puede contener un número en un momento y una tabla en otro. Lo que sí se vincula, y en dos momentos distintos, es el nombre con su lugar de almacenamiento. Para una variable local, la traducción del archivo ya decide a qué variable se refiere cada aparición del nombre, mirando solo el texto del programa; en la máquina virtual de Lua cada variable local ocupa una posición fija, asignada en ese momento (Ierusalimschy et al., 2005). Para una variable global, la asociación se resuelve durante la ejecución, cada vez que se consulta la tabla `_ENV`. El valor siempre se vincula durante la ejecución, cuando se ejecuta la asignación.

El Mini-REPL tiene su propia vinculación, que ocurre en tres momentos. En el primero, el tokenizador decide que una palabra es un nombre y no un número ni un operador. En el segundo, cuando el evaluador encuentra ese nombre, `push_variable` busca su valor actual y lo coloca en la pila junto con el nombre:

```lua
function M.push_variable(name, stack, env)
    local current = Environment.lookup(env, name)
    return push(stack, Value.name(name, current))
end
```

En el tercero, el operador `=` crea o reemplaza la asociación entre el nombre y un valor en el entorno actual, como se verá en la sección 3.5.

La razón para apilar el nombre y no solo su valor está en la propia notación postfija. En `x 10 =` la palabra `x` aparece antes que el valor y antes que el `=`. Cuando el evaluador la lee, no puede saber todavía si `x` se va a leer, como en `x 5 +`, o se va a escribir, como en `x 10 =`. Si buscara el valor y fallara porque `x` no existe, la primera asignación de cualquier variable sería imposible. Por eso se apila una ficha que conserva el nombre, que es lo que necesita `=`, y el valor que la variable tenía en ese momento, o `nil` si todavía no existe. El error por variable inexistente se reporta solo cuando alguien necesita el valor. `y 1 +` responde `[undefined_variable] la variable 'y' no está definida`, mientras que `y 1 =` funciona.

La ficha guarda el valor en el momento de apilarse, y no lo busca después, para respetar el orden en que se escribió la línea. En `begin x 99 = x end`, la segunda `x` se apila dentro del bloque, cuando vale 99, y el resultado impreso es `99` aunque al final de la línea el bloque ya esté cerrado. Si el valor se buscara al imprimir, se encontraría la `x` global y el resultado sería otro. El mismo mecanismo permite expresiones como `x x 1 + =`, que incrementa `x`: la segunda `x` aporta su valor a la suma y la primera aporta el nombre a la asignación.

### 3.3 Estructuras de control

Lua ofrece `if` con `elseif` y `else`, los bucles `while` y `repeat`, el `for` numérico y el `for` genérico, que recorre lo que devuelve una función iteradora (Ierusalimschy et al., 2020, §3.3.4 y §3.3.5). Para salir antes de tiempo están `break` y `return`. Lua no tiene una instrucción `switch` para elegir entre muchos casos.

El REPL usa un `while true do` del que se sale con `break` cuando llega `exit` o cuando la entrada se termina. El evaluador recorre los tokens con un `for` genérico sobre `ipairs`, que entrega cada posición de la lista en orden junto con su elemento. Para elegir qué hacer con cada token usa una cadena de `if` y `elseif` sobre su clase:

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

El `return` dentro del bucle es el que hace que la evaluación se detenga en el primer error. Para los operadores, en cambio, no se usa una cadena de condiciones sino una tabla: `OPERATORS[op]` devuelve directamente la entrada del operador con su regla de tipos y su función de cálculo. Es la forma habitual de reemplazar un `switch` en Lua, y tiene la ventaja de que agregar un operador consiste en agregar una entrada a la tabla sin tocar `apply_operator`.

### 3.4 Reglas de alcance de Lua

El alcance de un nombre es la parte del programa donde ese nombre puede usarse. Lua tiene alcance léxico: el alcance de una variable local empieza en la instrucción siguiente a su declaración y termina al final del bloque más interno que la contiene (Ierusalimschy et al., 2020, §3.5). Un bloque es, por ejemplo, el cuerpo de una función o lo que queda entre `do` y `end`. Como el alcance depende solo de la posición en el texto, basta leer el código para saber a qué variable se refiere cada nombre.

Si dentro de un bloque se declara una variable con el mismo nombre que una exterior, la interior oculta a la exterior hasta que el bloque termina. Este ocultamiento se llama *shadowing*. El siguiente fragmento de Lua muestra exactamente el comportamiento que el Mini-REPL debe reproducir con `begin` y `end`:

```lua
local x = 7
do
    local x = 99
    print(x)  --> 99
end
print(x)      --> 7
```

La `x` interior es otra variable; no modifica a la exterior, y al salir del bloque la exterior sigue valiendo 7.

### 3.5 Alcance en el Mini-REPL: begin y end

El Mini-REPL no puede usar los bloques de Lua para las variables del usuario, porque esas variables se crean mientras el programa se ejecuta, a partir de lo que se escribe en la consola. Lo que hace es construir su propia tabla de símbolos con la misma regla. Cada entorno es una tabla con tres campos: `vars`, que guarda las variables de ese nivel; `parent`, que apunta al entorno que lo contiene; y `depth`, que indica el nivel, 0 para el global, 1 para el primer bloque, y así sucesivamente.

```lua
function M.new(parent)
    return {
        parent = parent,
        vars = {},
        depth = parent and (parent.depth + 1) or 0,
    }
end
```

La expresión `parent and (parent.depth + 1) or 0` aprovecha cómo funcionan `and` y `or` en Lua: si `parent` es `nil`, todo vale 0; si no, vale la profundidad del padre más uno.

`begin` crea un entorno nuevo cuyo padre es el actual, y `end` vuelve al padre. Los entornos forman así una cadena desde el bloque más interno hasta el global. Para leer una variable, `lookup` la busca en el entorno actual y, si no la encuentra, sube al padre, hasta llegar al global:

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

Esta búsqueda es la que produce el ocultamiento. Si el bloque tiene su propia `x`, se encuentra primero y la global ni siquiera se consulta. Si no la tiene, se encuentra la global, de modo que desde un bloque se pueden leer las variables exteriores.

Para escribir, el operador `=` llama a `define`, que siempre escribe en el entorno actual:

```lua
function M.define(env, name, value)
    env.vars[name] = value
    return Result.ok(value)
end
```

Esta es la decisión central para cumplir el requisito de alcance local. El esqueleto del proyecto incluía también `set`, que busca la variable en la cadena y la modifica donde exista, aunque esté en el entorno global. Si `=` usara `set`, la línea `begin x 99 = end` cambiaría la `x` global, y eso es justamente lo que la consigna prohíbe. Con `define`, una asignación dentro de un bloque crea una `x` local que oculta a la global, igual que el `local x = 99` del ejemplo anterior. `set` se mantiene en el módulo y está cubierta por las pruebas para mostrar la diferencia entre las dos operaciones, pero el evaluador no la usa.

Cerrar un bloque consiste en devolver el padre. Si no hay padre, el usuario escribió `end` sin un `begin` previo y se responde con un error en lugar de ignorarlo:

```lua
function M.close(current)
    if current.parent == nil then
        return Result.fail(Errors.new(
            Errors.Code.NO_OPEN_BLOCK,
            "'end' sin 'begin': no hay ningún bloque abierto",
            "end"))
    end
    return Result.ok(current.parent)
end
```

`begin` y `end` se atienden en el evaluador, como palabras reservadas dentro de la expresión, y no como comandos del REPL. Así pueden aparecer en medio de una línea, como en `begin x 99 = x end`, o en líneas separadas, en cuyo caso el bloque queda abierto entre una línea y otra. Para que el usuario sepa en qué nivel está, el indicador cambia: `rpn> ` en el global y `rpn[1]> ` dentro de un bloque, `rpn[2]> ` dentro de un bloque anidado.

En ejecución se observa lo siguiente. Con `x` global valiendo 7, la línea `begin x 99 = x end` imprime `99`; la línea siguiente, `x`, imprime `7`. Si se abre un bloque con `begin`, se escribe `z 3 =` y luego `end`, la variable `z` deja de existir: `z` responde `[undefined_variable] la variable 'z' no está definida`. El comando `vars` muestra para cada variable visible su valor, su tipo y el entorno donde vive, por ejemplo `x = 1 (int, bloque 1)`; un nombre que existe en el bloque y en el global aparece una sola vez, con el valor del bloque, porque esa es la variable que se usaría. Si una línea falla después de un `begin`, como `begin 5 0 /`, el bloque abierto antes del error sigue abierto, y el indicador `rpn[1]> ` lo hace visible.

`Environment.MAX_DEPTH` fija en 1000 la cantidad máxima de bloques anidados. `open` compara la profundidad del entorno actual antes de crear el hijo, y con 1000 bloques abiertos devuelve un error en lugar de seguir agregando tablas:

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
```

La respuesta es `[max_depth_exceeded] se alcanzó el límite de 1000 bloques anidados`. Sin este control, cada `begin` crearía una tabla nueva y la cadena de padres crecería hasta agotar la memoria; en ese caso Lua lanzaría un error de memoria que el REPL mostraría como `internal_error`, que es un fallo imprevisto y no un error del usuario. El límite también evita que `lookup` y `vars`, que recorren la cadena, tengan que subir por un número arbitrario de niveles.

## 4. Sistema de tipos y chequeo de tipos

### 4.1 Tipos en Lua y momento del chequeo

Lua tiene ocho tipos básicos: `nil`, `boolean`, `number`, `string`, `function`, `userdata`, `thread` y `table` (Ierusalimschy et al., 2020, §2.1). La función `type` devuelve el nombre del tipo de cualquier valor. Desde la versión 5.3 el tipo `number` tiene dos variantes internas, entero y decimal, y en la versión estándar ambos ocupan 64 bits. La función `math.type` permite distinguirlas: devuelve `"integer"`, `"float"`, o `nil` si lo que recibe no es un número (§6.7).

Lua es un lenguaje de tipado dinámico. El manual lo expresa así: las variables no tienen tipos, solo los valores los tienen, y no existen definiciones de tipos en el lenguaje (§2.1). La diferencia con un lenguaje de tipado estático, como Rust o Go, está en el momento en que se detectan los errores de tipos. En un lenguaje estático el compilador revisa el programa antes de ejecutarlo y rechaza, por ejemplo, una suma entre un número y un booleano. En Lua la traducción del archivo no hace esa revisión; el error aparece en el instante en que la suma se ejecuta. Lua tampoco realiza inferencia de tipos, entendida como deducir el tipo de cada variable a partir del código, porque no hay tipos declarados que deducir.

Lo que Lua hace cuando encuentra una operación inválida es lanzar un error. La expresión `5 + true` produce el mensaje `attempt to perform arithmetic on a boolean value` y, si nadie lo atrapa, termina el programa. De forma parecida, `true < 1` produce `attempt to compare boolean with number`. Por eso el evaluador no deja que Lua descubra el problema: revisa los tipos antes de operar y, si no corresponden, devuelve un error controlado que el REPL muestra sin interrumpir la sesión.

Hay además un caso en que Lua convierte tipos por su cuenta: en una operación aritmética, un texto que parece número se convierte en número, de modo que `"10" + 1` da `11` (§3.4.3). El evaluador nunca queda expuesto a esa conversión, porque los números llegan de la consola como texto y se convierten explícitamente con `tonumber` antes de entrar a la pila. Las operaciones del evaluador solo reciben valores ya convertidos.

### 4.2 Equivalencia de tipos

La equivalencia de tipos responde a la pregunta de cuándo dos valores son del mismo tipo. Algunos lenguajes comparan el nombre con que se declaró el tipo y otros comparan su estructura, es decir, qué campos tiene. En Lua la pregunta casi no existe para las tablas: todas son del tipo `table`, sin importar qué campos tengan. Dos tablas con los mismos campos tampoco son iguales entre sí; el operador `==` compara tablas por identidad, y dos tablas solo son iguales si son la misma (Ierusalimschy et al., 2020, §3.4.4).

El evaluador define su propia noción de tipo con el campo `kind` de cada valor, que contiene un texto como `"int"` o `"bool"`. Dos valores son del mismo tipo cuando sus textos son iguales, y los textos en Lua sí se comparan por su contenido. Se trata, entonces, de una equivalencia por nombre: lo que cuenta es la etiqueta que el valor lleva, no los campos que tiene.

### 4.3 Representación de los tokens

Cada token es una tabla con los campos `kind`, `lexeme` y `column`. Las clases posibles se reúnen en una tabla de constantes, que cumple el papel que en otros lenguajes tendría un tipo enumerado:

```lua
M.Kind = {
    NUMBER = "number",
    BOOLEAN = "boolean",
    IDENT = "ident",
    OPERATOR = "operator",
    KEYWORD = "keyword",
}
```

Las constantes son textos y no números para que se lean con facilidad al revisar un token durante una prueba. El código siempre las usa a través de la tabla, como `Tokenizer.Kind.NUMBER`, y no escribe el texto `"number"` directamente, de modo que el nombre de cada clase está definido en un único lugar. Lua no comprueba que la tabla se use bien: si se escribiera `Tokenizer.Kind.NUMBR`, el resultado sería `nil` sin ningún aviso. Esa es una diferencia concreta con los tipos enumerados de un lenguaje estático, donde el compilador rechazaría el nombre mal escrito.

### 4.4 Representación de los valores: unión etiquetada

La consigna pide representar los valores con los tipos compuestos del lenguaje, y menciona entre otras opciones las uniones etiquetadas (*tagged unions*). Una unión etiquetada es un valor que puede ser de varias clases, acompañado de una etiqueta que dice de cuál es. Puede pensarse como una caja con un rótulo: el rótulo dice si dentro hay un entero, un decimal o un booleano, y quien abre la caja lee primero el rótulo para saber qué hacer con el contenido. Lenguajes como Rust tienen esta construcción incorporada; en Lua se arma con una tabla que tiene un campo para la etiqueta y otro para el contenido:

```lua
M.Kind = {
    INT = "int",
    FLOAT = "float",
    BOOL = "bool",
    NAME = "name",
}

local ValueMeta = {}

local function tagged(kind, value)
    return setmetatable({ kind = kind, value = value }, ValueMeta)
end

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

En un lenguaje con uniones etiquetadas incorporadas, el compilador garantiza que la etiqueta coincide con el contenido. En Lua nada impide escribir `{ kind = "int", value = true }`. Por eso los valores solo se crean a través de estas funciones constructoras, y cada una comprueba con `assert` que el contenido corresponde a la etiqueta. `M.float` además suma `0.0` al número, lo que obliga a Lua a guardarlo como decimal aunque llegue un entero; así un valor con etiqueta `float` siempre contiene un decimal de verdad. Si alguna parte del programa intentara crear un valor incorrecto, `assert` lanzaría un error. Ese error indicaría una falla de programación y no un error del usuario, y se trata como tal en la sección 5.3.

La cuarta variante, `name`, es la ficha descrita en la sección 3.2. Lleva el nombre de la variable y el valor que tenía al apilarse:

```lua
function M.name(identifier, current)
    assert(type(identifier) == "string", "value.name: se esperaba un texto")
    return setmetatable({ kind = M.Kind.NAME, name = identifier, value = current }, ValueMeta)
end
```

Una ficha `name` nunca llega a un operador tal cual. Antes de operar, `resolve` la reemplaza por el valor que contiene o devuelve el error de variable no definida:

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

### 4.5 Reglas de tipos del evaluador

Cada operador declara qué tipos acepta, y `check_types` hace la verificación antes de calcular:

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

Las reglas resultantes son las siguientes.

| Operadores | Operandos aceptados | Tipo del resultado |
| --- | --- | --- |
| `+` `-` `*` | dos números | Int si ambos son Int; Float si alguno es Float |
| `/` | dos números, el segundo distinto de cero | Int si ambos son Int y la división es exacta; Float en otro caso |
| `<` `>` | dos números | Bool |
| `==` `!=` | dos números o dos booleanos | Bool |

Las tres primeras filas siguen lo que hace Lua con sus propios números. Cuando los dos operandos son enteros, Lua suma, resta y multiplica como enteros; si alguno es decimal, convierte ambos a decimal (Ierusalimschy et al., 2020, §3.4.1). La función `number_value` traslada ese resultado a la etiqueta correcta y, además, comprueba que quepa en el tipo correspondiente:

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

La división es la excepción. El operador `/` de Lua siempre produce un decimal, incluso en `8 / 2`, que da `4.0` (§3.4.1). En el Mini-REPL se decidió que la división entre enteros dé un entero cuando es exacta y un decimal cuando no lo es. Para saber si es exacta se usa el resto, `%`; si es cero, el cociente se calcula con `//`, la división entera de Lua, que conserva el tipo entero:

```lua
local function divide(a, b)
    if b.value == 0 then
        return Result.fail(Errors.new(Errors.Code.DIVISION_BY_ZERO, "división por cero", "/"))
    end
    if a.kind == Value.Kind.INT and b.kind == Value.Kind.INT and a.value % b.value == 0 then
        return Result.ok(Value.int(a.value // b.value))
    end
    local quotient = a.value / b.value
    if quotient ~= quotient or quotient == math.huge or quotient == -math.huge then
        return arithmetic_overflow("/", "el resultado de / excede el rango de flotantes")
    end
    return Result.ok(Value.float(quotient))
end
```

El cociente se revisa antes de devolverse: si un divisor decimal muy pequeño produjera infinito, `divide` responde `arithmetic_overflow` igual que `number_value`. La comparación `b.value == 0` detecta tanto el entero `0` como el decimal `0.0`, porque para Lua dos números son iguales si representan el mismo valor matemático, sin importar si son enteros o decimales (§3.4.4). La revisión se hace antes de dividir porque el operador `/` de Lua no lanza un error al dividir por cero: `5 / 0` da infinito, que Lua escribe `inf`. Solo la división entera entre enteros, `5 // 0`, produce un error en Lua.

La misma regla de igualdad hace que `2 2.0 ==` dé `true`. La igualdad entre un número y un booleano, en cambio, es una decisión del evaluador. Lua respondería `false` sin quejarse, porque `==` con operandos de tipos distintos siempre da falso (§3.4.4). El evaluador la rechaza con un error de tipos, porque comparar un número con un booleano casi siempre indica una equivocación del usuario, y la consigna pide reportar esas operaciones inválidas. Las comparaciones `<` y `>` solo aceptan números, igual que en Lua.

### 4.6 Límites de los enteros

Los enteros de Lua tienen 64 bits, así que existe un entero máximo, 9223372036854775807. Hay dos situaciones en que ese límite aparece.

La primera es un número escrito por el usuario que no cabe en ese rango. `tonumber("99999999999999999999")` no falla; devuelve el decimal `1e+20`. Si el evaluador lo aceptara, el usuario escribiría un entero y obtendría un decimal sin enterarse. Por eso `push_number` revisa que, si `tonumber` devolvió un decimal, el texto original tenga un punto; si no lo tiene, el número se rechaza:

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
    return Result.fail(Errors.new(Errors.Code.INVALID_TOKEN,
        string.format("el entero '%s' está fuera del rango permitido", lexeme), lexeme))
end
```

La respuesta en la consola es `[invalid_token] el entero '99999999999999999999' está fuera del rango permitido`.

La segunda situación es una operación cuyo resultado se pasa del máximo. Lua no la trata como error: según el manual, cuando una operación entre enteros se desborda, el resultado da la vuelta (§3.4.1). Por ejemplo, `9199999999999999999 1000000000000000000 +` daría `-8246744073709551617`. El evaluador no hereda ese comportamiento: prefiere devolver un error controlado antes que mostrar un número matemáticamente incorrecto. La diferencia es una decisión de diseño del Mini-REPL, no del lenguaje anfitrión.

Para la suma basta comparar con las cotas antes de operar:

```lua
local function checked_add(a, b)
    if b > 0 and a > MAX_INT - b then return nil end
    if b < 0 and a < MIN_INT - b then return nil end
    return a + b
end
```

`MAX_INT` y `MIN_INT` son `math.maxinteger` y `math.mininteger` (§6.7). La resta usa la misma idea con los signos invertidos. La multiplicación puede verificarse dividiendo el producto, pero hay que apartar antes los casos de `0` y `-1`, porque `MIN_INT // -1` también desborda en Lua:

```lua
local function checked_mul(a, b)
    if a == 0 or b == 0 then return 0 end
    if a == -1 then
        if b == MIN_INT then return nil end
        return -b
    end
    if b == -1 then
        if a == MIN_INT then return nil end
        return -a
    end
    local product = a * b -- puede venir con wrap; solo se usa para verificar
    if product // a ~= b then return nil end
    return product
end
```

La división entera tiene un único caso especial, `math.mininteger / -1`, que se comprueba en `divide` antes de calcular el cociente. Las comparaciones no pueden desbordar. Cuando una de estas comprobaciones falla, la función auxiliar devuelve `nil` y `number_value` lo convierte en un error con código `arithmetic_overflow`. Como `apply_operator` valida antes de desapilar, los operandos permanecen en la pila.

### 4.7 Comportamiento en ejecución

En la consola, las reglas anteriores se ven así. `7 2 /` imprime `3.5` y `8 2 /` imprime `4`. `1.5 2 +` imprime `3.5`, y `2.0 2 *` imprime `4.0`: el `.0` indica que el resultado es decimal, porque `Value.tostring` usa el formato de Lua, que siempre escribe la parte decimal de un número decimal. `3 4 <` imprime `true` y `true false ==` imprime `false`. `5 true +` responde `[type_mismatch] el operador + no se puede aplicar a int y bool`, y `true 1 <` responde `[type_mismatch] el operador < no se puede aplicar a bool y int`. `5 0 /` y `5 0.0 /` responden `[division_by_zero] división por cero`. Una suma que se pasa del límite, como `9199999999999999999 1000000000000000000 +`, responde `[arithmetic_overflow] el resultado de + excede el rango de enteros`.

## 5. Subrutinas, paso de parámetros y manejo de memoria

### 5.1 Funciones en Lua

En Lua las funciones son valores como cualquier otro: se pueden guardar en variables y en tablas, pasar como argumento y devolver como resultado (Ierusalimschy et al., 2020, §3.4.11). El proyecto usa esto en tres lugares. Las funciones de cada módulo son campos de la tabla `M`. La tabla `OPERATORS` guarda en el campo `apply` de cada operador la función que hace su cálculo. Y `REPL.run` recibe como argumentos las funciones con que lee la entrada y escribe la salida.

Los parámetros de una función se comportan como variables locales que se inicializan con los argumentos de la llamada. Si la llamada trae menos argumentos que parámetros, los que faltan valen `nil`; si trae más, los sobrantes se descartan (§3.4.11). `REPL.run` aprovecha esto para tener parámetros opcionales:

```lua
function M.run(input, output, write_prompt)
    input = input or io.read
    output = output or print
    write_prompt = write_prompt or function(text)
        io.write(text)
        io.flush()
    end
```

Cuando `main.lua` llama a `REPL.run()` sin argumentos, los tres parámetros valen `nil` y `or` los reemplaza por la lectura del teclado, la escritura en pantalla y una función que escribe el indicador. Las pruebas, en cambio, pasan funciones propias que entregan líneas preparadas de antemano y guardan lo que el REPL imprime, sin usar el teclado ni la pantalla.

Una función de Lua también puede devolver varios resultados a la vez. Si quien la llama los asigna a varias variables, cada una recibe uno; si asigna menos variables, los resultados sobrantes se descartan; si asigna más, las variables que faltan reciben `nil` (§3.4.12). El evaluador usa esto en `local current = Environment.lookup(env, name)`: `lookup` devuelve el valor y el entorno donde lo encontró, pero aquí solo interesa el valor, y el segundo resultado se descarta.

### 5.2 La convención (valor, error)

La consigna pide manejar los errores con el mecanismo propio del lenguaje sin que el programa termine abruptamente, y menciona las tuplas `(valor, error)`. En Lua esa es la forma habitual de informar un error esperado: la función devuelve dos resultados, y la propia biblioteca estándar la usa, por ejemplo en `io.open`, que devuelve `nil` y un mensaje si no puede abrir el archivo. Ierusalimschy (2016) recomienda devolver `nil` y un mensaje cuando el fallo es una situación que quien llama puede esperar y atender, y reservar los errores lanzados para lo que no debería ocurrir. El módulo `result.lua` le da nombre a los dos casos:

```lua
function M.ok(value)
    return value, nil
end

function M.fail(message)
    return nil, message
end
```

Todas las subrutinas del tokenizador, del evaluador y del entorno siguen ese contrato: en caso de éxito devuelven el valor y `nil`; en caso de fallo, `nil` y una tabla de error. Quien llama comprueba el segundo resultado y, si hay error, lo devuelve hacia arriba sin hacer nada más. Así un error que se origina en lo profundo del programa llega hasta el REPL a través de una cadena de retornos normales. Una división por cero nace en `divide`, que la devuelve a `apply_operator`; esta la devuelve a `eval`, que detiene el recorrido de tokens y la devuelve a `eval_line`, y desde allí llega a `run`, que la imprime.

Los errores son tablas creadas por `errors.lua`, con un código fijo, un mensaje para el usuario y el detalle de la palabra que lo causó:

```lua
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
```

El código sirve para que un programa, como el archivo de pruebas, distinga los errores sin depender del texto del mensaje. El mensaje sirve para que una persona entienda qué pasó. En pantalla se muestran ambos con la forma `[código] mensaje`.

### 5.3 Errores lanzados y pcall

Lua tiene también un mecanismo parecido a las excepciones de otros lenguajes. La función `error` interrumpe la ejecución, y el error sube por las llamadas hasta que alguna lo atrapa con `pcall`. Si nadie lo atrapa, el programa termina (Ierusalimschy et al., 2020, §2.3). `pcall` recibe una función y sus argumentos y la ejecuta en "modo protegido". Si todo sale bien, devuelve `true` seguido de los resultados de la función; si ocurre un error, devuelve `false` y el mensaje.

El proyecto no usa este mecanismo para los errores del usuario. Una división por cero o un nombre mal escrito son parte del uso normal de una calculadora, y tratarlos como valores de retorno deja a la vista, en cada llamada, qué puede fallar y qué se hace en ese caso. `pcall` aparece en un solo lugar, el REPL, como protección contra fallas que no deberían ocurrir:

```lua
            local ok, value, err, new_env = pcall(M.eval_line, command, stack, env)
            if not ok then
                output(Errors.format(Errors.new(Errors.Code.INTERNAL_ERROR,
                    "fallo interno: " .. tostring(value))))
```

Si un error de programación hiciera fallar uno de los `assert` de `value.lua`, o si Lua lanzara un error por una operación no prevista, `pcall` lo atraparía. El REPL mostraría `[internal_error]` con la descripción y seguiría esperando la siguiente línea, en lugar de terminar. Los dos mecanismos tienen entonces funciones separadas: `(valor, error)` para lo esperado y `pcall` para lo imprevisto.

### 5.4 Paso de parámetros: valor y referencia

Este es el punto que la consigna pide demostrar pasando explícitamente la pila y el entorno a las subrutinas. Para explicarlo hay que distinguir dos clases de valores en Lua.

Los números, los booleanos, los textos y `nil` se guardan directamente en la variable. Pasarlos a una función entrega una copia, y si la función cambia su parámetro, la variable original no se entera. Con las tablas, en cambio, el manual es explícito: las tablas y las funciones son objetos, y las variables no contienen esos objetos sino solo referencias a ellos; la asignación, el paso de parámetros y la devolución de resultados siempre manipulan referencias y nunca hacen copias (Ierusalimschy et al., 2020, §2.1). Una referencia es la indicación de dónde está la tabla en memoria. Si dos variables tienen la referencia a la misma tabla, ambas ven cualquier cambio que se haga en ella.

Formalmente Lua tiene un solo mecanismo: todos los argumentos se pasan por valor, pero en el caso de una tabla ese valor es la referencia. Scott (2015) llama a este mecanismo paso por compartición, y es el mismo que usan, entre otros, Java para los objetos y Python. De él se siguen dos consecuencias, y el Mini-REPL muestra ambas.

La primera es que una función que recibe una tabla puede modificar su contenido, y quien la llamó ve los cambios. Así trabaja la pila. El REPL crea una sola tabla `stack` y la pasa a `eval_line`, que la pasa a `eval`, que la pasa a `push_number` y a `apply_operator`. Todas reciben la referencia a la misma tabla, y lo que una apila o desapila lo ven todas las demás. Ninguna función devuelve la pila, porque no hace falta. Las pruebas lo verifican directamente:

```lua
local stack = {}
Evaluator.push_number("5", stack)
Evaluator.push_number("2", stack)
check("push_number modifica la pila del llamador", #stack == 2)
Evaluator.apply_operator("+", stack)
check("apply_operator deja un solo valor en la misma pila",
    #stack == 1 and stack[1].value == 7)
```

La segunda consecuencia es que una función no puede cambiar a qué tabla apunta la variable de quien la llamó. Si dentro de una función se escribe `stack = {}`, solo el parámetro pasa a apuntar a una tabla nueva; la variable original sigue apuntando a la tabla anterior, con su contenido intacto. Por eso `REPL.clear` vacía la pila borrando sus elementos uno por uno, en lugar de reemplazarla:

```lua
function M.clear(stack)
    for i = #stack, 1, -1 do
        stack[i] = nil
    end
end
```

El entorno muestra esta segunda consecuencia con más claridad. `begin` y `end` no modifican el contenido del entorno; cambian cuál es el entorno activo. Dentro de `eval`, la instrucción `env = new_env` solo cambia el parámetro local de `eval`, y la variable `env` del REPL seguiría apuntando al entorno anterior. Por eso `eval` devuelve el entorno activo como tercer resultado, y el REPL actualiza su propia variable con `env = new_env` después de cada línea. La prueba correspondiente comprueba que la variable de quien llama no cambió y que el entorno nuevo llegó por el valor de retorno:

```lua
local caller_env = Environment.new(nil)
local _, _, returned_env = Evaluator.eval(Tokenizer.tokenize("begin"), {}, caller_env)
check("eval no cambia la variable del llamador; devuelve el entorno nuevo",
    caller_env.depth == 0 and returned_env.parent == caller_env)
```

`define`, en cambio, sí modifica el contenido del entorno, porque escribe en su tabla `vars`. Esa modificación se ve desde el REPL sin necesidad de devolver nada, por la misma razón que se ven los cambios en la pila.

Las referencias también se comparten entre estructuras. Cuando se apila una ficha `name`, su campo `value` apunta a la misma tabla de valor que está guardada en el entorno, sin copiarla. Compartir es seguro porque los valores nunca se modifican después de creados: cada operación produce un valor nuevo y deja intactos sus operandos. Si algún código cambiara el campo `value` de un valor compartido, el cambio aparecería al mismo tiempo en la pila y en la variable.

Lua no tiene punteros que el programa pueda manipular, como los de C, ni reglas de préstamo como las de Rust, en las que el compilador controla quién puede modificar un dato y durante cuánto tiempo. Cualquier función que tenga la referencia a una tabla puede leerla y modificarla. La disciplina de no modificar los valores después de creados la impone el propio código, no el lenguaje.

### 5.5 Manejo de memoria

Lua administra la memoria automáticamente. El programa nunca pide ni libera memoria de forma explícita: cada tabla nueva ocupa memoria al crearse, y un recolector de basura la libera cuando la tabla deja de ser alcanzable, es decir, cuando ninguna variable ni ninguna otra tabla en uso conserva una referencia a ella (Ierusalimschy et al., 2020, §2.5). En Lua 5.4 el recolector trabaja por defecto en pasos pequeños intercalados con la ejecución del programa, y puede cambiarse a un modo que revisa con más frecuencia los objetos recién creados (§2.5.1 y §2.5.2).

En el Mini-REPL cada línea crea tablas: los tokens, los valores intermedios y los errores. Cuando la línea termina y la pila se vacía en la siguiente, ya nada conserva referencias a esas tablas, y el recolector las libera en algún momento posterior. Borrar los elementos de la pila con `stack[i] = nil` cumple aquí una segunda función: elimina las referencias que mantendrían vivos los valores de la línea anterior.

El caso más interesante es el cierre de un bloque. `close` devuelve el entorno padre, y el REPL deja de guardar la referencia al entorno del bloque. Como el padre no apunta a sus hijos, el entorno del bloque y todas sus variables locales quedan sin referencias y el recolector los libera. Es el equivalente, construido a mano, de lo que pasa con las variables locales de Lua al terminar un bloque `do ... end`.

Las pruebas comprueban esa liberación con una tabla débil. Una tabla débil es una tabla cuyas referencias no cuentan para el recolector: si un objeto solo es referenciado desde una tabla débil, el recolector lo libera igual y lo quita de ella. Se declara con el campo `__mode` en su metatabla; el valor `"v"` indica que los valores de la tabla son referencias débiles (§2.5.4):

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

La función abre un bloque, define una variable en él, guarda una referencia débil al bloque y lo cierra. Después, `collectgarbage("collect")` fuerza un ciclo completo del recolector. Si el entorno del bloque hubiera quedado referenciado en algún lugar, `weak.block` lo seguiría mostrando; la prueba confirma que desapareció, mientras el entorno global, que sí sigue en uso, permanece. El trabajo se hace dentro de una función para que las variables locales `block_env` y `global_env` dejen de existir al salir de ella, y así no retengan al bloque. Los paréntesis en `return (Environment.close(block_env))` conservan solo el primer resultado de `close` (§3.4.12).

## 6. Abstracción de datos y su equivalente a la programación orientada a objetos

### 6.1 Las tablas como único mecanismo de estructura

Lua no tiene clases, registros ni arreglos como construcciones separadas. Todas se construyen con tablas (Ierusalimschy et al., 2020, §2.1). Sus autores explican que fue una decisión deliberada: un único mecanismo general mantiene el lenguaje pequeño y fácil de implementar, y deja que cada programa construya las estructuras que necesita (Ierusalimschy et al., 2007). En el proyecto, la misma construcción cumple papeles distintos según cómo se use. La pila es una lista, con claves 1, 2, 3 y siguientes. Un token, un valor o un error es un registro, con campos con nombre como `kind` y `value`. `OPERATORS` y `KEYWORDS` son diccionarios, que asocian cada lexema con su información. Y cada módulo es una tabla de funciones.

### 6.2 Módulos y ocultamiento de información

Abstraer un dato significa ofrecer operaciones para usarlo y esconder cómo está construido por dentro, de modo que el resto del programa dependa de las operaciones y no de la construcción (Sebesta, 2019). En Lua esto se logra con módulos y variables locales. Todo lo que un archivo declara como `local` es invisible desde fuera, porque el alcance léxico de la sección 3.4 lo limita al propio archivo. Solo lo que se guarda en la tabla `M` devuelta queda disponible para los demás.

`environment.lua` es el ejemplo más completo. Desde fuera, un entorno se maneja con `new`, `lookup`, `get`, `define`, `set`, `open`, `close`, `names` y `scope_label`. Ni el evaluador ni el REPL escriben en los campos `vars` o `parent`; el REPL solo lee `depth` para armar el indicador. Si mañana los entornos se guardaran de otra forma, por ejemplo como una lista de tablas en lugar de una cadena de padres, solo habría que cambiar ese archivo. Del mismo modo, `evaluator.lua` esconde `check_types`, `divide`, `number_value`, `checked_add`, `checked_sub`, `checked_mul`, `underflow` y `run_keyword`, que son detalles de cómo evalúa, y ofrece `eval` y las operaciones sobre la pila.

### 6.3 Metatablas

Una metatabla es una tabla común que, asociada a otra tabla, cambia cómo se comporta esta última en ciertas operaciones. Los campos de la metatabla con nombres especiales, como `__add`, `__index` o `__tostring`, indican qué hacer cuando se suma la tabla, cuando se consulta un campo que no existe o cuando se la convierte en texto (Ierusalimschy et al., 2020, §2.4). Las metatablas son el mecanismo con que Lua permite construir algo parecido a las clases.

El proyecto las usa de forma acotada. Todos los valores comparten la metatabla `ValueMeta`, y todos los errores comparten `ErrorMeta`. Ambas definen `__tostring`, que la función `tostring` consulta antes de convertir una tabla en texto (§6.1):

```lua
ValueMeta.__tostring = M.tostring
```

Sin esa línea, `print(Value.float(2.5))` mostraría algo como `table: 0x55d1c8a0`, que es la forma en que Lua escribe cualquier tabla. Con ella muestra `2.5`. Este comportamiento compartido, definido una sola vez para todos los valores, es lo más cercano en el proyecto a un método de clase.

La forma habitual de imitar clases en Lua va más lejos (Ierusalimschy, 2016). Se usa el campo `__index` para que los objetos busquen sus métodos en una tabla común, y se llaman con dos puntos, como `env:get(name)`. Esa escritura es solo una abreviatura de `env.get(env, name)` (§3.4.10). El proyecto no la usa a propósito. La consigna pide que la pila y el entorno se pasen explícitamente a las subrutinas, y la forma con dos puntos esconde justamente ese parámetro. `Environment.get(env, name)` deja a la vista qué entorno recibe la función.

### 6.4 Polimorfismo e interfaces

En la programación orientada a objetos, el polimorfismo permite tratar de la misma forma a objetos de clases distintas, y una interfaz es el conjunto de operaciones que esas clases se comprometen a ofrecer. Lua no tiene interfaces declaradas. Cualquier tabla que tenga los campos que el código espera sirve, y si le falta alguno, el error aparece en el momento de usarlo. El proyecto aplica esta idea en cuatro lugares.

El primero es la unión etiquetada. Un valor de la pila puede ser de cuatro variantes, y el código decide qué hacer leyendo la etiqueta: `resolve` trata distinto a una ficha `name`, y `check_types` pregunta si los operandos son números o booleanos. Es el reemplazo, en un lenguaje sin clases, de tener una clase por variante.

El segundo es la tabla de operadores. Todas sus entradas tienen la misma forma, un campo `accepts` y una función `apply` que recibe dos valores y devuelve `(valor, error)`:

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

`apply_operator` llama a `operator.apply(a, b)` sin saber qué operador es. Esa forma común funciona como una interfaz acordada: la división tiene una función con nombre propio, `divide`, porque puede fallar, y las demás son funciones escritas en el mismo lugar, pero desde `apply_operator` todas se usan igual.

El tercero es el contrato `(valor, error)`, que siguen todas las subrutinas de todos los módulos. Ningún mecanismo del lenguaje lo obliga, pero gracias a él cualquier función del proyecto se llama y se revisa de la misma manera.

El cuarto son los parámetros `input`, `output` y `write_prompt` de `REPL.run`. El REPL no sabe si lee del teclado o de una lista preparada; solo necesita una función que, al llamarla, devuelva la siguiente línea o `nil`. Las pruebas aprovechan esto para ejecutar una sesión completa sin intervención humana.

### 6.5 Composición

La orientación a objetos suele reutilizar comportamiento por herencia, haciendo que una clase extienda a otra. El proyecto no usa herencia y construye sus estructuras por composición, es decir, haciendo que una tabla contenga o apunte a otra. Un entorno contiene una referencia a su padre, y de esa relación sale todo el mecanismo de alcance. Una ficha `name` contiene el valor que representa. El evaluador no hereda de nadie: usa los módulos de valores, entornos y errores llamando a sus funciones.

## 7. Pruebas y sesión de ejecución

### 7.1 Pruebas automáticas

El archivo `tests/test_evaluator.lua` no usa ninguna biblioteca externa. Se ejecuta con `lua tests/test_evaluator.lua` desde la raíz del proyecto. La función `check` recibe una descripción y una condición; si la condición falla, imprime la descripción junto con lo que se obtuvo. Al final se muestra el total de comprobaciones correctas y fallidas, y el programa termina con código 0 si todo pasó o con código 1 si algo falló, lo que permite usarlo desde otras herramientas.

Las comprobaciones están agrupadas en ocho partes. La primera cubre la aritmética y las comparaciones, incluidos el orden de los operandos, la mezcla de enteros y decimales y la regla de la división. La segunda cubre cada clase de error: división por cero, pila insuficiente, tipos incompatibles, tokens inválidos, enteros fuera de rango, desbordamiento aritmético, variables no definidas, asignaciones mal formadas y `end` sin `begin`. La tercera cubre las variables y las expresiones que las usan. La cuarta cubre los bloques, el ocultamiento, el anidamiento, el límite de profundidad y la diferencia entre `define` y `set`. La quinta cubre el paso de la pila y del entorno, la sexta la liberación de memoria, la séptima las metatablas y la octava una sesión completa del REPL con entrada simulada, cuya salida debe coincidir línea por línea con la esperada. La ejecución correcta termina informando cero comprobaciones fallidas.

### 7.2 Sesión comentada

La siguiente sesión es la misma que verifica la octava parte de las pruebas. Las líneas que empiezan con `rpn> ` o `rpn[1]> ` son lo que escribe el usuario, y las demás son las respuestas del programa.

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

La primera línea suma dos enteros y el resultado es el entero 7. La segunda apila la ficha de `x`, que todavía no existe, calcula `5 2 +` y asigna el 7 a `x` en el entorno global; la pila queda vacía y no se imprime nada. La tercera lee `x`. La cuarta es la expresión `(x + 5) × 2` de la consigna, que con `x` igual a 7 da 24. La quinta muestra que una división entera no exacta produce un decimal, y la sexta que una comparación produce un booleano.

Las cinco líneas siguientes son errores controlados. El primero es un error de tipos, el segundo una división por cero, el tercero una pila insuficiente, el cuarto un desbordamiento aritmético y el quinto un token inválido. Los cuatro primeros corresponden a las clases que exige la consigna; el desbordamiento se agrega porque es un error de ejecución que Lua no reporta por su cuenta. En todos los casos el programa sigue funcionando y la línea siguiente se evalúa con normalidad.

`begin x 99 = x end` abre un bloque, crea en él una `x` local con 99, la lee y cierra el bloque, todo en la misma línea; se imprime 99, el valor que `x` tenía dentro del bloque. La línea siguiente confirma que la `x` global sigue valiendo 7. Luego se abre un bloque que queda activo entre líneas, como indica el cambio del indicador a `rpn[1]> `. Dentro de él se asignan `x` e `y`, y `vars` muestra que ambas pertenecen al bloque 1; la `x` global no aparece porque la del bloque la oculta. Al cerrar el bloque, `vars` muestra solo la `x` global con su valor original, y la variable `y` ya no existe. El último `end` no tiene un bloque que cerrar y se informa como error. `exit` termina la sesión.

## 8. Bibliografía

Facultad Experimental de Ciencias y Tecnología. (2026). *Asignación #1, CAO604 Lenguajes de Programación, semestre 1-2026*. Universidad de Carabobo.

Hamblin, C. L. (1962). Translation to and from Polish notation. *The Computer Journal, 5*(3), 210-212.

Ierusalimschy, R. (2016). *Programming in Lua* (4.ª ed.). Lua.org.

Ierusalimschy, R., de Figueiredo, L. H., y Celes, W. (2005). The implementation of Lua 5.0. *Journal of Universal Computer Science, 11*(7), 1159-1176. https://www.lua.org/doc/jucs05.pdf

Ierusalimschy, R., de Figueiredo, L. H., y Celes, W. (2007). The evolution of Lua. En *Proceedings of the Third ACM SIGPLAN Conference on History of Programming Languages (HOPL III)*. ACM. https://www.lua.org/doc/hopl.pdf

Ierusalimschy, R., de Figueiredo, L. H., y Celes, W. (2020). *Lua 5.4 reference manual*. Lua.org, PUC-Rio. https://www.lua.org/manual/5.4/

Scott, M. L. (2015). *Programming language pragmatics* (4.ª ed.). Morgan Kaufmann.

Sebesta, R. W. (2019). *Concepts of programming languages* (12.ª ed.). Pearson.
