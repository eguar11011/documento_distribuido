defmodule CpdDoc.Causal do
  def siguiente(vc, yo) do
    seq = Map.get(vc, yo, 0) + 1
    {seq, Map.put(vc, yo, seq)}
  end

  def clasificar(vc, %{from: i, vc: m}) do
    mi = Map.get(m, i, 0)
    vi = Map.get(vc, i, 0)

    cond do
      mi <= vi ->
        :duplicada

      mi == vi + 1 and dependencias_listas?(vc, i, m) ->
        :entregable

      true ->
        :espera
    end
  end

  def entregar(vc, %{from: i, vc: m}) do
    Map.put(vc, i, Map.get(m, i, 0))
  end

  def recibir(vc, espera, op) do
    case clasificar(vc, op) do
      :duplicada ->
        {vc, espera, [], :duplicada}

      :espera ->
        {vc, guardar(espera, op), [], :espera}

      :entregable ->
        {vc, espera, aplicadas} = vaciar(entregar(vc, op), espera, [op])
        {vc, espera, aplicadas, :aplicada}
    end
  end

  def faltan(vc, %{from: i, vc: m}) do
    Enum.reduce(m, %{}, fn {k, n}, faltan ->
      necesita = necesita(i, k, n)

      if necesita > Map.get(vc, k, 0) do
        Map.put(faltan, k, necesita)
      else
        faltan
      end
    end)
  end

  defp dependencias_listas?(vc, i, m) do
    Enum.all?(m, fn {k, n} -> k == i or n <= Map.get(vc, k, 0) end)
  end

  defp guardar(espera, op) do
    if Enum.any?(espera, fn otra -> misma?(otra, op) end) do
      espera
    else
      espera ++ [op]
    end
  end

  defp vaciar(vc, espera, aplicadas) do
    espera = Enum.reject(espera, fn op -> clasificar(vc, op) == :duplicada end)

    case Enum.find(espera, fn op -> clasificar(vc, op) == :entregable end) do
      nil -> {vc, espera, Enum.reverse(aplicadas)}
      op -> vaciar(entregar(vc, op), List.delete(espera, op), [op | aplicadas])
    end
  end

  defp misma?(a, b) do
    a.from == b.from and a.vc[a.from] == b.vc[b.from]
  end

  defp necesita(i, i, n) do
    n - 1
  end

  defp necesita(_i, _k, n) do
    n
  end
end
