defmodule VCUtils.HTTPClient.Finch do
  @behaviour VCUtils.HTTPClient

  @impl VCUtils.HTTPClient
  def request(method, url, body \\ nil, headers \\ [], opts \\ []) do
    method
    |> Finch.build(url, headers, body, opts)
    |> Finch.request(VCUtils.HTTPClient.Finch)
  end
end
