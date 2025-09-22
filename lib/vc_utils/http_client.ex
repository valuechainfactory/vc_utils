defmodule VCUtils.HTTPClient do
  require Logger
  @type method() :: :get | :post | :head | :patch | :delete | :options | :put | String.t()

  @callback request(method(), String.t(), String.t() | nil, Keyword.t() | [], Keyword.t() | []) ::
              {:ok, any()} | {:error, any()}

  @callback auth_headers() :: list(tuple())
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
        defaults = [
          adapter: VCUtils.HTTPClient.Finch,
          serializer: Jason,
          log_level: :debug,
          keys: :atoms
        ]

        config = Application.get_env(:vc_utils, __MODULE__, defaults)
        config = Keyword.merge(defaults, config)

        :timer.tc(fn ->
          adapter = Keyword.get(config, :adapter)
          serializer = Keyword.get(config, :serializer)
          body = if is_map(body), do: serializer.encode!(body), else: body

          method
          |> adapter.request(url, body, headers, opts)
          |> log(method, url, body, headers, opts, config)
          |> process_response(config)
        end)
        |> log_telemetry_async(method, url, body, headers, opts, config)
        |> format_timer(url)
      end

      @impl true
      def auth_headers, do: [{"Content-Type", "application/json"}]

      defp log(response, method, url, body, headers, opts, config) do
        level = Keyword.get(config, :log_level, :warning)

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
             true <- level in ~w(debug info warning error none)a do
          Logger.log(level, log)
        else
          level when is_boolean(level) -> :ok
        end

        response
      end

      defp log_telemetry({time, response}, method, url, body, headers, opts, config) do
        with listener = Keyword.get(config, :telemetry_listener),
             true <- not is_nil(listener),
             pid = (is_atom(listener) && Process.whereis(listener)) || listener,
             true <- is_pid(pid) do
          send(pid, {:http_request, {time, response}, method, url, body, headers, opts})
        end
      end

      defp log_telemetry_async(response, method, url, body, headers, opts, config) do
        Task.start(fn -> log_telemetry(response, method, url, body, headers, opts, config) end)
        response
      end

      defp format_timer({time, response}, url) do
        human =
          time
          |> Timex.Duration.from_microseconds()
          |> Timex.Format.Duration.Formatters.Humanized.format()

        "[#{__MODULE__}] Recieved #{response |> elem(1) |> Map.get(:status)} for #{url |> URI.parse() |> Map.get(:path)} in #{human}"
        |> Logger.warning()

        response
      end

      defoverridable request: 5, auth_headers: 0
    end
  end

  def process_response(tuple, opts \\ [])

  def process_response({:ok, %{status: status, body: body}}, opts) when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(opts) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e ->
      {:error,
       "Error decoding response: \n#{inspect(body, pretty: true)}\n\n#{inspect(e, pretty: true)}"}
  end

  def process_response({:ok, %{status_code: status, body: body}}, opts)
      when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(opts) |> then(&{:ok, %{status: status, body: &1}})
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
     |> serializer.decode!(opts)
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
