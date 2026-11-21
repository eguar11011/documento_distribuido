defmodule DocumentoDistribuido.TreedocTest do
  use ExUnit.Case, async: true

  alias DocumentoDistribuido.Treedoc
  alias DocumentoDistribuido.Treedoc.Operation.{Delete, Insert}
  alias DocumentoDistribuido.Treedoc.PosID

  defp pos(components) do
    {:ok, position} = PosID.new(components)
    position
  end

  defp apply_operations(operations) do
    Enum.reduce(operations, Treedoc.new(), fn operation, doc ->
      {:ok, doc} = Treedoc.apply(doc, operation)
      doc
    end)
  end

  test "el documento nuevo está vacío" do
    doc = Treedoc.new()
    assert Treedoc.visible(doc) == []
    assert Treedoc.text(doc) == ""
  end

  test "ordena ramas mayores, mininodos y descendientes como en el recorrido infijo" do
    c = pos([{:root, {1, "c"}}])
    d = pos([:right, {:left, {1, "d"}}])
    w = pos([:right, :left, {:left, {1, "w"}}])
    y = pos([:right, :left, {:left, {1, "y"}}])
    x = pos([:right, :left, {:left, {1, "w"}}, {:right, {1, "x"}}])
    z = pos([:right, :left, :left, {:right, {1, "z"}}])

    operations =
      Enum.map([{d, "d"}, {z, "z"}, {y, "y"}, {c, "c"}, {x, "x"}, {w, "w"}], fn {p, value} ->
        %Insert{position: p, value: value}
      end)

    assert Treedoc.text(apply_operations(operations)) == "cwxyzd"
  end

  test "orden infijo coloca descendientes izquierdos antes y derechos después" do
    parent = pos([{:root, {1, "a"}}])
    left = pos([{:root, {1, "a"}}, {:left, {1, "b"}}])
    right = pos([{:root, {1, "a"}}, {:right, {1, "c"}}])

    assert PosID.compare(left, parent) == :lt
    assert PosID.compare(parent, left) == :gt
    assert PosID.compare(parent, right) == :lt
    assert PosID.compare(right, parent) == :gt
    assert PosID.compare(parent, parent) == :eq
  end

  test "desambiguadores UDIS se ordenan por contador y luego réplica" do
    a = pos([{:root, {1, "a"}}])
    b = pos([{:root, {1, "b"}}])
    next = pos([{:root, {2, "a"}}])

    assert PosID.compare(a, b) == :lt
    assert PosID.compare(b, next) == :lt
    assert PosID.compare(next, a) == :gt
  end

  test "la comparación mantiene antisimetría y transitividad en caminos variados" do
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

    for a <- positions, b <- positions do
      assert PosID.compare(a, b) == reverse(PosID.compare(b, a))

      for c <- positions,
          PosID.compare(a, b) == :lt,
          PosID.compare(b, c) == :lt do
        assert PosID.compare(a, c) == :lt
      end
    end
  end

  defp reverse(:lt), do: :gt
  defp reverse(:gt), do: :lt
  defp reverse(:eq), do: :eq

  test "inserciones concurrentes convergen en cualquier orden" do
    a = %Insert{position: pos([{:root, {1, "a"}}]), value: "A"}
    b = %Insert{position: pos([{:root, {1, "b"}}]), value: "B"}
    c = %Insert{position: pos([{:root, {1, "c"}}]), value: "C"}

    permutations =
      for x <- [a, b, c],
          y <- [a, b, c],
          z <- [a, b, c],
          x != y and y != z and x != z,
          do: [x, y, z]

    documents = Enum.map(permutations, &apply_operations/1)

    assert length(permutations) == 6
    assert Enum.all?(documents, &(Treedoc.text(&1) == "ABC"))
    assert Enum.uniq(documents) |> length() == 1
  end

  test "duplicados y borrado anterior a inserción no resucitan contenido" do
    position = pos([{:root, {1, "a"}}])
    insert = %Insert{position: position, value: "a"}
    delete = %Delete{position: position}
    first = apply_operations([insert, insert, delete, delete])
    second = apply_operations([delete, delete, insert, insert])

    assert first == second
    assert Treedoc.text(first) == ""
  end

  test "el borrado de un átomo conserva sus descendientes visibles" do
    parent = pos([{:root, {1, "a"}}])
    child = pos([{:root, {1, "a"}}, {:right, {1, "b"}}])

    doc =
      apply_operations([
        %Insert{position: parent, value: "a"},
        %Insert{position: child, value: "b"},
        %Delete{position: parent}
      ])

    assert Treedoc.visible(doc) == [{child, "b"}]
  end

  test "rechaza posiciones inválidas y dos valores diferentes para el mismo identificador" do
    for components <- [
          [],
          [:left],
          [{:root, {-1, "a"}}],
          [{:root, {0, ""}}],
          [:left, {:root, {1, "a"}}]
        ] do
      assert {:error, :invalid_position} = PosID.new(components)
    end

    invalid = %PosID{components: [:invalid]}
    assert {:error, :invalid_operation} = Treedoc.apply(Treedoc.new(), %Delete{position: invalid})
    position = pos([{:root, {1, "a"}}])
    {:ok, doc} = Treedoc.apply(Treedoc.new(), %Insert{position: position, value: "a"})

    assert {:error, :position_conflict} =
             Treedoc.apply(doc, %Insert{position: position, value: "b"})
  end
end
