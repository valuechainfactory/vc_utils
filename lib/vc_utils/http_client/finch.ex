defmodule VCUtils.HTTPClient.Finch do
  @behaviour VCUtils.HTTPClient

  @impl VCUtils.HTTPClient
  def request(method, url, body \\ nil, headers \\ [], opts \\ []) do
    build_opts = Keyword.take(opts, ~w(pool_tag unix_socket)a)

    request_opts =
      Keyword.take(opts, ~w(pool_timeout receive_timeout request_timeout pool_strategy)a)

    method
    |> Finch.build(url, headers, body, build_opts)
    |> Finch.request(VCUtils.HTTPClient.Finch, request_opts)
  end
end
