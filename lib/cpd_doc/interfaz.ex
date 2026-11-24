defmodule CpdDoc.Interfaz do
  @moduledoc "Selección de dirección para el nodo: Ethernet primero, luego Wi-Fi."

  def ipv4(ethernet, wifi) do
    direccion(ethernet) || direccion(wifi)
  end

  defp direccion(direcciones) when is_list(direcciones) do
    Enum.find_value(direcciones, fn
      %{family: :inet, address: {127, _, _, _}} -> nil
      %{family: :inet, address: {169, 254, _, _}} -> nil
      %{family: :inet, address: {0, _, _, _}} -> nil
      %{family: :inet, address: {a, b, c, d}} -> Enum.join([a, b, c, d], ".")
      _ -> nil
    end)
  end

  defp direccion(_), do: nil
end
