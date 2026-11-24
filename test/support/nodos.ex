defmodule CpdDoc.Nodos do
  def iniciar(nombre, dir) do
    rutas = Enum.flat_map(:code.get_path(), fn ruta -> [~c"-pa", ruta] end)
    args = rutas ++ [~c"-connect_all", ~c"false", ~c"-setcookie", ~c"cpd2026"]

    {:ok, pid, nodo} =
      :peer.start(%{
        name: nombre,
        host: ~c"127.0.0.1",
        longnames: true,
        args: args,
        connection: :standard_io
      })

    :ok = llamar(pid, __MODULE__, :arrancar, [Path.join(dir, "#{nombre}.log")])
    {pid, nodo}
  end

  def iniciar_sin_nombre(etiqueta, dir) do
    rutas = Enum.flat_map(:code.get_path(), fn ruta -> [~c"-pa", ruta] end)
    args = rutas ++ [~c"-connect_all", ~c"false"]
    {:ok, pid, _sin_nombre} = :peer.start(%{args: args, connection: :standard_io})
    :ok = llamar(pid, __MODULE__, :arrancar, [Path.join(dir, "#{etiqueta}.log")])
    pid
  end

  def distribuir(nombre) do
    System.cmd("epmd", ["-daemon"])
    {:ok, _} = Node.start(nombre, name_domain: :longnames)
    Node.set_cookie(:cpd2026)
    :ok
  end

  def editar_al_azar(n) do
    for _ <- 1..n do
      Process.sleep(:rand.uniform(15))
      largo = String.length(CpdDoc.texto())

      if largo > 0 and :rand.uniform(3) == 1 do
        CpdDoc.borrar(:rand.uniform(largo) - 1, 1)
      else
        CpdDoc.insertar(:rand.uniform(largo + 1) - 1, Enum.random(["a", "bc", "ñ", "👍🏽"]))
      end
    end

    :ok
  end

  def arrancar(archivo) do
    Application.load(:documento_distribuido)
    Application.put_env(:documento_distribuido, :historial, archivo)
    hijos = [CpdDoc.Replica]
    {:ok, sup} = Supervisor.start_link(hijos, strategy: :one_for_one, name: CpdDoc.Supervisor)
    Process.unlink(sup)
    :ok
  end

  def llamar(pid, m, f) do
    llamar(pid, m, f, [])
  end

  def llamar(pid, m, f, a) do
    :peer.call(pid, m, f, a, 30_000)
  end

  def eventualmente(f) do
    eventualmente(f, 100)
  end

  def eventualmente(f, 0) do
    f.()
  end

  def eventualmente(f, intentos) do
    if f.() do
      true
    else
      Process.sleep(100)
      eventualmente(f, intentos - 1)
    end
  end
end
