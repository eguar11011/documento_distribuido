defmodule DocumentoDistribuido.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:documento_distribuido, :arrancar, true) do
        [CpdDoc.Replica, CpdDoc.Descubrimiento] ++ target_children()
      else
        []
      end

    opts = [strategy: :one_for_one, name: DocumentoDistribuido.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.target() == :host do
    defp target_children(), do: []
  else
    defp target_children(), do: [CpdDoc.Red]
  end
end
