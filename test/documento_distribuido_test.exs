defmodule DocumentoDistribuidoTest do
  use ExUnit.Case
  doctest DocumentoDistribuido

  test "greets the world" do
    assert DocumentoDistribuido.hello() == :world
  end
end
