defmodule VCUtils.HTTPClient.Finch do
  @behaviour VCUtils.HTTPClient

  @impl VCUtils.HTTPClient
  def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
    method
    |> Finch.build(url, headers, body, opts)
    |> Finch.request(VCUtils.Finch)
  end
end
