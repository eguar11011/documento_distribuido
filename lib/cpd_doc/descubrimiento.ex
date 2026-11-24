defmodule CpdDoc.Descubrimiento do
  use GenServer

  @grupo {233, 252, 1, 32}
  @puerto 45_892
  @etiqueta "crdt-treedoc-1 "
  @anunciar_cada 2_000
  @barrer_cada 10_000
  @reintentar 30_000
  @max_nombres 256
  @nombre ~r/\A[A-Za-z0-9_\-.]{1,64}@\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def paquete(nodo) do
    @etiqueta <> Atom.to_string(nodo)
  end

  def leer_paquete(datos) do
    case leer_nombre(datos) do
      {:ok, nombre} -> {:ok, String.to_atom(nombre)}
      :error -> :error
    end
  end

  def leer_nombre(<<@etiqueta, nombre::binary>>) do
    if Regex.match?(@nombre, nombre) do
      {:ok, nombre}
    else
      :error
    end
  end

  def leer_nombre(_) do
    :error
  end

  def vecinos(ip, prefijo) do
    [a, b, c, d] = Enum.map(String.split(ip, "."), fn x -> String.to_integer(x) end)
    tamano = Integer.pow(2, 32 - max(prefijo, 24))
    base = d - rem(d, tamano)

    if tamano < 4 do
      []
    else
      for x <- (base + 1)..(base + tamano - 2), x != d do
        Enum.join([a, b, c, x], ".")
      end
    end
  end

  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    send(self(), :anunciar)
    Process.send_after(self(), :barrer, 1_000)
    {:ok, %{socket: nil, ip: nil, fallidos: %{}, barriendo: nil, nombres: MapSet.new()}}
  end

  def handle_info(:anunciar, estado) do
    Process.send_after(self(), :anunciar, @anunciar_cada)
    estado = abrir_socket(estado, ip_propia())

    if estado.socket != nil do
      :gen_udp.send(estado.socket, @grupo, @puerto, paquete(node()))
    end

    {:noreply, estado}
  end

  def handle_info({:udp, _socket, _ip, _puerto, datos}, estado) do
    case leer_nombre(datos) do
      {:ok, nombre} -> {:noreply, anunciado(nombre, estado)}
      :error -> {:noreply, estado}
    end
  end

  def handle_info({:intento, nodo, true}, estado) do
    {:noreply, %{estado | fallidos: Map.delete(estado.fallidos, nodo)}}
  end

  def handle_info(:barrer, estado) do
    Process.send_after(self(), :barrer, @barrer_cada)
    ip = ip_propia()

    if ip != nil and estado.barriendo == nil and
         Application.get_env(:documento_distribuido, :barrido, true) do
      {:noreply, %{estado | barriendo: Task.async(fn -> barrer(ip) end)}}
    else
      {:noreply, estado}
    end
  end

  def handle_info({ref, _resultado}, %{barriendo: %Task{ref: ref}} = estado) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{estado | barriendo: nil}}
  end

  def handle_info({:nodeup, nodo}, estado) do
    IO.puts("se conectó #{inspect(nodo)}")
    {:noreply, estado}
  end

  def handle_info({:nodedown, nodo}, estado) do
    IO.puts("se desconectó #{inspect(nodo)}")
    {:noreply, estado}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp anunciado(nombre, estado) do
    cond do
      MapSet.member?(estado.nombres, nombre) ->
        intentar(String.to_atom(nombre), estado)

      MapSet.size(estado.nombres) < @max_nombres ->
        intentar(String.to_atom(nombre), %{estado | nombres: MapSet.put(estado.nombres, nombre)})

      true ->
        estado
    end
  end

  defp intentar(nodo, estado) do
    ahora = System.monotonic_time(:millisecond)

    if nuevo?(nodo) and Map.get(estado.fallidos, nodo, ahora) <= ahora do
      yo = self()
      spawn(fn -> send(yo, {:intento, nodo, Node.connect(nodo)}) end)
      %{estado | fallidos: Map.put(estado.fallidos, nodo, ahora + @reintentar)}
    else
      estado
    end
  end

  defp nuevo?(nodo) do
    nodo != node() and nodo not in Node.list()
  end

  defp abrir_socket(%{ip: ip} = estado, ip) do
    estado
  end

  defp abrir_socket(estado, ip) do
    if estado.socket != nil do
      :gen_udp.close(estado.socket)
    end

    %{estado | socket: abrir_udp(ip), ip: ip}
  end

  defp abrir_udp(nil) do
    nil
  end

  defp abrir_udp(ip) do
    opciones = [
      :binary,
      active: true,
      reuseaddr: true,
      multicast_ttl: 1,
      multicast_loop: true,
      multicast_if: ip
    ]

    case :gen_udp.open(@puerto, opciones ++ [add_membership: {@grupo, ip}]) do
      {:ok, socket} -> socket
      {:error, _} -> solo_anunciar(opciones)
    end
  end

  defp solo_anunciar(opciones) do
    case :gen_udp.open(0, opciones) do
      {:ok, socket} -> socket
      {:error, _} -> nil
    end
  end

  defp barrer(ip) do
    vecinos = vecinos(Enum.join(Tuple.to_list(ip), "."), prefijo(ip))

    intentos =
      Task.async_stream(vecinos, fn vecino -> conectar_en(vecino) end,
        max_concurrency: 64,
        timeout: 5_000,
        on_timeout: :kill_task
      )

    Stream.run(intentos)
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp conectar_en(vecino) do
    for nodo <- nodos_en(vecino) do
      if nuevo?(nodo) do
        Node.connect(nodo)
      end
    end
  end

  defp nodos_en(vecino) do
    {:ok, ip} = :inet.parse_ipv4_address(String.to_charlist(vecino))
    tarea = Task.async(fn -> :erl_epmd.names(ip) end)

    case Task.yield(tarea, 3_000) do
      {:ok, {:ok, nombres}} ->
        nombres_validos(nombres, vecino)

      nil ->
        Task.shutdown(tarea, :brutal_kill)
        []

      _ ->
        []
    end
  end

  defp nombres_validos(nombres, vecino) do
    for {nombre, _puerto} <- nombres, Regex.match?(@nombre, "#{nombre}@#{vecino}") do
      String.to_atom("#{nombre}@#{vecino}")
    end
  end

  defp ip_propia() do
    if Node.alive?() do
      [_, host] = String.split(Atom.to_string(node()), "@")
      ipv4(:inet.parse_ipv4_address(String.to_charlist(host)))
    else
      nil
    end
  end

  defp ipv4({:ok, {127, 0, 0, 1}}) do
    nil
  end

  defp ipv4({:ok, ip}) do
    ip
  end

  defp ipv4({:error, _}) do
    nil
  end

  defp prefijo(ip) do
    case :inet.getifaddrs() do
      {:ok, interfaces} -> bits(mascara(interfaces, ip))
      {:error, _} -> 24
    end
  end

  defp mascara(interfaces, ip) do
    Enum.find_value(interfaces, fn {_nombre, opciones} ->
      if {:addr, ip} in opciones do
        Keyword.get(opciones, :netmask)
      end
    end)
  end

  defp bits(nil) do
    24
  end

  defp bits(mascara) do
    Enum.sum(Enum.map(Tuple.to_list(mascara), fn byte -> unos(byte) end))
  end

  defp unos(0) do
    0
  end

  defp unos(byte) do
    rem(byte, 2) + unos(div(byte, 2))
  end
end
