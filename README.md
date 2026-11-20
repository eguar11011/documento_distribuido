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

## Arquitectura propuesta del editor

Esta primera etapa deja el proyecto como un esqueleto: aún no se pueden editar
ni sincronizar documentos. El núcleo del CRDT será independiente de los
procesos, la red y Nerves para poder probarlo en un host.

- `DocumentoDistribuido.Treedoc`: estado y reglas puras del documento. Por ahora
  `new/0` solo crea un estado vacío; faltan inserción, eliminación y lectura.
- `Treedoc.PosID`: identificador de una posición del árbol. Sus componentes son
  provisionales: falta definir cómo se generan y ordenan, incluido el desempate
  determinista de inserciones concurrentes y la identidad estable de cada réplica.
- `Treedoc.Operation.Insert` y `Treedoc.Operation.Delete`: formas iniciales para
  representar operaciones. Faltan la validación, identidad de operación y los
  metadatos causales que necesite el algoritmo.
- `Document`: futuro GenServer propietario del estado de un documento; serializará
  solicitudes locales y la aplicación de operaciones recibidas.
- `API`: futura interfaz local para consultar y editar documentos, delegando en
  `Document` sin exponer los detalles de transporte.
- `Discovery`: descubrirá pares en la red local. mDNS ya está disponible en la
  configuración del dispositivo, pero aún no anuncia ni descubre el editor.
- `Transport`: enviará y recibirá mensajes entre pares. El protocolo está por elegir.
- `Sync`: reconciliará réplicas tras conexiones o desconexiones y solicitará la
  información que falte, usando `Transport`.
- `Persistence`: guardará y recuperará el estado y los metadatos necesarios. La
  ubicación y el formato siguen pendientes.

Solo los tipos de datos y `Treedoc.new/0` tienen implementación en esta etapa;
los demás módulos son límites documentados, no procesos ni servicios activos.
Antes de implementar el CRDT se definirán y probarán sus reglas de orden,
tratamiento de eliminaciones y operaciones fuera de orden, idempotencia y
convergencia entre réplicas. También habrá que decidir cómo persistir la
identidad y el contador de cada réplica, las marcas de borrado y la información
necesaria para recuperar o sincronizar un documento.

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

Las pruebas actuales comprueban únicamente la construcción del estado vacío y
las estructuras iniciales; todavía no prueban el comportamiento de un CRDT.
