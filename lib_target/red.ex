defmodule CpdDoc.Red do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    for interface <- ["eth0", "wlan0"] do
      VintageNet.subscribe(["interface", interface, "addresses"])
    end

    send(self(), :revisar)
    {:ok, %{ip: nil}}
  end

  def handle_info(:revisar, estado) do
    {:noreply, revisar(estado)}
  end

  def handle_info({VintageNet, _propiedad, _viejo, _nuevo, _meta}, estado) do
    {:noreply, revisar(estado)}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp revisar(estado) do
    ethernet = VintageNet.get(["interface", "eth0", "addresses"], [])
    wifi = VintageNet.get(["interface", "wlan0", "addresses"], [])
    actualizar(CpdDoc.Interfaz.ipv4(ethernet, wifi), estado)
  end

  defp actualizar(ip, estado) do
    if ip == estado.ip and Node.alive?() do
      estado
    else
      detener_nodo()
      arrancar_nodo(ip)
    end
  end

  defp detener_nodo() do
    if Node.alive?() do
      IO.puts("deteniendo nodo #{inspect(Node.self())}")
      Node.stop()
    end
  end

  defp arrancar_nodo(nil) do
    IO.puts("eth0 y wlan0 sin IPv4, esperando")
    %{ip: nil}
  end

  defp arrancar_nodo(ip) do
    System.cmd("epmd", ["-daemon"])
    nombre = String.to_atom("#{host()}-#{epoca()}@#{ip}")

    case Node.start(nombre, name_domain: :longnames) do
      {:ok, _} ->
        Node.set_cookie(:cpd2026)
        IO.puts("nodo arrancado: #{inspect(Node.self())}")
        %{ip: ip}

      {:error, razon} ->
        IO.puts("no se pudo arrancar #{inspect(nombre)}: #{inspect(razon)}, reintento en 5 s")
        Process.send_after(self(), :revisar, 5000)
        %{ip: nil}
    end
  end

  defp host() do
    {:ok, h} = :inet.gethostname()
    String.replace(to_string(h), ~r/[^A-Za-z0-9_-]/, "-")
  end

  defp epoca() do
    archivo = Application.fetch_env!(:documento_distribuido, :epoca)

    case File.read(archivo) do
      {:ok, e} -> revisar_epoca(e, archivo)
      {:error, _} -> nueva_epoca(archivo)
    end
  end

  defp revisar_epoca(e, archivo) do
    if Regex.match?(~r/\A[0-9a-f]{6}\z/, e) do
      e
    else
      nueva_epoca(archivo)
    end
  end

  defp nueva_epoca(archivo) do
    e = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
    File.mkdir_p(Path.dirname(archivo))

    case File.write(archivo, e, [:sync]) do
      :ok -> :ok
      {:error, razon} -> IO.puts("no se pudo guardar la época en #{archivo}: #{inspect(razon)}")
    end

    e
  end
end
