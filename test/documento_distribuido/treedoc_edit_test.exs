defmodule DocumentoDistribuido.TreedocEditTest do
  use ExUnit.Case, async: true

  alias DocumentoDistribuido.Treedoc
  alias DocumentoDistribuido.Treedoc.Operation.{Delete, Insert}
  alias DocumentoDistribuido.Treedoc.PosID

  defp pos(components) do
    {:ok, position} = PosID.new(components)
    position
  end

  test "genera posiciones con extremos abiertos y entre caminos variados" do
    positions = [
      pos([{:root, {1, "a"}}]),
      pos([{:root, {1, "b"}}]),
      pos([:left, {:left, {1, "a"}}]),
      pos([{:left, {1, "a"}}]),
      pos([:left, {:right, {1, "a"}}]),
      pos([{:root, {1, "a"}}, {:left, {1, "c"}}]),
      pos([{:root, {1, "a"}}, {:right, {1, "c"}}]),
      pos([{:right, {1, "a"}}]),
      pos([:right, {:left, {1, "a"}}])
    ]

    assert {:ok, empty} = PosID.between(nil, nil, {20, "nueva"})
    assert PosID.valid?(empty)

    for position <- positions do
      {:ok, before} = PosID.between(nil, position, {20, "nueva"})
      {:ok, after_position} = PosID.between(position, nil, {20, "nueva"})
      assert PosID.compare(before, position) == :lt
      assert PosID.compare(position, after_position) == :lt
    end

    for left <- positions, right <- positions, PosID.compare(left, right) == :lt do
      assert {:ok, between} = PosID.between(left, right, {20, "nueva"})
      assert PosID.compare(left, between) == :lt
      assert PosID.compare(between, right) == :lt
    end
  end

  test "rechaza extremos iguales, invertidos o inválidos y desambiguadores inválidos" do
    a = pos([{:root, {1, "a"}}])
    b = pos([{:root, {1, "b"}}])
    assert {:error, :invalid_bounds} = PosID.between(a, a, {2, "a"})
    assert {:error, :invalid_bounds} = PosID.between(b, a, {2, "a"})
    assert {:error, :invalid_position} = PosID.between(:bad, nil, {2, "a"})
    assert {:error, :invalid_disambiguator} = PosID.between(nil, nil, {-1, "a"})
    assert {:error, :invalid_disambiguator} = PosID.between(nil, nil, {1, ""})
  end

  test "inserta y borra al inicio, en medio y al final por índice de átomo" do
    {:ok, doc, %Insert{}} = Treedoc.insert(Treedoc.new(), 0, "mundo", {1, "a"})
    {:ok, doc, %Insert{}} = Treedoc.insert(doc, 0, "¡", {2, "a"})
    {:ok, doc, %Insert{}} = Treedoc.insert(doc, 1, "hola ", {3, "a"})
    {:ok, doc, %Insert{}} = Treedoc.insert(doc, 3, "!", {4, "a"})
    assert Treedoc.text(doc) == "¡hola mundo!"

    {:ok, doc, %Delete{}} = Treedoc.delete(doc, 1)
    assert Treedoc.text(doc) == "¡mundo!"
    {:ok, doc, %Delete{}} = Treedoc.delete(doc, 0)
    {:ok, doc, %Delete{}} = Treedoc.delete(doc, 1)
    assert Treedoc.text(doc) == "mundo"
  end

  test "inserciones concurrentes en un hueco generan operaciones distintas y convergen" do
    {:ok, base, _} = Treedoc.insert(Treedoc.new(), 0, "L", {1, "base"})
    {:ok, base, _} = Treedoc.insert(base, 1, "R", {2, "base"})
    {:ok, first, operation_a} = Treedoc.insert(base, 1, "A", {1, "a"})
    {:ok, second, operation_b} = Treedoc.insert(base, 1, "B", {1, "b"})

    assert operation_a.position != operation_b.position
    assert {:ok, first} = Treedoc.apply(first, operation_b)
    assert {:ok, second} = Treedoc.apply(second, operation_a)
    assert first == second
    assert Treedoc.text(first) == "LABR"
  end

  test "puede insertar entre dos mininodos concurrentes ya integrados" do
    {:ok, _a, insert_a} = Treedoc.insert(Treedoc.new(), 0, "A", {1, "a"})
    {:ok, _b, insert_b} = Treedoc.insert(Treedoc.new(), 0, "B", {1, "b"})
    {:ok, doc} = Treedoc.apply(Treedoc.new(), insert_b)
    {:ok, doc} = Treedoc.apply(doc, insert_a)
    {:ok, doc, insert_middle} = Treedoc.insert(doc, 1, "X", {1, "c"})

    assert Treedoc.text(doc) == "AXB"
    assert PosID.compare(insert_a.position, insert_middle.position) == :lt
    assert PosID.compare(insert_middle.position, insert_b.position) == :lt
  end

  test "el borrado concurrente con inserción y los mensajes repetidos convergen" do
    {:ok, base, _} = Treedoc.insert(Treedoc.new(), 0, "a", {1, "base"})
    {:ok, deleting, delete} = Treedoc.delete(base, 0)
    {:ok, inserting, insert} = Treedoc.insert(base, 1, "b", {1, "other"})
    {:ok, deleting} = Treedoc.apply(deleting, insert)
    {:ok, deleting} = Treedoc.apply(deleting, insert)
    {:ok, inserting} = Treedoc.apply(inserting, delete)
    {:ok, inserting} = Treedoc.apply(inserting, delete)
    assert deleting == inserting
    assert Treedoc.text(deleting) == "b"
  end

  test "índices y desambiguadores reutilizados se rechazan incluso tras borrar" do
    doc = Treedoc.new()
    assert {:error, :invalid_index} = Treedoc.insert(doc, 1, "x", {1, "a"})
    assert {:error, :invalid_index} = Treedoc.insert(doc, -1, "x", {1, "a"})
    assert {:error, :invalid_index} = Treedoc.delete(doc, 0)
    assert {:error, :invalid_operation} = Treedoc.insert(doc, 0, nil, {1, "a"})
    assert {:error, :invalid_disambiguator} = Treedoc.insert(doc, 0, "x", {1, ""})
    {:ok, doc, _} = Treedoc.insert(doc, 0, "x", {1, "a"})
    {:ok, doc, _} = Treedoc.delete(doc, 0)
    assert {:error, :disambiguator_used} = Treedoc.insert(doc, 0, "y", {1, "a"})
    assert {:ok, _, _} = Treedoc.insert(doc, 0, "y", {2, "a"})
  end

  test "muchas ediciones en distintos índices coinciden con una secuencia de referencia" do
    {doc, expected} =
      Enum.reduce(1..100, {Treedoc.new(), []}, fn counter, {doc, expected} ->
        index = rem(counter * 37, length(expected) + 1)
        value = Integer.to_string(counter) <> ","
        {:ok, doc, _} = Treedoc.insert(doc, index, value, {counter, "a"})
        expected = List.insert_at(expected, index, value)
        assert Treedoc.text(doc) == Enum.join(expected)
        {doc, expected}
      end)

    {doc, expected} =
      Enum.reduce(1..50, {doc, expected}, fn counter, {doc, expected} ->
        index = rem(counter * 17, length(expected))
        {:ok, doc, _} = Treedoc.delete(doc, index)
        expected = List.delete_at(expected, index)
        assert Treedoc.text(doc) == Enum.join(expected)
        {doc, expected}
      end)

    assert length(Treedoc.visible(doc)) == length(expected)
  end
end
