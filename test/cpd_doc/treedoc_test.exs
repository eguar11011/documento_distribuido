defmodule CpdDoc.TreedocTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Causal
  alias CpdDoc.Treedoc

  defp doc(atomos) do
    doc(atomos, [])
  end

  defp doc(atomos, borrados) do
    d = insertar_todos(Treedoc.nuevo(), atomos)
    Enum.reduce(borrados, d, fn p, d -> Treedoc.aplicar(d, %{op: :del, pos: p}) end)
  end

  defp insertar_todos(d, posids) do
    Enum.reduce(posids, d, fn {p, c}, d -> Treedoc.aplicar(d, %{op: :ins, pos: p, ch: c}) end)
  end

  defp escribir(d, i, texto, seq0, nodo) do
    {:ok, posids} = Treedoc.preparar_insercion(d, i, String.graphemes(texto), seq0, nodo)
    {insertar_todos(d, posids), posids}
  end

  test "orden infijo, hermanos por {seq, nodo} y borrados" do
    v1 = [
      {[{1, 1, :a}], "c"},
      {[{1, 1, :a}, {0, 2, :a}], "b"},
      {[{1, 1, :a}, {1, 3, :a}], "d"},
      {[{1, 1, :a}, {0, 2, :a}, {0, 4, :a}], "a"}
    ]

    assert Treedoc.texto(doc(v1)) == "abcd"
    assert Treedoc.texto(doc(v1, [[{1, 1, :a}, {0, 2, :a}]])) == "acd"

    v2 = [
      {[{1, 2, :a}], "Z"},
      {[{1, 1, :b}], "Y"},
      {[{1, 1, :a}, {1, 5, :a}], "x"},
      {[{1, 1, :a}], "X"}
    ]

    assert Treedoc.texto(doc(v2)) == "XxYZ"
  end

  test "figuras 3 y 4 del paper: W e Y a la vez entre c y d, luego X entre W e Y" do
    c = [{1, 1, :c}]
    b = c ++ [{0, 1, :b}]
    e = c ++ [{1, 1, :e}]
    d = e ++ [{0, 1, :d}]
    w = d ++ [{0, 1, :w}]
    y = d ++ [{0, 1, :y}]

    figura_3 = [
      {c, "c"},
      {b, "b"},
      {b ++ [{0, 1, :a}], "a"},
      {e, "e"},
      {d, "d"},
      {e ++ [{1, 1, :f}], "f"},
      {w, "W"},
      {y, "Y"},
      {y ++ [{1, 1, :z}], "Z"}
    ]

    assert Treedoc.texto(doc(figura_3)) == "abcWYZdef"
    assert Treedoc.texto(doc([{w ++ [{1, 1, :x}], "X"} | figura_3])) == "abcWXYZdef"
  end

  test "insertar texto y borrar rangos coinciden con un String en 500 ediciones" do
    {d, cadena, _} =
      Enum.reduce(1..500, {Treedoc.nuevo(), "", 0}, fn _, {d, cadena, seq} ->
        editar_al_azar(d, cadena, seq)
      end)

    assert Treedoc.texto(d) == cadena
  end

  defp editar_al_azar(d, cadena, seq) do
    n = String.length(cadena)

    if n > 0 and :rand.uniform(3) == 1 do
      i = Enum.random(0..(n - 1))
      k = Enum.random(1..min(3, n - i))
      {:ok, posids} = Treedoc.preparar_borrado(d, i, k)
      d = Enum.reduce(posids, d, fn p, d -> Treedoc.aplicar(d, %{op: :del, pos: p}) end)
      {d, String.slice(cadena, 0, i) <> String.slice(cadena, i + k, n), seq}
    else
      i = Enum.random(0..n)
      t = Enum.random(["a", "bc", "ñé", "xyz"])
      {d, _} = escribir(d, i, t, seq, :a)
      {d, String.slice(cadena, 0, i) <> t <> String.slice(cadena, i, n), seq + String.length(t)}
    end
  end

  test "el último paso de cada PosID nuevo lleva el {seq, nodo} de su operación" do
    {d, _} = escribir(Treedoc.nuevo(), 0, "hola", 0, :a)
    {_, posids} = escribir(d, 2, "XYZ", 4, :b)
    ultimos = Enum.map(posids, fn {p, _} -> List.last(p) end)

    assert Enum.map(ultimos, fn {_bit, seq, nodo} -> {seq, nodo} end) == [
             {5, :b},
             {6, :b},
             {7, :b}
           ]
  end

  test "posiciones inválidas no cambian nada" do
    {d, _} = escribir(Treedoc.nuevo(), 0, "ab", 0, :a)

    assert Treedoc.preparar_insercion(d, 3, ["x"], 2, :a) == {:error, :posicion_invalida}
    assert Treedoc.preparar_insercion(d, -1, ["x"], 2, :a) == {:error, :posicion_invalida}
    assert Treedoc.preparar_borrado(d, 1, 2) == {:error, :posicion_invalida}
    assert Treedoc.preparar_borrado(d, 0, 0) == {:ok, []}
  end

  test "sin intercalado: Alice y Charlie a la vez antes del !, hacia adelante" do
    {base, _} = escribir(Treedoc.nuevo(), 0, "Hello!", 0, :base)
    {alice, da} = escribir(base, 5, " Alice", 0, :alice)
    {charlie, dc} = escribir(base, 5, " Charlie", 0, :charlie)

    assert Treedoc.texto(insertar_todos(alice, dc)) == "Hello Alice Charlie!"
    assert Treedoc.texto(insertar_todos(charlie, da)) == "Hello Alice Charlie!"
  end

  test "sin intercalado: Alice y Charlie a la vez antes del !, hacia atrás" do
    {base, _} = escribir(Treedoc.nuevo(), 0, "Hello!", 0, :base)
    {alice, da} = escribir_al_reves(base, 5, " Alice", :alice)
    {charlie, dc} = escribir_al_reves(base, 5, " Charlie", :charlie)

    assert Treedoc.texto(alice) == "Hello Alice!"
    assert Treedoc.texto(insertar_todos(alice, dc)) == "Hello Alice Charlie!"
    assert Treedoc.texto(insertar_todos(charlie, da)) == "Hello Alice Charlie!"
  end

  defp escribir_al_reves(base, i, texto, nodo) do
    letras = Enum.with_index(Enum.reverse(String.graphemes(texto)))

    Enum.reduce(letras, {base, []}, fn {c, k}, {d, posids} ->
      {d, [posid]} = escribir(d, i, c, k, nodo)
      {d, [posid | posids]}
    end)
  end

  test "3 réplicas con entrega causal en órdenes aleatorios convergen (200 ejecuciones)" do
    for _ <- 1..200 do
      {replicas, ops} = simular()

      textos =
        for r <- replicas do
          Treedoc.texto(entregar_todo(r, Enum.shuffle(ops)))
        end

      assert length(Enum.uniq(textos)) == 1

      posids =
        for %{op: :ins, pos: p} <- ops do
          p
        end

      assert length(posids) == length(Enum.uniq(posids))
    end
  end

  defp simular() do
    nodos = [:a, :b, :c]
    inicial = Map.new(nodos, fn n -> {n, %{doc: Treedoc.nuevo(), vc: %{}, espera: []}} end)

    {replicas, ops} =
      Enum.reduce(1..25, {inicial, []}, fn _, {replicas, ops} ->
        n = Enum.random(nodos)
        {r, nuevas} = editar(recibir_alguna(replicas[n], ops), n)
        {Map.put(replicas, n, r), ops ++ nuevas}
      end)

    {Map.values(replicas), ops}
  end

  defp recibir_alguna(r, []) do
    r
  end

  defp recibir_alguna(r, ops) do
    if :rand.uniform(2) == 1 do
      recibir(r, Enum.random(ops))
    else
      r
    end
  end

  defp editar(r, n) do
    visibles = length(Treedoc.visibles(r.doc))
    seq0 = Map.get(r.vc, n, 0)

    ops =
      if visibles > 0 and :rand.uniform(3) == 1 do
        {:ok, [p]} = Treedoc.preparar_borrado(r.doc, Enum.random(0..(visibles - 1)), 1)
        [%{op: :del, from: n, vc: Map.put(r.vc, n, seq0 + 1), pos: p}]
      else
        letras = String.graphemes(Enum.random(["a", "bc"]))
        {:ok, ps} = Treedoc.preparar_insercion(r.doc, Enum.random(0..visibles), letras, seq0, n)

        for {{p, c}, seq} <- Enum.with_index(ps, seq0 + 1) do
          %{op: :ins, from: n, vc: Map.put(r.vc, n, seq), pos: p, ch: c}
        end
      end

    r =
      Enum.reduce(ops, r, fn op, r ->
        %{r | doc: Treedoc.aplicar(r.doc, op), vc: Causal.entregar(r.vc, op)}
      end)

    {r, ops}
  end

  defp recibir(r, op) do
    {vc, espera, aplicadas, _} = Causal.recibir(r.vc, r.espera, op)
    doc = Enum.reduce(aplicadas, r.doc, fn o, d -> Treedoc.aplicar(d, o) end)
    %{r | vc: vc, espera: espera, doc: doc}
  end

  defp entregar_todo(r, ops) do
    r = Enum.reduce(ops, r, fn op, r -> recibir(r, op) end)
    assert r.espera == []
    r.doc
  end

  test "pegar 5000 caracteres es rápido y queda en orden, también entre borrados" do
    texto = String.duplicate("abcdefghij", 500)
    {microsegundos, {d, _}} = :timer.tc(fn -> escribir(Treedoc.nuevo(), 0, texto, 0, :a) end)

    assert Treedoc.texto(d) == texto
    assert microsegundos < 2_000_000

    {:ok, posids} = Treedoc.preparar_borrado(d, 100, 50)
    d = Enum.reduce(posids, d, fn p, d -> Treedoc.aplicar(d, %{op: :del, pos: p}) end)
    {d, _} = escribir(d, 100, "PEGADO", 5000, :b)
    esperado = String.slice(texto, 0, 100) <> "PEGADO" <> String.slice(texto, 150, 5000)

    assert Treedoc.texto(d) == esperado
  end

  test "caracteres de varios puntos de código ocupan una sola posición" do
    {d, _} = escribir(Treedoc.nuevo(), 0, "a👍🏽é\r\nñ🇨🇴", 0, :a)

    assert Treedoc.texto(d) == "a👍🏽é\r\nñ🇨🇴"
    assert length(Treedoc.visibles(d)) == 6
    {:ok, [p]} = Treedoc.preparar_borrado(d, 1, 1)
    assert Treedoc.texto(Treedoc.aplicar(d, %{op: :del, pos: p})) == "aé\r\nñ🇨🇴"
  end

  test "4 réplicas, cada operación llega entre 1 y 3 veces en cualquier orden (500 ejecuciones)" do
    for _ <- 1..500 do
      {replicas, ops} = simular()
      d = Enum.random(replicas)

      textos =
        for _ <- 1..4 do
          repetidas = Enum.flat_map(ops, fn op -> List.duplicate(op, :rand.uniform(3)) end)
          Treedoc.texto(entregar_todo(d, Enum.shuffle(repetidas)))
        end

      assert length(Enum.uniq(textos)) == 1
    end
  end
end
