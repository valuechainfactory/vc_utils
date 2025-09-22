defmodule VCUtils.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  if Mix.env() in [:dev, :test] do
    @ca_verify :verify_none
  else
    @ca_verify :verify_peer
  end

  @impl true
  def start(_type, _args) do
    default = [
      name: VCUtils.HTTPClient.Finch,
      pools: %{
        default: [
          size: 1_000_000_000,
          start_pool_metrics?: true,
          conn_opts: [transport_opts: [verify: @ca_verify]]
        ]
      }
    ]

    opts = Application.get_env(:vc_utils, :finch_options, default)

    children = [
      {Finch, opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VCUtils.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # defp ca_unverified_opts() do
  #   :vc_utils
  #   |> Application.get_env(:ca_unverified, [])
  #   |> Enum.reduce(%{}, fn {host, conn_opts}, acc -> Map.put(acc, host, conn_opts: conn_opts) end)
  # end
end
