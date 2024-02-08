defmodule VCUtils.HTTPClient do
  require Logger
  @type method() :: :get | :post | :head | :patch | :delete | :options | :put | String.t()

  @callback request(method(), String.t(), Keyword.t() | [], String.t() | nil, Keyword.t() | []) ::
              {:ok, any()} | {:error, any()}

  @callback auth_headers :: Keyword.t()
  @callback process_response({:ok | :error, struct}, Keyword.t()) :: {:ok | :error, struct}

  @optional_callbacks [auth_headers: 0, process_response: 2, request: 5]

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour VCUtils.HTTPClient
      import VCUtils.HTTPClient, only: [process_response: 2]

      @impl true
      def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
        defaults = [adapter: VCUtils.HTTPClient.Finch, serializer: Jason]
        config = Application.get_env(:http_client, __MODULE__, defaults)
        adapter = Keyword.get(config, :adapter)
        serializer = Keyword.get(config, :serializer)
        body = if is_map(body), do: serializer.encode!(body), else: body

        method
        |> adapter.request(url, headers, body, opts)
        |> process_response(config)
      end

      @impl true
      def auth_headers, do: []

      defoverridable request: 5, auth_headers: 0
    end
  end

  def process_response(tuple, opts \\ [])

  def process_response({:ok, %{status: status, body: body}}, opts) when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(keys: :atoms) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e ->
      {:error,
       "Error decoding response: \n#{inspect(body, pretty: true)}\n\n#{inspect(e, pretty: true)}"}
  end

  def process_response({:ok, %{status_code: status, body: body}}, opts)
      when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(keys: :atoms) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e ->
      {:error,
       "Error decoding response: \n#{inspect(body, pretty: true)}\n\n#{inspect(e, pretty: true)}"}
  end

  def process_response({:ok, response}, opts) do
    status = Map.get(response, :status) || Map.get(response, :status_code)
    serializer = Keyword.get(opts, :serializer, Jason)

    {:error,
     response.body
     |> serializer.decode!(keys: :atoms)
     |> then(&%{status: status, body: &1})}
  rescue
    e ->
      Logger.error(
        "[#{__MODULE__}] Error decoding response: \n#{inspect(response.body, pretty: true)}\n\n#{inspect(e, pretty: true)}"
      )

      {:error, Map.take(response, ~w(body status status_code))}
  end

  def process_response({:error, %{reason: reason}}, _opts),
    do: {:error, "Error making request: #{inspect(reason, pretty: true)}"}

  def process_response({:error, reason}, _opts), do: {:error, %{error: reason}}
end
