defmodule VCUtils.HTTPClient do
  require Logger
  @type method() :: :get | :post | :head | :patch | :delete | :options | :put | String.t()

  @callback request(method(), String.t(), Keyword.t(), String.t() | nil) ::
              {:ok, any()} | {:error, any()}

  @callback auth_headers :: Keyword.t()
  @callback process_response({:ok | :error, struct}) :: {:ok | :error, struct}

  @optional_callbacks [auth_headers: 0, process_response: 1, request: 4]

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour VCUtils.HTTPClient
      import VCUtils.HTTPClient, only: [process_response: 1]

      @impl true
      def request(method, url, headers \\ [], body \\ nil) do
        config = Application.get_env(:http_client, __MODULE__, [])
        mod = Keyword.get(config, :mod, VCUtils.HTTPClient.Finch)
        body = if is_map(body), do: Jason.encode!(body), else: body

        method
        |> mod.request(url, headers, body)
        |> process_response()
      end

      @impl true
      def auth_headers, do: []

      defoverridable request: 4, auth_headers: 0
    end
  end

  def process_response(tuple, opts \\ [])

  def process_response({:ok, %{status: status, body: body}}, _opts) when status in 200..299 do
    body |> Jason.decode!(keys: :atoms) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e in Jason.DecodeError ->
      {:error,
       "Error decoding response: \n#{inspect(body, pretty: true)}\n\n#{inspect(e, pretty: true)}"}
  end

  def process_response({:ok, %{status_code: status, body: body}}, _opts)
      when status in 200..299 do
    body |> Jason.decode!(keys: :atoms) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e in Jason.DecodeError ->
      {:error,
       "Error decoding response: \n#{inspect(body, pretty: true)}\n\n#{inspect(e, pretty: true)}"}
  end

  def process_response({:ok, response}, _opts) do
    status = Map.get(response, :status) || Map.get(response, :status_code)

    {:error,
     response.body
     |> Jason.decode!(keys: :atoms)
     |> then(&%{status: status, body: &1})}
  rescue
    e in Jason.DecodeError ->
      Logger.error(
        "[#{__MODULE__}] Error decoding response: \n#{inspect(response.body, pretty: true)}\n\n#{inspect(e, pretty: true)}"
      )

      {:error, Map.take(response, ~w(body status status_code))}
  end

  def process_response({:error, %{reason: reason}}, _opts),
    do: {:error, "Error making request: #{inspect(reason, pretty: true)}"}

  def process_response({:error, reason}, _opts), do: {:error, %{error: reason}}
end
