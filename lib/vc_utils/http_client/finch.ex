defmodule VCUtils.HTTPClient.Finch do
  @behaviour VCUtils.HTTPClient

  @impl VCUtils.HTTPClient
  def request(method, url, headers \\ [], body \\ nil) do
    method
    |> Finch.build(url, headers, body)
    |> Finch.request(VCUtils.Finch)
  end
end
