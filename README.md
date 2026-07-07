# VCUtils

Tools and helpers we constantly find repeated in most of our projects.

## Contents

- [Installation](#installation)
- [Usage](#usage)
  - [Database CRUD and Query helpers](#database-crud-and-query-helpers)
  - [Easy and Quick setup of a HTTP Client](#easy-and-quick-setup-of-a-http-client)
    - [Configuration](#configuration)
    - [Overriding the request timeout](#overriding-the-request-timeout)
    - [Customizing the Finch pool](#customizing-the-finch-pool)
    - [Telemetry](#telemetry)
    - [Mocking in tests](#mocking-in-tests)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `vc_utils` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vc_utils, git: "https://github.com/valuechainfactory/vc_utils.git"}
  ]
end
```

## Usage

### Database CRUD and Query helpers

Setup a module `MyApp.Schema`

```elixir
defmodule MyApp.Schema do
  defmacro __using__(_opts) do
    quote location: :keep do
      use Ecto.Schema
      use VCUtils.FieldQueries
      use VCUtils.RepoCrud, repo: MyApp.Repo
    end
  end
end
```

..then in specific `Ecto.Schema` modules, just user the `def_crud` and `defbyq` macros to setup Create, Modify, Get and Delete functions, and handy query filtering functions.

Example:

```elixir
defmodule MyApp.User do
  use MyApp.Schema

  schema "users" do
    field: :name, :string
    field: :phone, :string
    ...
  end

  def_crud [:create, :modify, :get, :delete]

  defbyq [:name, :phone]
end
```

This generates functions that assist in CRUD functions and query filtering functions.
More details on `defbyq` and `def_crud` in the `VCUtils.FieldQueries` and `VCUtils.RepoCrud` module respectively.

---

### Easy and Quick setup of a HTTP Client

The benefits of this is the handling of response, and json decoding out of the box. One can configure custom json serializers or define custom ones in scenarios where one is probably not working with a json api.

... setting up a mock of the api, requires to mock the expected `request/5` callback provided by `VCUtils.HTTPClient`.

... more details and exampls on the module docs of `VCUtils.HTTPClient` module.

```elixir
defmodule MyApp.APIClient do
  @moduledoc """
  This module is responsible for making requests to the remote API.
  """
  use VCUtils.HTTPClient

  # ----- Callbacks ----- #
  def config, do: Application.fetch_env!(:my_app, __MODULE__)
  def config(key), do: config() |> Keyword.fetch!(key)

  @impl true
  def auth_headers do
    username = config(:username)
    password = config(:password)
    token = Base.encode64("#{username}:#{password}")

    [
      {"Content-Type", "application/json"},
      {"Authorization", "Basic #{token}"}
    ]
  end

  # ----- End of Callbacks ----- #

  def some_remote_call(params) do
    request(:post, url, params, auth_headers())
  end
end
```

`request/5` takes its arguments in the order `request(method, url, body, headers, opts)`.
`auth_headers/0` is not merged in automatically, so pass it explicitly as `headers` on
every call, as above.

#### Configuration

Configuration is looked up per client module, keyed by the module itself:

```elixir
config :vc_utils, MyApp.APIClient,
  adapter: VCUtils.HTTPClient.Finch,
  serializer: Jason,
  log_level: :debug,
  lite_log_level: :warning,
  keys: :atoms
```

* `:adapter` - module performing the actual HTTP call. Defaults to `VCUtils.HTTPClient.Finch`.
* `:serializer` - module implementing `encode!/1` and `decode!/2`. Defaults to `Jason`.
* `:log_level` - level for the full request/response payload log. Defaults to `:debug`.
* `:lite_log_level` - level for the one-line `"Received <status> for <path> in <duration>"`
  summary logged after every request. Defaults to `:warning`.
* `:keys` - passed to the serializer's `decode!/2` (e.g. `:atoms` or `:strings`). Defaults to `:atoms`.

Any of `:log_level`/`:lite_log_level` can be set to `false` (or any value other than
`:debug`/`:info`/`:warning`/`:error`) to disable that log.

#### Overriding the request timeout

Per-request options are passed through the `opts` (5th) argument to the adapter. With the
default `VCUtils.HTTPClient.Finch` adapter:

```elixir
MyApp.APIClient.request(:get, url, nil, headers, receive_timeout: 30_000)
```

Supported keys: `:receive_timeout` (default 15s), `:request_timeout` (default `:infinity`),
`:pool_timeout` (default 5s).

#### Customizing the Finch pool

The options above are per-request. To tune connection pooling, concurrency, or TLS
verification (settings that live for the app's lifetime, not a single call), configure the
underlying `Finch` pool itself.

`VCUtils.HTTPClient.Finch` (the default adapter) requires a `Finch` pool named
`VCUtils.HTTPClient.Finch`. `VCUtils.Application` starts this automatically, using options
from `:vc_utils, :finch_options`, which default to:

```elixir
config :vc_utils, :finch_options,
  name: VCUtils.HTTPClient.Finch,
  pools: %{
    default: [
      size: 1_000_000_000,
      start_pool_metrics?: true,
      conn_opts: [transport_opts: [verify: :verify_peer]]
    ]
  }
```

(`:verify_none` is used instead of `:verify_peer` in `:dev`/`:test`.)

Setting `:finch_options` **replaces** this default entirely, so keep
`name: VCUtils.HTTPClient.Finch` in your override — the adapter always routes requests
through that pool name.

Pools are keyed by `:default` (catch-all) or by `"scheme://host:port"`, so you can tune
settings per endpoint. For example, relaxing certificate verification for one internal
host while keeping strict verification everywhere else:

```elixir
config :vc_utils, :finch_options,
  name: VCUtils.HTTPClient.Finch,
  pools: %{
    default: [conn_opts: [transport_opts: [verify: :verify_peer]]],
    "https://internal.example.com" => [conn_opts: [transport_opts: [verify: :verify_none]]]
  }
```

Or giving a high-traffic partner API a bigger, sharded pool:

```elixir
config :vc_utils, :finch_options,
  name: VCUtils.HTTPClient.Finch,
  pools: %{
    default: [size: 50],
    "https://api.partner.com" => [size: 200, count: 4]
  }
```

Useful per-pool options:

* `:size` - connections per pool (HTTP/1 only; HTTP/2 pools are always a single
  multiplexed connection). Defaults to 50.
* `:count` - number of pools to start for that destination, for extra sharding under load.
  Defaults to 1.
* `:conn_opts` - passed to `Mint.HTTP.connect/4`, e.g. `transport_opts: [verify: :verify_peer]`
  for TLS verification, or `transport_opts: [timeout: 5_000]` for the connect timeout.
* `:protocols` - e.g. `[:http2]` to force HTTP/2 for a destination.
* `:start_pool_metrics?` - enables `Finch.get_pool_status/2` for that pool.

See [`Finch.start_link/1`](https://hexdocs.pm/finch/Finch.html#start_link/1) for the full
list of pool options.

#### Telemetry

Every request emits a `[:vc_utils, :http_client, :request]` telemetry event with
`%{duration: native_time_microseconds}` measurements and metadata
`%{module, method, url, body, headers, opts, status, response}`.

#### Mocking in tests

The adapter is just a module implementing the `VCUtils.HTTPClient` behaviour's
`request/5` callback, and it's selected per client via the `:adapter` config key — which
is exactly the seam [Mox](https://hexdocs.pm/mox) is built for.

Add `{:mox, "~> 1.0", only: :test}` to your deps, then define a mock for the behaviour
(e.g. in `test/support/mocks.ex`, loaded from `test/test_helper.exs`):

```elixir
Mox.defmock(MyApp.HTTPClientMock, for: VCUtils.HTTPClient)
```

Point the client at the mock in `config/test.exs`:

```elixir
config :vc_utils, MyApp.APIClient, adapter: MyApp.HTTPClientMock
```

Then set an expectation per test with `expect/4`, matching on whatever arguments your
client actually passes and returning the same shape a real adapter would
(`{:ok, %{status: ..., body: ...}}` or `{:error, reason}`) — `process_response/2` runs on
top of it exactly as it would for a live response:

```elixir
defmodule MyApp.APIClientTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "get_widget/1 returns the decoded response" do
    expect(MyApp.HTTPClientMock, :request, fn :get, url, nil, _headers, _opts ->
      assert url == "https://api.example.com/widgets/1"
      {:ok, %{status: 200, body: Jason.encode!(%{id: 1, name: "Widget"})}}
    end)

    assert {:ok, %{body: %{name: "Widget"}}} = MyApp.APIClient.get_widget(1)
  end
end
```

The adapter is called synchronously in the calling process — there's no `Task` or
message-passing involved — so Mox's default private mode works without needing
`Mox.allow/3` or `set_mox_global/1`, as long as the request happens in the test process
itself.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/vc_utils>.
