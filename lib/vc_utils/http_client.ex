defmodule VCUtils.HTTPClient do
  @moduledoc """
  Behaviour and `__using__` macro for building JSON HTTP API clients with consistent
  request/response handling, logging, and telemetry.

  ## Usage

      defmodule MyApp.APIClient do
        use VCUtils.HTTPClient

        @base_url "https://api.example.com"

        @impl true
        def auth_headers, do: [{"Authorization", "Bearer \#{token()}"}]

        def get_user(id) do
          request(:get, "\#{@base_url}/users/\#{id}", nil, auth_headers())
        end
      end

  `request/5` takes its arguments in the order `request(method, url, body, headers, opts)`.
  A `body` given as a map is encoded with the configured `:serializer` before being sent;
  a 2xx JSON response is decoded the same way. `auth_headers/0` is not merged in
  automatically — pass it explicitly as the `headers` argument on each call, as above.

  ## Configuration

  Configuration is looked up per client module, keyed by the module itself:

      config :vc_utils, MyApp.APIClient,
        adapter: VCUtils.HTTPClient.Finch,
        serializer: Jason,
        log_level: :debug,
        lite_log_level: :warning,
        keys: :atoms

    * `:adapter` - module implementing this behaviour's `request/5` callback, responsible
      for performing the actual HTTP call. Defaults to `VCUtils.HTTPClient.Finch`.
    * `:serializer` - module implementing `encode!/1` and `decode!/2` (e.g. `Jason`).
      Defaults to `Jason`.
    * `:log_level` - level used to log the full request/response payload (method, url,
      headers, body, opts, response) on every request. One of `:debug`, `:info`,
      `:warning`, `:error`; any other value (e.g. `false` or `:none`) disables it.
      Defaults to `:debug`.
    * `:lite_log_level` - level used to log a one-line summary after every request, in the
      form `"Received <status> for <path> in <duration>"`. Accepts the same values as
      `:log_level`. Defaults to `:warning`.
    * `:keys` - passed through as an option to the serializer's `decode!/2` (e.g. `:atoms`
      or `:strings` for `Jason`). Defaults to `:atoms`.

  ## Overriding the request timeout

  Per-request options, including timeouts, are passed straight through via the `opts`
  (5th) argument to the adapter. With the default `VCUtils.HTTPClient.Finch` adapter:

      MyApp.APIClient.request(:get, url, nil, headers, receive_timeout: 30_000)

  Supported keys: `:receive_timeout` (default `15_000`ms), `:request_timeout` (default
  `:infinity`), `:pool_timeout` (default `5_000`ms). See `Finch.request/3` for details on
  each.

  ## Telemetry

  Every request emits a `[:vc_utils, :http_client, :request]` telemetry event with
  `%{duration: native_time_microseconds}` measurements and metadata
  `%{module, method, url, body, headers, opts, status, response}`.
  """

  require Logger

  @typedoc "HTTP method accepted by `request/5`."
  @type method() :: :get | :post | :head | :patch | :delete | :options | :put | String.t()

  @doc """
  Performs an HTTP request.

  Arguments are given in the order `request(method, url, body, headers, opts)`. When
  `body` is a map, it is encoded via the configured `:serializer` before being sent.
  """
  @callback request(method(), String.t(), String.t() | nil, Keyword.t() | [], Keyword.t() | []) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Returns headers to be included with a request, typically used for authentication.

  Not applied automatically — call it explicitly when building the `headers` argument for
  `request/5`, e.g. `request(:get, url, nil, auth_headers())`.
  """
  @callback auth_headers() :: list(tuple())

  @doc """
  Normalizes an adapter's raw `{:ok, response} | {:error, reason}` result: decodes JSON
  bodies for 2xx responses and turns everything else into an `{:error, term()}`.
  """
  @callback process_response({:ok | :error, struct}, Keyword.t()) :: {:ok | :error, struct}

  @optional_callbacks [auth_headers: 0, process_response: 2, request: 5]

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour VCUtils.HTTPClient
      require Logger
      import VCUtils.HTTPClient, only: [process_response: 2]

      @impl true
      def request(method, url, body \\ nil, headers \\ [], opts \\ [])

      def request(method, url, headers, body, opts)
          when is_list(headers) and (is_binary(body) or is_nil(body) or is_map(body)) do
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
          lite_log_level: :warning,
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
        |> emit_telemetry(method, url, body, headers, opts)
        |> format_timer(url, config)
      end

      @impl true
      def auth_headers, do: [{"Content-Type", "application/json"}]

      defp log(response, method, url, body, headers, opts, config) do
        level = Keyword.get(config, :log_level, :debug)

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

        log_at_level(level, log)

        response
      end

      defp log_at_level(level, message) do
        with true <- is_atom(level),
             true <- level in ~w(debug info warning error)a do
          Logger.log(level, message)
        end

        :ok
      end

      defp emit_telemetry({time, response} = result, method, url, body, headers, opts) do
        status =
          case response do
            {_, %{status: status}} -> status
            _ -> nil
          end

        :telemetry.execute(
          [:vc_utils, :http_client, :request],
          %{duration: time},
          %{
            module: __MODULE__,
            method: method,
            url: url,
            body: body,
            headers: headers,
            opts: opts,
            status: status,
            response: response
          }
        )

        result
      end

      defp format_timer({time, response}, url, config) do
        level = Keyword.get(config, :lite_log_level, :warning)
        humanized_time = humanize_time(time)

        status =
          response
          |> elem(1)
          |> case do
            %{status: status} -> status
            "" -> "an empty string response"
            error when is_binary(error) -> error
            any -> inspect(any)
          end

        log_at_level(
          level,
          "[#{__MODULE__}] Received #{status} for #{url |> URI.parse() |> Map.get(:path)} in #{humanized_time}"
        )

        response
      end

      defp humanize_time(time) do
        minutes = div(time, 60_000_000)
        seconds = time |> rem(60_000_000) |> div(1_000_000)
        ms = time |> rem(1_000_000) |> div(1_000)
        us = rem(time, 1_000)

        [{minutes, "min"}, {seconds, "s"}, {ms, "ms"}, {us, "µs"}]
        |> Enum.reject(fn {v, _} -> v == 0 end)
        |> case do
          [] -> "0µs"
          parts -> parts |> Enum.take(2) |> Enum.map_join(" ", fn {v, unit} -> "#{v}#{unit}" end)
        end
      end

      defoverridable request: 5, auth_headers: 0
    end
  end

  @doc """
  Default implementation of the `c:process_response/2` callback.

  Decodes JSON bodies for 2xx responses (accepting either `:status` or `:status_code` on
  the response struct, to work with adapters other than `VCUtils.HTTPClient.Finch`) using
  the `:serializer` given in `opts` (defaults to `Jason`). Anything outside the 2xx range,
  or a decode failure, is returned as `{:error, term()}`.
  """
  def process_response(tuple, opts \\ [])

  def process_response({:ok, %{status: status, body: ""}}, _) when status in 200..299 do
    {:ok, %{status: status, body: ""}}
  end

  def process_response({:ok, %{status: status, body: ""}}, _) do
    {:error, %{status: status, body: ""}}
  end

  def process_response({:ok, %{status: status, body: body} = response}, opts)
      when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(opts) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e ->
      error = """
      #{inspect(body, pretty: true)}
      ##{Exception.format(:error, e, __STACKTRACE__)}
      """

      Logger.error("[#{__MODULE__}] Error decoding response: \n#{error}")
      {:error, response}
  end

  def process_response({:ok, %{status_code: status, body: body} = response}, opts)
      when status in 200..299 do
    serializer = Keyword.get(opts, :serializer, Jason)
    body |> serializer.decode!(opts) |> then(&{:ok, %{status: status, body: &1}})
  rescue
    e ->
      error = """
      #{inspect(body, pretty: true)}
      ##{Exception.format(:error, e, __STACKTRACE__)}
      """

      Logger.error("[#{__MODULE__}] Error decoding response: \n#{error}")
      {:error, response}
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
      error = """
      #{inspect(response.body, pretty: true)}
      ##{Exception.format(:error, e, __STACKTRACE__)}
      """

      Logger.error("[#{__MODULE__}] Error decoding response: \n#{error}")
      {:error, response}
  end

  def process_response({:error, %{reason: reason}}, _opts),
    do: {:error, "Error making request: #{inspect(reason, pretty: true)}"}

  def process_response({:error, reason}, _opts), do: {:error, %{error: reason}}
end
