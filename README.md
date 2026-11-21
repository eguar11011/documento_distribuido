# DocumentoDistribuido

**TODO: Add description**

## Targets

Nerves applications produce images for hardware targets based on the
`MIX_TARGET` environment variable. If `MIX_TARGET` is unset, `mix` builds an
image that runs on the host (e.g., your laptop). This is useful for executing
logic tests, running utilities, and debugging. Other targets are represented by
a short name like `rpi5` that maps to a Nerves system image for that platform.
All of this logic is in the generated `mix.exs` and may be customized. For more
information about targets see:

https://nerves.hexdocs.pm/supported-targets.html

## Getting Started

To start your Nerves app:
  * `export MIX_TARGET=my_target` or prefix every command with
    `MIX_TARGET=my_target`. For example, `MIX_TARGET=rpi5`
  * Install dependencies with `mix deps.get`
  * Create firmware with `mix firmware`
  * Burn to an SD card with `mix burn`

## Learn more

  * Official docs: https://nerves.hexdocs.pm/getting-started.html
  * Official website: https://nerves-project.org/
  * Forum: https://elixirforum.com/c/nerves-forum
  * Elixir Discord #nerves channel: https://discord.gg/elixir
  * Source: https://github.com/nerves-project/nerves

## Arquitectura del editor

El núcleo implementado es puro y se puede probar en el host. Permite generar
posiciones y editar un documento local por átomos; todavía no existe un editor
completo ni sincronización entre dispositivos.

- `DocumentoDistribuido.Treedoc`: mantiene átomos y eliminaciones, genera
  operaciones locales, aplica operaciones recibidas y devuelve el texto visible.
- `Treedoc.PosID`: valida, compara y genera caminos en el árbol extendido. Cada
  mininodo lleva un desambiguador UDIS `{contador, réplica}`, ordenado primero
  por contador y luego por réplica. El componente `:root` representa el
  mininodo de la raíz.
- `Treedoc.Operation.Insert` y `Treedoc.Operation.Delete`: representan las
  operaciones aplicadas por el núcleo.
- `Document`: futuro GenServer propietario del estado de un documento.
- `API`: futura interfaz local para consultar y editar documentos.
- `Discovery`: descubrirá pares; la configuración mDNS existente aún no anuncia
  ni descubre el editor.
- `Transport`: enviará y recibirá mensajes entre pares; el protocolo está por elegir.
- `Sync`: reconciliará réplicas y solicitará la información que falte.
- `Persistence`: guardará y recuperará documentos y metadatos de réplica.

Los últimos seis módulos son límites documentados; no inician procesos ni
servicios. La identidad única y el contador persistente de cada réplica siguen
pendientes: hasta implementarlos, quien llama al núcleo debe aportar un par
`{contador, réplica}` diferente en cada inserción, incluso tras reinicios y al
editar otros documentos. Solo se detecta la reutilización que ya se haya
observado en el documento actual. No se debe usar este núcleo como editor
distribuido completo.

### Ejemplo del núcleo

```elixir
alias DocumentoDistribuido.Treedoc

doc = Treedoc.new()
{:ok, doc, insertar_a} = Treedoc.insert(doc, 0, "A", {1, "replica-a"})
{:ok, doc, insertar_b} = Treedoc.insert(doc, 1, "B", {2, "replica-a"})
Treedoc.text(doc) # "AB"
{:ok, doc, borrar_a} = Treedoc.delete(doc, 0)
Treedoc.text(doc) # "B"

# Las operaciones se pueden aplicar a otra copia del documento:
{:ok, copia} = Treedoc.apply(Treedoc.new(), insertar_a)
{:ok, copia} = Treedoc.apply(copia, insertar_b)
{:ok, copia} = Treedoc.apply(copia, borrar_a)
Treedoc.text(copia) # "B"
```

Cada inserción agrega un átomo, que puede ser una cadena de varios caracteres.
Los índices de inserción y borrado cuentan átomos visibles, no bytes ni
caracteres. Las funciones devuelven `{:ok, documento, operación}` o un error;
los datos son inmutables, por lo que el llamador conserva el nuevo documento.

`PosID.between/3` genera un descendiente de uno de los mininodos que delimitan
el hueco. Esta estrategia simple respeta el orden implementado, pero no es una
transcripción literal del algoritmo 1 del artículo. No equilibra el árbol: las
rutas pueden crecer con las ediciones y las lecturas ordenan todos los átomos.

El núcleo conserva marcas de borrado y valores asociados a PosID incluso tras
un borrado: así una operación duplicada o recibida antes de su inserción no
resucita contenido y se puede detectar una inserción conflictiva. Esto consume
memoria y todavía no hay compactación ni recolección de marcas. Un mismo PosID
con valores distintos produce `{:error, :position_conflict}`; la unicidad global
depende de que el llamador no reutilice los desambiguadores.

El diseño se basa en Preguiça et al., *A commutative replicated data type for
cooperative editing* (2009), secciones 2 y 3. El artículo presupone entrega en
orden causal; conservar marcas aun antes de recibir la inserción es una decisión
adicional de esta implementación. Para comparar rutas se sigue el recorrido
infijo y los ejemplos de las figuras 3 y 4: la regla impresa que compara un
componente `0` con un mininodo no distingue el caso de un descendiente derecho
del nodo mayor y, aplicada literalmente al ejemplo de la figura, parece ubicar
Z antes de W. La prueba del ejemplo deja explícita esta interpretación, que debe
revisarse si se adopta literalmente la generación de PosID del algoritmo 1.

Nerves y las dependencias existentes aportan el sistema y las herramientas para
firmware, supervisión OTP, configuración de interfaces mediante VintageNet,
acceso SSH y anuncios mDNS. El proyecto debe implementar las reglas del editor,
el descubrimiento específico de sus pares, el transporte, la sincronización y
la persistencia. La distribución Erlang no se inicia automáticamente.

La configuración actual activa `wlan0` con `VintageNetWiFi`, pero no configura
el SSID Ewu ni sus credenciales. Su aprovisionamiento queda para una etapa
posterior; no se deben incorporar credenciales al código fuente. Se conservan
sin cambios la configuración de Nerves, SSH y red, así como el supervisor vacío.

## Pruebas en el host

Con Elixir, Erlang, el archivo bootstrap de Nerves y las dependencias del proyecto
instalados, se pueden ejecutar en Ubuntu sin compilar firmware:

```sh
MIX_TARGET=host mix test
```

Las pruebas cubren generación y orden de posiciones, edición local,
inserciones concurrentes, convergencia, duplicados y borrados fuera de orden.
La sincronización por red todavía no está implementada.
