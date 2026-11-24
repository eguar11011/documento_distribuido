# Documento distribuido para Raspberry Pi

Editor compartido sin servidor central para la Raspberry Pi 4 y otros nodos de
la misma red. La implementación activa utiliza el contrato del proyecto de
referencia: Treedoc por operaciones, relojes vectoriales, descubrimiento por
multicast y retransmisión del historial al reconectar. La interfaz de prueba es
IEx por SSH. Cada nodo guarda su historial antes de aplicar y enviar cambios.

El motor `CpdDoc` y sus pruebas se adaptaron de
[Carlixgonzam/distribution-project-](https://github.com/Carlixgonzam/distribution-project-/tree/main/documento),
commit `ad9d665352b0e60763ebc78743d180b30b617f2e`; el contrato de red se
describe en su [PROTOCOL.md](https://github.com/Carlixgonzam/distribution-project-/blob/main/PROTOCOL.md).
El repositorio de referencia consultado no incluye un archivo de licencia;
verifica los permisos correspondientes antes de redistribuir este código.

El núcleo anterior `DocumentoDistribuido.Treedoc` se conserva con sus pruebas
como implementación experimental independiente. Sus estructuras no son el
formato de red del contrato y no alimentan el documento de `CpdDoc`.

## Preparación

Necesitas Elixir/Erlang y las herramientas de Nerves instaladas en el equipo
que compila, una Raspberry Pi 4, una microSD y una red Wi-Fi WPA2 personal
compartida por la Pi y el computador. Desactiva el aislamiento entre clientes
del router. El firmware incorpora las claves públicas SSH de `~/.ssh` del
equipo que lo compila; necesitas conservar la clave privada correspondiente.

La versión de Nerves fijada actualmente para `rpi4` usa Erlang/OTP 29. Instala
Erlang 29 y una versión compatible de Elixir, además de Hex y Nerves Bootstrap.
Las pruebas de host también funcionan con Erlang/OTP 28.

Desde este directorio, ejecuta las pruebas locales:

```sh
MIX_TARGET=host mix deps.get
MIX_TARGET=host mix test
```

Las pruebas distribuidas arrancan nodos Erlang locales y necesitan poder abrir
sockets y ejecutar `epmd`.

## Crear e instalar el firmware

Abre una shell con las versiones compatibles, sustituye los valores por los de
tu red y ejecuta en tu computador:

```sh
mise exec erlang@29.1.2 elixir@1.20.5-otp-29 -- zsh
export MIX_TARGET=rpi4
export HOTSPOT_SSID='nombre de tu red'
export HOTSPOT_PSK='clave de tu red'
# Opcional: segunda red, preferida cuando ambas están disponibles.
export HOTSPOT_SSID_2='nombre de la segunda red'
export HOTSPOT_PSK_2='clave de la segunda red'
mix deps.get
mix firmware
mix burn
exit
```

Para actualizar una Pi que ya usa Nerves y acepta tu clave SSH, ejecuta
`mix upload <IP-de-la-Pi>` después de `mix firmware`, en lugar de `mix burn`.

`mix burn` solicita seleccionar una unidad y sobrescribe la tarjeta elegida:
revisa cuidadosamente que sea la microSD. Las credenciales quedan incluidas en
el firmware; no compartas la imagen con personas que no deban conocerlas. Los
archivos de firmware de prueba deben recompilarse con la red real antes de
instalarlos. La configuración supone dominio regulatorio `CO`. `exit` vuelve
a la shell anterior después de grabar.

Inicia la Pi con la tarjeta, espera a que se conecte al Wi-Fi y entra desde el
computador en la misma red:

```sh
ssh nerves-XXXX.local
```

Sustituye `XXXX` por el identificador de la Pi, o utiliza su IP asignada por el
router. El nombre exacto se puede consultar en el router o en la consola serie.
La Pi anuncia su nombre propio; no se usa `nerves.local`, que sería ambiguo con
varias placas. SSH abre una consola IEx.

## Probar una Pi y un computador

En la consola IEx de la Pi:

```elixir
CpdDoc.estado()
CpdDoc.insertar(0, "Hola desde la Raspberry")
CpdDoc.texto()
```

En otra terminal del computador, averigua su IPv4 en esa misma red y arranca un
segundo nodo con un nombre único; reemplaza `192.168.1.10` por tu IP real:

```sh
MIX_TARGET=host iex --name laptop@192.168.1.10 --cookie cpd2026 \
  --erl '-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228 prevent_overlapping_partitions false' -S mix
```

En el IEx del computador, espera unos segundos y comprueba:

```elixir
CpdDoc.estado()   # :vecinos muestra los nodos conectados
CpdDoc.texto()    # debe mostrar el texto insertado en la Pi
CpdDoc.insertar(0, "PC: ")
```

En la Pi, `CpdDoc.texto()` debe mostrar `"PC: Hola desde la Raspberry"`.
Para borrar, por ejemplo, los primeros cuatro grafemas: `CpdDoc.borrar(0, 4)`.
Los índices cuentan grafemas visibles, empiezan en cero y `borrar/2` recibe
índice y cantidad. `CpdDoc.insertar/2` devuelve `:ok` o un error.

Si no aparecen vecinos, consulta `CpdDoc.estado().nodo` en un nodo y conéctalo
manualmente desde el otro: `CpdDoc.conectar("nombre@192.168.1.23")`. Revisa
las IP, el aislamiento del router, multicast y el firewall: TCP 4369 y
4218–4228, UDP 45892. La cookie compartida `cpd2026` y la distribución Erlang
son para una red de confianza; no expongas estos puertos a Internet.

## Datos, reinicio y límites

La Pi guarda el historial y una identidad de época en `/data/cpd_doc`; el host
guarda por defecto en `datos/<nombre>.log` (se puede cambiar el directorio con
`CPD_DOC_DATOS`). No borres el historial de un host y vuelvas a editar con el
mismo nombre de nodo: usa otro nombre para evitar reutilizar números de
operación. Al reinstalar una tarjeta se crea una época nueva. Si el historial
se daña, se conserva el prefijo válido y se exige reiniciar con otra identidad
cuando corresponda. Si falla la escritura, `estado().error_disco` informa el
error y la réplica deja de aceptar operaciones hasta reiniciar y recuperar el
almacenamiento.

La Pi necesita obtener una IPv4 válida en `eth0` o `wlan0` al menos una vez por
arranque antes de editar. Si ambas están disponibles usa Ethernet; al perder
esa dirección usa Wi-Fi. Si cambia de interfaz o IP, la distribución se reinicia
y los nodos vuelven a conectarse. Las configuraciones de red guardadas por
VintageNet prevalecen sobre las incluidas como valores iniciales en el firmware.
Tras desconectarse puede seguir editando bajo su última identidad y reconciliar
al reconectar. Las marcas de borrado y el historial crecen sin
compactación y se reenvía el historial completo al reconectar: adecuado para
una demostración de pocos nodos, no para documentos grandes. Cambiar la IP
cambia el nombre de nodo. Se verificaron la actualización y la sincronización
entre una Pi 4 por Wi-Fi y un computador; Ethernet y otras placas requieren
pruebas físicas.
