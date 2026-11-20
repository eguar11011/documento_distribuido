defmodule DocumentoDistribuido.Document do
  @moduledoc """
  Límite previsto para el GenServer propietario de un documento.

  Serializará las solicitudes y delegará las reglas al núcleo Treedoc. Todavía
  no se inicia ningún proceso ni se implementan llamadas al servidor.
  """
end
