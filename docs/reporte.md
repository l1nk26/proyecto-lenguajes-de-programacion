# Reporte técnico — Mini-REPL RPN en Lua

> Outline del PDF a entregar. Completar con extractos reales del código de
> `src/` una vez implementado el componente práctico.

## 1. Nombres, binding, estructuras de control y scoping

- Nombres en Lua: variables globales vs. locales; tablas como entornos.
- Binding: cómo `tokenizer.lua` y `environment.lua` asocian un lexema a una
  entrada de la tabla de símbolos.
- Estructuras de control: bucle `while` del REPL y despacho por token en
  `evaluator.lua`.
- Scoping: cadena `parent` en `environment.lua`, comandos `begin`/`end` y
  shadowing. Referenciar: `environment.open`, `environment.close`.

## 2. Sistema de tipos y chequeo de tipos

- Tipado dinámico de Lua; diferencia entre `integer` y `float` (`math.type`).
- Tagged union en `value.lua` (`kind`: int / float / bool).
- Chequeo en tiempo de ejecución en `evaluator.apply_operator` y error
  `type_mismatch`.

## 3. Subrutinas, paso de parámetros y memoria

- Funciones de Lua como subrutinas; múltiples retornos `(valor, error)`.
- Las tablas se pasan como referencia: pila y entorno mutables.
- Gestión de memoria: garbage collector de Lua; ciclo de vida de los entornos
  al cerrar un bloque.

## 4. Abstracción de datos y POO (o equivalente)

- Tablas con metatables como sustituto de clases; `value.lua` como tipo
  algebraico simulado.
- Equivalencia de interfaces: contrato común de las subrutinas
  `(valor, error)` en todos los módulos.

## Anexos

- Extractos comentados del código fuente.
- Sesión de prueba (ver `README.md`).
