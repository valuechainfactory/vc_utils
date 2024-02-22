defmodule VCUtils.RepoCrud do
  @moduledoc """
  Repo CRUD Actions

  Generates functions that ease in repo CRUD operations

  Example:
  ```elixir
    defmodule User do
      use Utils.RepoCrud, repo: MyApp.Repo

      schema "users" do
        field :username, :string
        field :email, :string
        field :password, :string
        ...
      end

      def_crud([
        :create,
        :get,
        :modify,
        :delete
      ])
    end
  ```

  This implementations yields the functions below

  ```elixir
    # create
    def create(struct \\ %__MODULE__{}, attrs \\ %{} ) do
      struct
      |> __MODULE__.changeset(attrs)
      |> Repo.insert()
    end

    # get
    def get(id) do
      Repo.get(__MODULE__, id)
    end

    def get!(id) do
      Repo.get!(__MODULE__, id)
    end

    # modify
    def modify(struct, attrs \\ %{}, otps \\ []) do
      struct
      |> __MODULE__.changeset(attrs)
      |> Repo.update(opts)
    end

    # delete
    def delete(struct) when is_struct(struct), do: Repo.delete(struct)
    def delete(structs) when is_list(structs), do: Repo.delete_all(structs)
  ```
  """

  defmacro __using__(opts) do
    quote location: :keep do
      @repo unquote(opts[:repo])
      import VCUtils.RepoCrud
    end
  end

  defmacro def_crud(actions) do
    for action <- actions, do: def_crud_action(action)
  end

  defp def_crud_action(:create = action) do
    quote location: :keep do
      def unquote(action)(struct \\ %__MODULE__{}, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.insert(opts)
      end

      def unquote(:"#{action}!")(struct \\ %__MODULE__{}, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.insert!(opts)
      end
    end
  end

  defp def_crud_action(:get = action) do
    quote location: :keep do
      def unquote(action)(id), do: @repo.get(__MODULE__, id)
      def unquote(:"#{action}!")(id), do: @repo.get!(__MODULE__, id)
      def unquote(:"#{action}_by")(attrs) when is_map(attrs), do: @repo.get_by(__MODULE__, attrs)
    end
  end

  defp def_crud_action(:modify = action) do
    quote location: :keep do
      def unquote(action)(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.update(opts)
      end

      def unquote(:"#{action}!")(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.update!(opts)
      end
    end
  end

  defp def_crud_action(:update = action) do
    quote location: :keep do
      @deprecated "User :modify instead of :update"
      def unquote(action)(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.update(opts)
      end

      def unquote(:"#{action}!")(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @repo.update!(opts)
      end
    end
  end

  defp def_crud_action(:delete = action) do
    quote location: :keep do
      def unquote(action)(struct) when is_struct(struct), do: @repo.delete(struct)
      def unquote(action)(structs) when is_list(structs), do: @repo.delete_all(structs)
    end
  end
end
