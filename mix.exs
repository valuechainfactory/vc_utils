defmodule VCUtils.MixProject do
  use Mix.Project

  def project do
    [
      app: :vc_utils,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VCUtils.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      # -----

      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.19"},
      {:timex, "~> 3.7"}
    ]
  end
end
