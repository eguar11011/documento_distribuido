defmodule CpdDoc.Azar do
  @atomos [
    :op,
    :ins,
    :del,
    :from,
    :vc,
    :pos,
    :ch,
    :remote,
    :hello,
    nil,
    true,
    false,
    :a,
    :"b@127.0.0.1"
  ]

  def termino() do
    termino(3)
  end

  def termino(0) do
    hoja()
  end

  def termino(n) do
    case :rand.uniform(6) do
      1 -> lista(n)
      2 -> List.to_tuple(lista(n))
      3 -> Map.new(lista(n), fn x -> {Enum.random(@atomos), x} end)
      4 -> [termino(n - 1) | hoja()]
      _ -> hoja()
    end
  end

  def mensaje() do
    case :rand.uniform(5) do
      1 -> {:remote, termino()}
      2 -> {:remote, op_casi_valida()}
      3 -> {:hello, termino(1)}
      4 -> {:"$gen_cast", termino()}
      5 -> termino()
    end
  end

  def op_casi_valida() do
    base = %{op: :ins, from: :zz, vc: %{zz: 1 + :rand.uniform(50)}, pos: [{1, 1, :zz}], ch: "x"}
    clave = Enum.random(Map.keys(base))

    case :rand.uniform(4) do
      1 -> Map.put(base, clave, termino(2))
      2 -> Map.delete(base, clave)
      3 -> Map.put(base, :ch, :crypto.strong_rand_bytes(:rand.uniform(100)))
      4 -> Map.put(base, :pos, Enum.map(1..:rand.uniform(5), fn _ -> termino(1) end))
    end
  end

  defp lista(n) do
    Enum.map(1..:rand.uniform(4), fn _ -> termino(n - 1) end)
  end

  defp hoja() do
    case :rand.uniform(8) do
      1 -> :rand.uniform(1000) - 500
      2 -> Enum.random(@atomos)
      3 -> :crypto.strong_rand_bytes(:rand.uniform(8))
      4 -> Enum.random(["a", "é", "👍🏽", "", "ab", <<255>>, "\r\n"])
      5 -> 1.5
      6 -> self()
      7 -> make_ref()
      8 -> []
    end
  end
end
