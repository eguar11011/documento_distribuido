defmodule DocumentoDistribuido.Treedoc.PosID do
  @moduledoc """
  Posición en el árbol extendido de Treedoc (artículo, sección 3.1).

  Un camino contiene ramas `:left` y `:right` hacia nodos mayores y termina
  en un mininodo `{dirección, {contador, réplica}}`. Una dirección con
  desambiguador también puede aparecer antes del final cuando el camino pasa
  por un mininodo. `:root` identifica un mininodo de la raíz y solo puede
  aparecer en el primer componente.

  Los desambiguadores UDIS se ordenan por contador y luego por réplica.
  Cada réplica deberá conservar un contador propio y una identidad única; este
  módulo genera caminos, pero no administra ni persiste esos datos.
  """

  @enforce_keys [:components]
  defstruct [:components]

  @type direction :: :left | :right
  @type disambiguator :: {non_neg_integer(), String.t()}
  @type component :: direction() | {direction() | :root, disambiguator()}
  @type t :: %__MODULE__{components: [component(), ...]}

  @doc "Construye un PosID si el camino y sus desambiguadores son válidos."
  @spec new(term()) :: {:ok, t()} | {:error, :invalid_position}
  def new(components) do
    position = %__MODULE__{components: components}
    if valid?(position), do: {:ok, position}, else: {:error, :invalid_position}
  end

  @doc "Comprueba la forma del camino; no garantiza la unicidad de la réplica."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{components: components}) when is_list(components) do
    components != [] and
      Enum.with_index(components)
      |> Enum.all?(fn {component, index} ->
        valid_component?(component, index)
      end) and match?({_, {_, _}}, List.last(components))
  end

  def valid?(_), do: false

  @doc "Compara dos PosID válidos según el orden infijo del árbol."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    if valid?(left) and valid?(right) do
      compare_paths(tokens(left.components), tokens(right.components))
    else
      raise ArgumentError, "se requieren dos PosID válidos"
    end
  end

  @doc """
  Genera una posición entre dos límites abiertos o cerrados.

  `nil` representa la ausencia de límite. El llamador debe proporcionar un
  desambiguador globalmente único para cada inserción. Se usa un descendiente
  de un mininodo: es una estrategia simple que no balancea el árbol y no es
  una transcripción literal del algoritmo 1 del artículo.
  """
  @spec between(t() | nil, t() | nil, disambiguator()) ::
          {:ok, t()} | {:error, :invalid_position | :invalid_bounds | :invalid_disambiguator}
  def between(left, right, disambiguator) do
    cond do
      not valid_disambiguator?(disambiguator) ->
        {:error, :invalid_disambiguator}

      not valid_bound?(left) or not valid_bound?(right) ->
        {:error, :invalid_position}

      left != nil and right != nil and compare(left, right) != :lt ->
        {:error, :invalid_bounds}

      true ->
        {:ok, between_valid(left, right, disambiguator)}
    end
  end

  defp valid_bound?(nil), do: true
  defp valid_bound?(position), do: valid?(position)

  defp valid_disambiguator?({counter, replica}) do
    is_integer(counter) and counter >= 0 and is_binary(replica) and byte_size(replica) > 0
  end

  defp valid_disambiguator?(_), do: false

  defp between_valid(nil, nil, disambiguator),
    do: %__MODULE__{components: [{:root, disambiguator}]}

  defp between_valid(nil, right, disambiguator), do: child(right, :left, disambiguator)
  defp between_valid(left, nil, disambiguator), do: child(left, :right, disambiguator)

  defp between_valid(left, right, disambiguator) do
    if Enum.take(right.components, length(left.components)) == left.components do
      child(right, :left, disambiguator)
    else
      child(left, :right, disambiguator)
    end
  end

  defp child(position, direction, disambiguator),
    do: %__MODULE__{components: position.components ++ [{direction, disambiguator}]}

  defp valid_component?(direction, _index) when direction in [:left, :right], do: true

  defp valid_component?({direction, {counter, replica}}, index)
       when direction in [:left, :right, :root] and is_integer(counter) and counter >= 0 and
              is_binary(replica) and byte_size(replica) > 0 do
    direction != :root or index == 0
  end

  defp valid_component?(_, _), do: false

  defp compare_paths([], []), do: :eq
  defp compare_paths([], [next | _]), do: if(left?(next), do: :gt, else: :lt)
  defp compare_paths([next | _], []), do: if(left?(next), do: :lt, else: :gt)

  defp compare_paths([component | left], [component | right]),
    do: compare_paths(left, right)

  defp compare_paths([left | _], [right | _]) do
    left_key = component_key(left)
    right_key = component_key(right)
    if left_key < right_key, do: :lt, else: :gt
  end

  # Primero se entra en el nodo mayor y después se selecciona su mininodo.
  # Esto preserva el orden infijo también para hijos de nodos mayores.
  defp tokens(components) do
    Enum.flat_map(components, fn
      :left -> [{0, nil}]
      :right -> [{2, nil}]
      {:root, disambiguator} -> [{1, disambiguator}]
      {:left, disambiguator} -> [{0, nil}, {1, disambiguator}]
      {:right, disambiguator} -> [{2, nil}, {1, disambiguator}]
    end)
  end

  defp left?({0, nil}), do: true
  defp left?(_), do: false

  defp component_key(component), do: component
end
