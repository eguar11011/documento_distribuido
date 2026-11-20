defmodule DocumentoDistribuido.Treedoc.Operation do
  @moduledoc """
  Formas iniciales de las operaciones del documento.

  Estas estructuras no validan ni aplican operaciones. La identidad única de
  operación y la información causal necesaria se definirán junto al algoritmo.
  """

  alias DocumentoDistribuido.Treedoc.PosID

  defmodule Insert do
    @moduledoc "Inserción de contenido en una posición identificada."
    @enforce_keys [:position, :value]
    defstruct [:position, :value]

    @type t :: %__MODULE__{position: PosID.t(), value: String.t()}
  end

  defmodule Delete do
    @moduledoc "Eliminación del contenido de una posición identificada."
    @enforce_keys [:position]
    defstruct [:position]

    @type t :: %__MODULE__{position: PosID.t()}
  end

  @type t :: Insert.t() | Delete.t()
end
