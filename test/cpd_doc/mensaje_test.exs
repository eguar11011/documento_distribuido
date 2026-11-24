defmodule CpdDoc.MensajeTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Mensaje

  @ins %{
    op: :ins,
    from: :"crdt1@127.0.0.1",
    vc: %{"crdt1@127.0.0.1": 1},
    pos: [{1, 1, :"crdt1@127.0.0.1"}],
    ch: "h"
  }
  @del %{
    op: :del,
    from: :b@x,
    vc: %{"crdt1@127.0.0.1": 1, b@x: 1},
    pos: [{1, 1, :"crdt1@127.0.0.1"}]
  }

  test "acepta los ejemplos del contrato y descarta claves de más" do
    assert Mensaje.leer(@ins) == {:ok, @ins}
    assert Mensaje.leer(@del) == {:ok, @del}
    assert Mensaje.leer(Map.put(@ins, :extra, 1)) == {:ok, @ins}
    assert {:ok, _} = Mensaje.leer(%{@ins | ch: "é"})
    assert {:ok, _} = Mensaje.leer(%{@ins | ch: "👍🏽"})
  end

  test "rechaza cualquier otra forma" do
    malos = [
      %{},
      :basura,
      Map.delete(@ins, :ch),
      %{@ins | op: :otra},
      %{@ins | ch: "ab"},
      %{@ins | ch: ""},
      %{@ins | ch: <<255>>},
      %{@ins | ch: ~c"a"},
      %{@ins | from: "texto"},
      %{@ins | from: nil},
      %{@ins | vc: %{}},
      %{@ins | vc: %{"crdt1@127.0.0.1": 0}},
      %{@ins | vc: %{"crdt1@127.0.0.1": 1, otro: -1}},
      %{@ins | vc: [{:a, 1}]},
      %{@ins | pos: []},
      %{@ins | pos: [{2, 1, :a}]},
      %{@ins | pos: [{1, 0, :a}]},
      %{@ins | pos: [{1, 1, "a"}]},
      %{@ins | pos: [{1, 1, :a} | :impropia]},
      %{@ins | pos: [{1, 1}]}
    ]

    for m <- malos do
      assert Mensaje.leer(m) == :error, inspect(m)
    end
  end

  test "20 000 entradas al azar nunca lanzan error y lo aceptado vuelve a pasar la validación" do
    for _ <- 1..20_000 do
      entrada = CpdDoc.Azar.mensaje()

      case Mensaje.leer(entrada) do
        :error -> :ok
        {:ok, op} -> assert Mensaje.leer(op) == {:ok, op}
      end

      case entrada do
        {:remote, op} -> Mensaje.leer(op)
        _ -> :ok
      end
    end
  end

  test "un grafema de muchos bytes y un camino largo se aceptan, como en el contrato" do
    acentos = "e" <> String.duplicate("\u0301", 40)
    camino = for seq <- 1..20_000, do: {1, seq, :"crdt1@127.0.0.1"}

    assert byte_size(acentos) == 81
    assert {:ok, _} = Mensaje.leer(%{@ins | ch: acentos})
    assert {:ok, _} = Mensaje.leer(%{@ins | ch: "👨‍👩‍👧‍👦"})
    assert {:ok, _} = Mensaje.leer(%{@ins | pos: camino})
    assert {:ok, _} = Mensaje.leer(%{@del | pos: camino})
  end

  test "un carácter gigante se rechaza sin recorrerlo" do
    enorme = String.duplicate("a", 50_000_000)
    assert Mensaje.leer(%{@ins | ch: enorme}) == :error
  end
end
