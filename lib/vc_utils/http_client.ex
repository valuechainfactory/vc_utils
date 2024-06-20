defmodule VCUtils.HTTPClient do
  require Logger
  @type method() :: :get | :post | :head | :patch | :delete | :options | :put | String.t()

  @callback request(method(), String.t(), String.t() | nil, Keyword.t() | [], Keyword.t() | []) ::
              {:ok, any()} | {:error, any()}

  @callback auth_headers :: Keyword.t()
  @callback process_response({:ok | :error, struct}, Keyword.t()) :: {:ok | :error, struct}

  @optional_callbacks [auth_headers: 0, process_response: 2, request: 5]

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour VCUtils.HTTPClient
      require Logger
      import VCUtils.HTTPClient, only: [process_response: 2]

      @impl true
      def request(method, url, headers \\ [], body \\ nil, opts \\ [])

      def request(method, url, headers, body, opts)
          when is_list(headers) and (is_binary(body) or is_nil(body)) do
        Logger.warning("""
          Invalid order of arguments, instead call request/5 with the following order:
          `request(method, url, body, headers, opts)`

          ...the body and headers arguments were swapped.
        """)

        request(method, url, body, headers, opts)
      end

      def request(method, url, body, headers, opts) do
        :timer.tc(fn ->
          defaults = [adapter: VCUtils.HTTPClient.Finch, serializer: Jason, log_level: :debug]
          config = Application.get_env(:http_client, __MODULE__, defaults)
          config = Keyword.merge(defaults, config)
          adapter = Keyword.get(config, :adapter)
          serializer = Keyword.get(config, :serializer)
          body = if is_map(body), do: serializer.encode!(body), else: body

          method
          |> adapter.request(url, body, headers, opts)
          |> process_response(config)
          |> log(method, url, body, headers, opts, config)
        end)
        |> format_timer()
      end

      @impl true
      def auth_headers, do: []

      defp log(response, method, url, body, headers, opts, config) do
        level = Keyword.get(config, :log_level)

        log = """
        [#{__MODULE__}] Request log

        Method: #{method}
        URL: #{url}
        Headers: \n#{inspect(headers, pretty: true)}

        Body: \n#{inspect(body, pretty: true)}

        Options: \n#{inspect(opts, pretty: true)}

        Response: \n#{inspect(response, pretty: true)}

        [#{__MODULE__}] End request log
        """

        with false <- is_boolean(level),
             true <- level in ~w(debug info warning error)a do
          case level do
            :debug -> Logger.debug(log)
            :info -> Logger.info(log)
            :warning -> Logger.warning(log)
            :error -> Logger.error(log)
          end
        else
          level when is_boolean(level) -> :ok
        end

        response
      end

      defp format_timer({time, response}) do
        human =
          time
          |> Timex.Duration.from_microseconds()
          |> Timex.Format.Duration.Formatters.Humanized.format()

        Logger.warning("""

        [#{__MODULE__}] API call took: #{human}

        """)

        response
      end

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
