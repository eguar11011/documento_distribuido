defmodule DocumentoDistribuido.Treedoc do
  @moduledoc """
  Núcleo puro para editar y aplicar operaciones Treedoc.

  El estado guarda los átomos por PosID y conserva las eliminaciones para que
  un mensaje repetido o recibido fuera de orden no haga reaparecer un átomo.
  La identidad persistente de réplica y el intercambio de operaciones están pendientes.
  """

  alias DocumentoDistribuido.Treedoc.Operation.{Delete, Insert}
  alias DocumentoDistribuido.Treedoc.PosID

  defstruct entries: %{}, deleted: MapSet.new()

  @type t :: %__MODULE__{
          entries: %{optional(PosID.t()) => String.t()},
          deleted: MapSet.t(PosID.t())
        }

  @doc "Crea un documento vacío."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Inserta un átomo en el índice indicado y devuelve el documento y la operación.

  Los índices cuentan átomos visibles, no bytes ni caracteres. Cada `value` es
  un átomo y puede contener más de un carácter. El llamador debe facilitar un
  desambiguador `{contador, réplica}` que nunca reutilice, incluso tras reinicios
  o al editar otros documentos. Solo se detecta la reutilización observada en
  este documento; el contador persistente aún no está implementado.
  """
  @spec insert(t(), non_neg_integer(), String.t(), PosID.disambiguator()) ::
          {:ok, t(), Insert.t()}
          | {:error,
             :invalid_index | :invalid_operation | :invalid_disambiguator | :disambiguator_used}
  def insert(%__MODULE__{} = doc, index, value, disambiguator) do
    entries = visible(doc)

    cond do
      not is_integer(index) or index < 0 or index > length(entries) ->
        {:error, :invalid_index}

      not is_binary(value) ->
        {:error, :invalid_operation}

      disambiguator_used?(doc, disambiguator) ->
        {:error, :disambiguator_used}

      true ->
        left = if index == 0, do: nil, else: entries |> Enum.at(index - 1) |> elem(0)
        right = if index == length(entries), do: nil, else: entries |> Enum.at(index) |> elem(0)

        with {:ok, position} <- PosID.between(left, right, disambiguator),
             operation = %Insert{position: position, value: value},
             {:ok, updated} <- __MODULE__.apply(doc, operation) do
          {:ok, updated, operation}
        end
    end
  end

  @doc "Elimina el átomo visible del índice indicado y devuelve la operación."
  @spec delete(t(), non_neg_integer()) :: {:ok, t(), Delete.t()} | {:error, :invalid_index}
  def delete(%__MODULE__{} = doc, index) when is_integer(index) and index >= 0 do
    case Enum.at(visible(doc), index) do
      nil ->
        {:error, :invalid_index}

      {position, _value} ->
        operation = %Delete{position: position}
        {:ok, updated} = __MODULE__.apply(doc, operation)
        {:ok, updated, operation}
    end
  end

  def delete(%__MODULE__{}, _index), do: {:error, :invalid_index}

  defp disambiguator_used?(doc, disambiguator) do
    positions = Map.keys(doc.entries) ++ MapSet.to_list(doc.deleted)

    Enum.any?(positions, fn position ->
      Enum.any?(position.components, fn
        {_direction, ^disambiguator} -> true
        _ -> false
      end)
    end)
  end

  @doc """
  Aplica una operación y devuelve el nuevo estado o un error.

  Repetir una operación es idempotente. Si dos inserciones asignan contenido
  diferente al mismo PosID se informa un conflicto: esto viola el requisito de
  unicidad del algoritmo y no se resuelve arbitrariamente.
  """
  @spec apply(t(), Insert.t() | Delete.t()) ::
          {:ok, t()} | {:error, :invalid_operation | :position_conflict}
  def apply(%__MODULE__{} = doc, %Insert{position: position, value: value}) do
    cond do
      not PosID.valid?(position) or not is_binary(value) ->
        {:error, :invalid_operation}

      Map.has_key?(doc.entries, position) and Map.fetch!(doc.entries, position) != value ->
        {:error, :position_conflict}

      true ->
        {:ok, %{doc | entries: Map.put(doc.entries, position, value)}}
    end
  end

  def apply(%__MODULE__{} = doc, %Delete{position: position}) do
    if PosID.valid?(position) do
      {:ok, %{doc | deleted: MapSet.put(doc.deleted, position)}}
    else
      {:error, :invalid_operation}
    end
  end

  def apply(%__MODULE__{}, _operation), do: {:error, :invalid_operation}

  @doc "Devuelve los pares de posición y átomo visibles en orden del documento."
  @spec visible(t()) :: [{PosID.t(), String.t()}]
  def visible(%__MODULE__{} = doc) do
    doc.entries
    |> Enum.reject(fn {position, _value} -> MapSet.member?(doc.deleted, position) end)
    |> Enum.sort(fn {left, _}, {right, _} -> PosID.compare(left, right) != :gt end)
  end

  @doc "Concatena los átomos visibles para obtener el texto del documento."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = doc) do
    doc |> visible() |> Enum.map_join(fn {_position, value} -> value end)
  end
end
