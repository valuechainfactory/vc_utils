# VCUtils

Tools and helpers we constantly find repeated in most of our projects.

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
    request(:post, url, auth_headers(), params)
  end
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/vc_utils>.
