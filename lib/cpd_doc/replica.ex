defmodule CpdDoc.Replica do
  use GenServer

  alias CpdDoc.Causal
  alias CpdDoc.Historial
  alias CpdDoc.Mensaje
  alias CpdDoc.Treedoc

  @max_espera 50_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: Mensaje.nombre())
  end

  def init(:ok) do
    case archivo() do
      nil ->
        IO.puts("réplica no iniciada: arranca el nodo con --name <nombre>@<ip> --cookie cpd2026")
        :ignore

      archivo ->
        arrancar(archivo)
    end
  end

  def handle_call({:local, _}, _de, %{bloqueado: true} = estado) do
    {:reply, {:error, :reiniciar_con_otro_nombre}, estado}
  end

  def handle_call({:local, _}, _de, %{error_disco: razon} = estado) when not is_nil(razon) do
    {:reply, {:error, {:disco, razon}}, estado}
  end

  def handle_call({:local, {:insertar, i, texto}}, _de, estado) when is_binary(texto) do
    if String.valid?(texto) do
      insertar(i, String.graphemes(texto), estado)
    else
      {:reply, {:error, :texto_invalido}, estado}
    end
  end

  def handle_call({:local, {:borrar, i, n}}, _de, estado) do
    case Treedoc.preparar_borrado(estado.doc, i, n) do
      {:ok, posids} -> borrar(posids, estado)
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:local, _}, _de, estado) do
    {:reply, {:error, :argumentos_invalidos}, estado}
  end

  def handle_call(:texto, _de, estado) do
    {:reply, Treedoc.texto(estado.doc), estado}
  end

  def handle_call(:historial, _de, estado) do
    {:reply, Enum.reverse(estado.historial), estado}
  end

  def handle_call(:estado, _de, estado) do
    resumen = %{
      nodo: node(),
      autor: estado.yo,
      vecinos: Node.list(),
      reloj: estado.vc,
      en_espera: en_espera(estado),
      historial: estado.n_historial,
      caracteres: map_size(estado.doc.atomos),
      borrados: MapSet.size(estado.doc.borrados),
      recibidas: estado.recibidas,
      duplicadas: estado.duplicadas,
      ignoradas: estado.ignoradas,
      bloqueado: estado.bloqueado,
      error_disco: estado.error_disco,
      archivo: estado.archivo
    }

    {:reply, resumen, estado}
  end

  def handle_call(_otra, _de, estado) do
    {:reply, {:error, :desconocida}, estado}
  end

  def handle_cast({:remote, _crudo}, %{error_disco: razon} = estado) when not is_nil(razon) do
    {:noreply, estado}
  end

  def handle_cast({:remote, crudo}, estado) do
    case Mensaje.leer(crudo) do
      {:ok, op} -> {:noreply, remota(op, estado)}
      :error -> {:noreply, %{estado | ignoradas: estado.ignoradas + 1}}
    end
  end

  def handle_cast({:hello, nodo}, estado) when is_atom(nodo) do
    enviar_historial(estado)
    {:noreply, estado}
  end

  def handle_cast(_otro, estado) do
    {:noreply, %{estado | ignoradas: estado.ignoradas + 1}}
  end

  def handle_info({:nodeup, _nodo}, estado) do
    enviar_historial(estado)
    {:noreply, recordar_nombre(estado)}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp arrancar(archivo) do
    with {:ok, fd} <- Historial.abrir(archivo),
         {:ok, ops, fd, bloqueado} <- cargar(archivo, fd) do
      :net_kernel.monitor_nodes(true)

      estado = %{
        doc: reconstruir(ops),
        vc: reloj(ops),
        espera: [],
        historial: Enum.reverse(ops),
        n_historial: length(ops),
        fd: fd,
        archivo: archivo,
        yo: nombre_actual(),
        bloqueado: bloqueado,
        error_disco: nil,
        recibidas: 0,
        duplicadas: 0,
        ignoradas: 0
      }

      if Node.list() != [] do
        enviar_historial(estado)
        difundir({:hello, node()})
      end

      {:ok, estado}
    else
      {:error, razon} ->
        IO.puts("réplica no iniciada: no se pudo abrir #{archivo} (#{inspect(razon)})")
        :ignore
    end
  end

  defp cargar(archivo, fd) do
    case Historial.cargar(archivo) do
      {:ok, ops} -> {:ok, ops, fd, false}
      {:corrupto, prefijo, linea} -> recuperar(archivo, fd, prefijo, linea)
      {:error, razon} -> {:error, razon}
    end
  end

  defp recuperar(archivo, fd, prefijo, linea) do
    :file.close(fd)

    case Historial.apartar(archivo, prefijo) do
      {:ok, fd} ->
        olvidar_epoca()
        bloqueado = Node.alive?()
        avisar_corrupto(linea, length(prefijo), bloqueado)
        {:ok, prefijo, fd, bloqueado}

      {:error, razon} ->
        {:error, razon}
    end
  end

  defp olvidar_epoca() do
    case Application.get_env(:documento_distribuido, :epoca) do
      nil -> :ok
      epoca -> File.rm(epoca)
    end
  end

  defp avisar_corrupto(linea, n, bloqueado) do
    IO.puts("historial dañado en la línea #{linea}: se conservan #{n} operaciones")

    if bloqueado do
      IO.puts("reinicia el nodo con otro nombre para volver a editar")
    end
  end

  defp reconstruir(ops) do
    Enum.reduce(ops, Treedoc.nuevo(), fn op, doc -> Treedoc.aplicar(doc, op) end)
  end

  defp reloj(ops) do
    Enum.reduce(ops, %{}, fn op, vc -> Causal.entregar(vc, op) end)
  end

  defp recordar_nombre(estado) do
    if Node.alive?() do
      %{estado | yo: node()}
    else
      estado
    end
  end

  defp nombre_actual() do
    if Node.alive?() do
      node()
    else
      nil
    end
  end

  defp en_espera(estado) do
    Enum.map(estado.espera, fn op ->
      {op.from, op.vc[op.from], Causal.faltan(estado.vc, op)}
    end)
  end

  defp insertar(i, caracteres, estado) do
    case autor(estado, caracteres) do
      {:ok, yo, estado} -> insertar(i, caracteres, yo, estado)
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp insertar(i, caracteres, yo, estado) do
    seq0 = Map.get(estado.vc, yo, 0)

    case Treedoc.preparar_insercion(estado.doc, i, caracteres, seq0, yo) do
      {:ok, posids} -> locales(inserciones(posids, seq0 + 1, yo, estado.vc), estado)
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp borrar(posids, estado) do
    case autor(estado, posids) do
      {:ok, yo, estado} ->
        locales(borrados(posids, Map.get(estado.vc, yo, 0) + 1, yo, estado.vc), estado)

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  defp inserciones([], _seq, _yo, _vc) do
    []
  end

  defp inserciones([{posid, caracter} | resto], seq, yo, vc) do
    op = %{op: :ins, from: yo, vc: Map.put(vc, yo, seq), pos: posid, ch: caracter}
    [op | inserciones(resto, seq + 1, yo, vc)]
  end

  defp borrados([], _seq, _yo, _vc) do
    []
  end

  defp borrados([posid | resto], seq, yo, vc) do
    op = %{op: :del, from: yo, vc: Map.put(vc, yo, seq), pos: posid}
    [op | borrados(resto, seq + 1, yo, vc)]
  end

  defp autor(estado, []) do
    {:ok, nil, estado}
  end

  defp autor(estado, _) do
    cond do
      Node.alive?() -> {:ok, node(), %{estado | yo: node()}}
      estado.yo != nil -> {:ok, estado.yo, estado}
      true -> {:error, :sin_red}
    end
  end

  defp locales([], estado) do
    {:reply, :ok, estado}
  end

  defp locales(ops, estado) do
    if Enum.all?(ops, fn op -> Mensaje.leer(op) != :error end) do
      guardar(ops, estado)
    else
      {:reply, {:error, :operacion_invalida}, estado}
    end
  end

  defp guardar(ops, estado) do
    case Historial.agregar(estado.fd, ops) do
      :ok ->
        estado = aplicar(ops, estado)

        for op <- ops do
          difundir({:remote, op})
        end

        {:reply, :ok, anotar(estado, ops)}

      {:error, razon} ->
        {:reply, {:error, {:disco, razon}}, %{estado | error_disco: razon}}
    end
  end

  defp aplicar(ops, estado) do
    Enum.reduce(ops, estado, fn op, e ->
      %{e | doc: Treedoc.aplicar(e.doc, op), vc: Causal.entregar(e.vc, op)}
    end)
  end

  defp remota(op, estado) do
    {vc, espera, aplicadas, resultado} = Causal.recibir(estado.vc, estado.espera, op)

    case Historial.agregar(estado.fd, aplicadas) do
      :ok ->
        estado = contar(%{estado | vc: vc, espera: recortar(espera)}, resultado)
        aplicar_remotas(aplicadas, estado)

      {:error, razon} ->
        IO.puts("no se pudo guardar en #{estado.archivo}: #{inspect(razon)}")
        %{estado | error_disco: razon}
    end
  end

  defp contar(estado, :duplicada) do
    %{estado | duplicadas: estado.duplicadas + 1}
  end

  defp contar(estado, _resultado) do
    estado
  end

  defp recortar(espera) do
    if length(espera) > @max_espera do
      Enum.drop(espera, length(espera) - @max_espera)
    else
      espera
    end
  end

  defp aplicar_remotas([], estado) do
    estado
  end

  defp aplicar_remotas(ops, estado) do
    doc = Enum.reduce(ops, estado.doc, fn op, doc -> Treedoc.aplicar(doc, op) end)

    for op <- ops do
      difundir({:remote, op})
    end

    anotar(%{estado | doc: doc, recibidas: estado.recibidas + length(ops)}, ops)
  end

  defp anotar(estado, ops) do
    %{
      estado
      | historial: Enum.reverse(ops, estado.historial),
        n_historial: estado.n_historial + length(ops)
    }
  end

  defp enviar_historial(estado) do
    for op <- Enum.reverse(estado.historial) do
      difundir({:remote, op})
    end

    :ok
  end

  defp difundir(mensaje) do
    for n <- Node.list() do
      GenServer.cast({Mensaje.nombre(), n}, mensaje)
    end

    :ok
  end

  defp archivo() do
    case Application.get_env(:documento_distribuido, :historial) do
      nil -> archivo_por_nombre()
      ruta -> ruta
    end
  end

  defp archivo_por_nombre() do
    if Node.alive?() do
      [nombre, _] = String.split(Atom.to_string(node()), "@")
      Path.join(Application.get_env(:documento_distribuido, :datos, "datos"), nombre <> ".log")
    else
      nil
    end
  end
end
