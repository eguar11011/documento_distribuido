defmodule CpdDoc.InterfazTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Interfaz

  test "prefiere Ethernet y usa Wi-Fi al desconectar el cable" do
    eth = [%{family: :inet, address: {192, 168, 1, 10}}]
    wifi = [%{family: :inet, address: {10, 171, 42, 141}}]

    assert Interfaz.ipv4(eth, wifi) == "192.168.1.10"
    assert Interfaz.ipv4([], wifi) == "10.171.42.141"
    assert Interfaz.ipv4(nil, nil) == nil
  end

  test "ignora IPv6, loopback y direcciones de enlace local" do
    eth = [
      %{family: :inet6, address: {0, 0, 0, 0, 0, 0, 0, 1}},
      %{family: :inet, address: {127, 0, 0, 1}},
      %{family: :inet, address: {169, 254, 1, 2}}
    ]

    assert Interfaz.ipv4(eth, [%{family: :inet, address: {10, 0, 0, 5}}]) == "10.0.0.5"
  end
end
