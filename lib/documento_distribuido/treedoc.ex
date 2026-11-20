defmodule DocumentoDistribuido.Treedoc do
  @moduledoc """
  Núcleo puro previsto para el CRDT Treedoc.

  Por ahora el estado solo representa un documento recién creado. La asignación
  y el orden de posiciones, la aplicación de operaciones y las eliminaciones
  aún no están implementados.
  """

  defstruct []

  @type t :: %__MODULE__{}

  @doc "Crea el esqueleto de un documento vacío."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
