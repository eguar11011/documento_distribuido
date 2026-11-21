defmodule DocumentoDistribuido.Treedoc.Operation do
  @moduledoc """
  Operaciones de inserción y eliminación sobre identificadores ya asignados.

  La asignación de PosID y el protocolo para transmitir operaciones están pendientes.
  """

  alias DocumentoDistribuido.Treedoc.PosID

  defmodule Insert do
    @moduledoc "Inserta un átomo de texto en un PosID único."
    @enforce_keys [:position, :value]
    defstruct [:position, :value]

    @type t :: %__MODULE__{position: PosID.t(), value: String.t()}
  end

  defmodule Delete do
    @moduledoc "Elimina el átomo identificado por un PosID."
    @enforce_keys [:position]
    defstruct [:position]

    @type t :: %__MODULE__{position: PosID.t()}
  end

  @type t :: Insert.t() | Delete.t()
end
