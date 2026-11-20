defmodule DocumentoDistribuido.Treedoc.PosID do
  @moduledoc """
  Identificador de una posición del árbol Treedoc.

  Los componentes son provisionales: todavía hay que definir su representación,
  generación y comparación, incluyendo el desempate de inserciones concurrentes.
  """

  @enforce_keys [:components]
  defstruct [:components]

  @type t :: %__MODULE__{components: [term()]}
end
