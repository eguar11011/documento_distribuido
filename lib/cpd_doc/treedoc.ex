defmodule CpdDoc.Treedoc do
  def nuevo() do
    %{atomos: %{}, borrados: MapSet.new()}
  end

  def menor?([], []) do
    false
  end

  def menor?([], [{bit, _, _} | _]) do
    bit == 1
  end

  def menor?([{bit, _, _} | _], []) do
    bit == 0
  end

  def menor?([x | r1], [x | r2]) do
    menor?(r1, r2)
  end

  def menor?([x | _], [y | _]) do
    x < y
  end

  def orden(doc) do
    Enum.sort(Map.to_list(doc.atomos), fn {p1, _}, {p2, _} -> menor?(p1, p2) end)
  end

  def visibles(doc) do
    sin_borrados(orden(doc), doc.borrados)
  end

  def texto(doc) do
    Enum.map_join(visibles(doc), fn {_, caracter} -> caracter end)
  end

  def nuevo_posid(p, nil, seq, nodo) do
    p ++ [{1, seq, nodo}]
  end

  def nuevo_posid(p, f, seq, nodo) do
    if List.starts_with?(f, p) do
      f ++ [{0, seq, nodo}]
    else
      p ++ [{1, seq, nodo}]
    end
  end

  def preparar_insercion(doc, i, caracteres, seq0, nodo) do
    orden = orden(doc)
    visibles = sin_borrados(orden, doc.borrados)

    if is_integer(i) and i >= 0 and i <= length(visibles) do
      p = anterior(visibles, i)
      lugar = {:entre, p, siguiente(orden, p)}
      colocados = balancear(Enum.with_index(caracteres, seq0 + 1), lugar, nodo)
      {:ok, en_orden(colocados)}
    else
      {:error, :posicion_invalida}
    end
  end

  def preparar_borrado(doc, i, n) do
    visibles = visibles(doc)

    if is_integer(i) and is_integer(n) and i >= 0 and n >= 0 and i + n <= length(visibles) do
      {:ok, Enum.map(Enum.slice(visibles, i, n), fn {posid, _} -> posid end)}
    else
      {:error, :posicion_invalida}
    end
  end

  def aplicar(doc, %{op: :ins, pos: posid, ch: caracter}) do
    %{doc | atomos: Map.update(doc.atomos, posid, caracter, fn otro -> min(otro, caracter) end)}
  end

  def aplicar(doc, %{op: :del, pos: posid}) do
    %{doc | borrados: MapSet.put(doc.borrados, posid)}
  end

  defp balancear([], _lugar, _nodo) do
    []
  end

  defp balancear(caracteres, lugar, nodo) do
    {izquierda, [{caracter, seq} | derecha]} = Enum.split(caracteres, div(length(caracteres), 2))
    posid = ubicar(lugar, seq, nodo)
    medio = [{posid, caracter, seq}]

    medio ++
      balancear(izquierda, {:hijo, posid, 0}, nodo) ++ balancear(derecha, {:hijo, posid, 1}, nodo)
  end

  defp ubicar({:entre, p, f}, seq, nodo) do
    nuevo_posid(p, f, seq, nodo)
  end

  defp ubicar({:hijo, padre, bit}, seq, nodo) do
    padre ++ [{bit, seq, nodo}]
  end

  defp en_orden(colocados) do
    ordenados = Enum.sort_by(colocados, fn {_posid, _caracter, seq} -> seq end)
    Enum.map(ordenados, fn {posid, caracter, _seq} -> {posid, caracter} end)
  end

  defp sin_borrados(orden, borrados) do
    Enum.reject(orden, fn {posid, _} -> MapSet.member?(borrados, posid) end)
  end

  defp anterior(_visibles, 0) do
    []
  end

  defp anterior(visibles, i) do
    {posid, _} = Enum.at(visibles, i - 1)
    posid
  end

  defp siguiente([], _p) do
    nil
  end

  defp siguiente([{f, _} | _], []) do
    f
  end

  defp siguiente(orden, p) do
    case Enum.drop_while(orden, fn {q, _} -> q != p end) do
      [_, {f, _} | _] -> f
      _ -> nil
    end
  end
end
