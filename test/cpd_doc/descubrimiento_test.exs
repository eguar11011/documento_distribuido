defmodule CpdDoc.DescubrimientoTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Descubrimiento

  test "vecinos en una /24, una /28 y una red mayor que /24 (se barre la /24 propia)" do
    vecinos = Descubrimiento.vecinos("192.168.1.37", 24)
    assert length(vecinos) == 253
    assert hd(vecinos) == "192.168.1.1"
    assert List.last(vecinos) == "192.168.1.254"
    refute "192.168.1.37" in vecinos

    assert Descubrimiento.vecinos("10.0.0.20", 28) ==
             Enum.map(17..30, fn x -> "10.0.0.#{x}" end) -- ["10.0.0.20"]

    assert length(Descubrimiento.vecinos("10.1.2.3", 16)) == 253
  end

  test "paquetes de anuncio del contrato" do
    assert Descubrimiento.paquete(:"pi-pe@172.20.10.4") == "crdt-treedoc-1 pi-pe@172.20.10.4"

    assert Descubrimiento.leer_paquete("crdt-treedoc-1 pi-pe@172.20.10.4") ==
             {:ok, :"pi-pe@172.20.10.4"}

    assert Descubrimiento.leer_paquete("crdt-treedoc-1 nerves-1a2b-3f9c07@192.168.1.5") ==
             {:ok, :"nerves-1a2b-3f9c07@192.168.1.5"}

    for malo <- [
          "otra cosa",
          "crdt-treedoc-1 ",
          "crdt-treedoc-1 sin_arroba",
          "crdt-treedoc-1 a@b.local",
          "crdt-treedoc-1 a b@1.2.3.4"
        ] do
      assert Descubrimiento.leer_paquete(malo) == :error
    end
  end

  test "con cualquier máscara de /0 a /32 solo da IPs válidas de la propia /24, sin la propia" do
    for _ <- 1..200, prefijo <- 0..32 do
      [a, b, c, d] = Enum.map(1..4, fn _ -> :rand.uniform(254) end)
      ip = Enum.join([a, b, c, d], ".")
      vecinos = Descubrimiento.vecinos(ip, prefijo)

      refute ip in vecinos
      assert length(vecinos) <= 253

      for v <- vecinos do
        assert {:ok, {^a, ^b, ^c, x}} = :inet.parse_ipv4_address(String.to_charlist(v))
        assert x >= 1 and x <= 254
      end
    end

    assert Descubrimiento.vecinos("10.0.0.5", 31) == []
    assert Descubrimiento.vecinos("10.0.0.5", 32) == []
    assert Descubrimiento.vecinos("10.0.0.5", 30) == ["10.0.0.6"]
  end

  test "paquetes UDP basura no lo tumban y solo se conectan nombres válidos" do
    estado = %{socket: nil, ip: nil, fallidos: %{}, barriendo: nil, nombres: MapSet.new()}

    final =
      Enum.reduce(1..5_000, estado, fn _, e ->
        datos = basura()
        {:noreply, e} = Descubrimiento.handle_info({:udp, nil, {10, 0, 0, 1}, 45_892, datos}, e)
        e
      end)

    for nombre <- final.nombres do
      assert {:ok, ^nombre} = Descubrimiento.leer_nombre("crdt-treedoc-1 " <> nombre)
    end
  end

  test "una inundación de nombres distintos guarda como mucho 256" do
    estado = %{socket: nil, ip: nil, fallidos: %{}, barriendo: nil, nombres: MapSet.new()}

    final =
      Enum.reduce(1..1_000, estado, fn n, e ->
        paquete = "crdt-treedoc-1 inundacion#{n}@10.9.9.9"
        {:noreply, e} = Descubrimiento.handle_info({:udp, nil, {10, 9, 9, 9}, 45_892, paquete}, e)
        e
      end)

    assert MapSet.size(final.nombres) == 256
    assert {:noreply, ^final} = Descubrimiento.handle_info(:mensaje_raro, final)
  end

  defp basura() do
    case :rand.uniform(4) do
      1 -> :crypto.strong_rand_bytes(:rand.uniform(200))
      2 -> "crdt-treedoc-1 " <> :crypto.strong_rand_bytes(:rand.uniform(80))
      3 -> "crdt-treedoc-1 nodo#{:rand.uniform(5)}@10.0.0.#{:rand.uniform(300)}"
      4 -> "crdt-treedoc-1 " <> String.duplicate("a", 100) <> "@1.2.3.4"
    end
  end
end
