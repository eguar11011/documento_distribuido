defmodule CpdDoc.HistorialTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Historial

  @moduletag :tmp_dir

  defp op(seq) do
    %{op: :ins, from: :a, vc: %{a: seq}, pos: [{1, seq, :a}], ch: "x"}
  end

  test "lo escrito se carga en el mismo orden", %{tmp_dir: dir} do
    archivo = Path.join([dir, "sub", "a.log"])
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1), op(2)])
    :ok = Historial.agregar(fd, [op(3)])
    :ok = Historial.agregar(fd, [])

    assert Historial.cargar(archivo) == {:ok, [op(1), op(2), op(3)]}
    assert Historial.cargar(Path.join(dir, "no_existe.log")) == {:ok, []}
  end

  test "una última línea cortada se recorta al abrir", %{tmp_dir: dir} do
    archivo = Path.join(dir, "a.log")
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1), op(2)])
    File.write!(archivo, "AAAA", [:append])

    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(3)])
    assert Historial.cargar(archivo) == {:ok, [op(1), op(2), op(3)]}
  end

  test "una línea dañada en medio deja solo el prefijo, y apartar guarda el resto", %{
    tmp_dir: dir
  } do
    archivo = Path.join(dir, "a.log")
    {:ok, fd} = Historial.abrir(archivo)
    :ok = Historial.agregar(fd, [op(1)])
    File.write!(archivo, "esto-no-es-base64!\n", [:append])
    :ok = Historial.agregar(fd, [op(3)])

    assert Historial.cargar(archivo) == {:corrupto, [op(1)], 2}
    {:ok, _} = Historial.apartar(archivo, [op(1)])
    assert Historial.cargar(archivo) == {:ok, [op(1)]}
    assert [_] = Path.wildcard(archivo <> ".danado-*")
  end

  test "cortado en cada byte posible: nunca lanza error y conserva un prefijo válido", %{
    tmp_dir: dir
  } do
    original = Path.join(dir, "original.log")
    {:ok, fd} = Historial.abrir(original)
    ops = Enum.map(1..6, fn n -> op(n) end)
    :ok = Historial.agregar(fd, ops)
    datos = File.read!(original)

    for corte <- 0..byte_size(datos) do
      archivo = Path.join(dir, "corte_#{corte}.log")
      File.write!(archivo, binary_part(datos, 0, corte))
      {:ok, fd} = Historial.abrir(archivo)
      {:ok, cargadas} = Historial.cargar(archivo)

      assert cargadas == Enum.take(ops, length(cargadas))
      :ok = Historial.agregar(fd, [op(99)])
      assert Historial.cargar(archivo) == {:ok, cargadas ++ [op(99)]}
    end
  end

  test "bytes cambiados al azar: nunca lanza error y lo cargado es un prefijo", %{tmp_dir: dir} do
    original = Path.join(dir, "original.log")
    {:ok, fd} = Historial.abrir(original)
    ops = Enum.map(1..6, fn n -> op(n) end)
    :ok = Historial.agregar(fd, ops)
    datos = File.read!(original)

    for n <- 1..300 do
      archivo = Path.join(dir, "azar_#{n}.log")
      posicion = :rand.uniform(byte_size(datos)) - 1

      danado =
        binary_part(datos, 0, posicion) <>
          <<:rand.uniform(256) - 1>> <>
          binary_part(datos, posicion + 1, byte_size(datos) - posicion - 1)

      File.write!(archivo, danado)
      {:ok, _fd} = Historial.abrir(archivo)

      case Historial.cargar(archivo) do
        {:ok, cargadas} -> assert cargadas == Enum.take(ops, length(cargadas))
        {:corrupto, prefijo, _linea} -> assert prefijo == Enum.take(ops, length(prefijo))
      end
    end
  end

  test "sin permiso para crear la carpeta devuelve error, no lanza" do
    assert {:error, _} = Historial.abrir("/dev/null/no/se/puede/a.log")
  end
end
