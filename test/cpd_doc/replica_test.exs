defmodule CpdDoc.ReplicaTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CpdDoc.Historial

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    archivo = Path.join(dir, "r.log")
    Application.put_env(:documento_distribuido, :historial, archivo)
    on_exit(fn -> Application.delete_env(:documento_distribuido, :historial) end)
    %{archivo: archivo}
  end

  defp op(seq, ch) do
    %{op: :ins, from: :x, vc: %{x: seq}, pos: [{1, seq, :x}], ch: ch}
  end

  test "sin red se lee pero no se edita, y ninguna entrada inválida la tumba" do
    pid = start_supervised!(CpdDoc.Replica)

    assert CpdDoc.insertar(0, "x") == {:error, :sin_red}
    assert CpdDoc.texto() == ""
    assert CpdDoc.borrar(0) == {:error, :posicion_invalida}
    assert CpdDoc.borrar(-1, 2) == {:error, :posicion_invalida}
    assert CpdDoc.borrar("0", 1) == {:error, :posicion_invalida}
    assert CpdDoc.insertar(0, 5) == {:error, :argumentos_invalidos}
    assert CpdDoc.insertar(0, <<255>>) == {:error, :texto_invalido}
    assert CpdDoc.insertar(0, "") == :ok
    assert GenServer.call(Crdt.Replica, :lo_que_sea) == {:error, :desconocida}
    assert GenServer.call(Crdt.Replica, {:local, :raro}) == {:error, :argumentos_invalidos}
    assert CpdDoc.conectar(123) == {:error, :nodo_invalido}

    for _ <- 1..3_000 do
      m = CpdDoc.Azar.mensaje()
      GenServer.cast(Crdt.Replica, m)
      send(Crdt.Replica, m)
    end

    assert CpdDoc.texto() == ""
    assert Process.whereis(Crdt.Replica) == pid
    assert CpdDoc.estado().ignoradas > 0
  end

  test "aplica lo que llega en orden causal aunque llegue desordenado" do
    start_supervised!(CpdDoc.Replica)

    GenServer.cast(Crdt.Replica, {:remote, op(2, "o")})
    assert CpdDoc.texto() == ""
    assert [{:x, 2, %{x: 1}}] = CpdDoc.estado().en_espera

    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    assert CpdDoc.texto() == "ho"
    assert CpdDoc.estado().en_espera == []
    assert CpdDoc.estado().duplicadas == 1
  end

  test "al reiniciar reconstruye texto y reloj desde el log" do
    start_supervised!(CpdDoc.Replica)
    GenServer.cast(Crdt.Replica, {:remote, op(1, "h")})
    GenServer.cast(Crdt.Replica, {:remote, op(2, "i")})
    assert CpdDoc.texto() == "hi"

    stop_supervised!(CpdDoc.Replica)
    start_supervised!(CpdDoc.Replica)

    assert CpdDoc.texto() == "hi"
    assert CpdDoc.estado().reloj == %{x: 2}
    assert length(CpdDoc.historial()) == 2
  end

  test "si falla el disco no confirma ni reenvía operaciones remotas" do
    start_supervised!(CpdDoc.Replica)

    :sys.replace_state(Crdt.Replica, fn estado ->
      :ok = :file.close(estado.fd)
      estado
    end)

    GenServer.cast(Crdt.Replica, {:remote, op(1, "x")})
    assert CpdDoc.texto() == ""
    assert CpdDoc.estado().reloj == %{}
    assert CpdDoc.estado().error_disco != nil
    assert {:error, {:disco, _}} = CpdDoc.insertar(0, "y")
  end

  test "con el log dañado en medio arranca con el prefijo válido", %{archivo: archivo} do
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1, "h")])
    File.write!(archivo, "basura\n", [:append])
    :ok = Historial.agregar(fd, [op(2, "i")])

    salida = capture_io(fn -> start_supervised!(CpdDoc.Replica) end)

    assert salida =~ "historial dañado en la línea 2"
    assert CpdDoc.texto() == "h"
    assert CpdDoc.estado().bloqueado == false
    assert [_] = Path.wildcard(archivo <> ".danado-*")
  end

  test "si no puede abrir el log no arranca y las llamadas responden sin_replica" do
    Application.put_env(:documento_distribuido, :historial, "/dev/null/no/se/puede/r.log")

    salida = capture_io(fn -> start_supervised(CpdDoc.Replica) end)

    assert salida =~ "réplica no iniciada"
    assert Process.whereis(Crdt.Replica) == nil
    assert CpdDoc.texto() == {:error, :sin_replica}
    assert CpdDoc.insertar(0, "x") == {:error, :sin_replica}
  end
end
