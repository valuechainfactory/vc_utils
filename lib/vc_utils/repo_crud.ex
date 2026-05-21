defmodule VCUtils.RepoCrud do
  @moduledoc """
  Repo CRUD Actions

  Generates functions that ease in repo CRUD operations

  Example:
  ```elixir
    defmodule User do
      use VCUtils.RepoCrud,
        repo: MyApp.Repo,
        read_only_repo: MyApp.RORepo, # optional - incase of a dedicated read only repo - cluster setup
        write_only_repo: MyApp.Repo # optional - `:repo` assumed to be write repo

      schema "users" do
        field :username, :string
        field :email, :string
        field :password, :string
        ...
      end

      # `def_crud` will define helper functions that will utilize the seperate ro and rw dbs if defined
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
    def modify(struct, attrs \\ %{}, opts \\ []) do
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
      @ro_repo unquote(opts[:read_only_repo] || opts[:repo])
      @rw_repo unquote(opts[:write_only_repo] || opts[:repo])
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
        |> @rw_repo.insert(opts)
      end

      def unquote(:"#{action}!")(struct \\ %__MODULE__{}, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @rw_repo.insert!(opts)
      end
    end
  end

  defp def_crud_action(:get = action) do
    quote location: :keep do
      def unquote(action)(id) do
        repo = if @ro_repo, do: @ro_repo, else: @repo
        repo.get(__MODULE__, id)
      end

      def unquote(:"#{action}!")(id) do
        repo = if @ro_repo, do: @ro_repo, else: @repo
        repo.get!(__MODULE__, id)
      end

      def unquote(:"#{action}_by")(attrs) when is_map(attrs) do
        repo = if @ro_repo, do: @ro_repo, else: @repo
        repo.get_by(__MODULE__, attrs)
      end

      def unquote(:all)(queryable \\ __MODULE__, opts \\ []) do
        repo = if @ro_repo, do: @ro_repo, else: @repo
        repo.all(queryable, opts)
      end

      def unquote(:one)(queryable \\ __MODULE__, opts \\ []) do
        repo = if @ro_repo, do: @ro_repo, else: @repo
        repo.one(queryable, opts)
      end
    end
  end

  defp def_crud_action(:modify = action) do
    quote location: :keep do
      def unquote(action)(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @rw_repo.update(opts)
      end

      def unquote(:"#{action}!")(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @rw_repo.update!(opts)
      end
    end
  end

  defp def_crud_action(:update = action) do
    quote location: :keep do
      @deprecated "Use :modify instead of :update"
      def unquote(action)(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @rw_repo.update(opts)
      end

      def unquote(:"#{action}!")(struct, attrs \\ %{}, opts \\ []) do
        struct
        |> __MODULE__.changeset(attrs)
        |> @rw_repo.update!(opts)
      end
    end
  end

  defp def_crud_action(:delete = action) do
    quote location: :keep do
      def unquote(action)(struct) when is_struct(struct), do: @rw_repo.delete(struct)

      def unquote(action)(structs) when is_list(structs),
        do: Enum.map(structs, &@rw_repo.delete(&1))

      def unquote(action)(queryable), do: @rw_repo.delete_all(queryable)
    end
  end
end
