defmodule DocumentoDistribuido.TreedocTest do
  use ExUnit.Case, async: true

  alias DocumentoDistribuido.Treedoc
  alias DocumentoDistribuido.Treedoc.Operation.{Delete, Insert}
  alias DocumentoDistribuido.Treedoc.PosID

  test "crea el esqueleto de un documento vacío" do
    assert %Treedoc{} = Treedoc.new()
  end

  test "una inserción conserva su posición y contenido" do
    position = %PosID{components: [:ejemplo]}
    insert = %Insert{position: position, value: "a"}

    assert insert.position == position
    assert insert.value == "a"
  end

  test "una eliminación identifica la posición que se eliminará" do
    position = %PosID{components: [:ejemplo]}
    assert %Delete{position: ^position} = %Delete{position: position}
  end
end
