defmodule VCUtils.FieldQueries do
  @moduledoc """
    # Field Queries

    Provides macros to generate query functions for filtering by fields and preloading associations.

    ## Overview

    This module adds two primary macros:

    - `defbyq/1`: Generates query functions for filtering by fields with various conditions
    - `defpreloadq/1`: Generates query functions for preloading associations with joins

    The generated functions can be used for building complex queries with minimal boilerplate.

    ## Named Bindings Support

    Version 2.0 adds support for named bindings, allowing you to:

    - Filter by fields in joined associations
    - Create more maintainable and flexible queries
    - Combine multiple filters across related schemas

    ## Basic Usage

    First, include this module in your schema:

    ```elixir
    defmodule MyApp.Accounts.User do
      use VCUtils.FieldQueries
      # ... rest of your schema
    end
    ```

    ### Defining Field Queries

    Use the `defbyq/1` macro to define query functions for your fields:

    ```elixir
    defmodule MyApp.Accounts.User do
      use VCUtils.FieldQueries
      use Ecto.Schema

      schema "users" do
        field :first_name, :string
        field :last_name, :string
        field :email, :string
        field :active, :boolean
        field :joined_on, :date
        has_one :profile, MyApp.Accounts.Profile

        timestamps()
      end

      # Define query functions for these fields
      defbyq([
        {:first_name, :search},  # String search with LIKE
        :email,                  # Standard equality matching
        {:active, :boolean},     # Boolean field
        {:joined_on, :date}      # Date range queries
      ])

      # Define preload query for association
      defpreloadq([:profile])
    end
    ```

    ### Generated Functions

    For each field in `defbyq`, corresponding query functions will be generated:

    #### Standard Field (e.g., `:email`)

    ```elixir
    # Single value
    User.by_email_query("john@example.com")
    # Multiple values
    User.by_email_query(["john@example.com", "jane@example.com"])
    ```

    #### Search Field (e.g., `{:first_name, :search}`)

    ```elixir
    # Generates a LIKE query with wildcards
    User.by_first_name_query("john")  # WHERE first_name LIKE '%john%'
    ```

    #### Boolean Field (e.g., `{:active, :boolean}`)

    ```elixir
    # Generic query with any boolean value
    User.by_active_query(true)
    User.by_active_query(false)

    # Specific queries for true/false
    User.is_active_query()
    User.is_not_active_query()
    ```

    #### Date Field (e.g., `{:joined_on, :date}`)

    ```elixir
    # Between two dates
    User.by_joined_on_query(%{start_date: ~D[2023-01-01], end_date: ~D[2023-12-31]})

    # From a date onwards
    User.by_joined_on_query(%{start_date: ~D[2023-01-01], end_date: nil})

    # Until a date
    User.by_joined_on_query(%{start_date: nil, end_date: ~D[2023-12-31]})
    ```

    ### Preload Queries

    For each association in `defpreloadq`, a preload query function will be generated with a named binding:

    ```elixir
    # Preload profile with an inner join using named binding :profile
    User.preload_profile_query(:inner)
    ```

    ## Using Named Bindings

    The real power comes when combining queries with named bindings:

    ```elixir
    defmodule MyApp.Accounts.Profile do
      use VCUtils.FieldQueries
      use Ecto.Schema

      schema "profiles" do
        field :bio, :string
        field :theme, :string
        field :locale, :string
        belongs_to :user, MyApp.Accounts.User

        timestamps()
      end

      defbyq([
        {:theme, :search},
        :locale
      ])
    end
    ```

    Now you can filter on joined associations using the named binding:

    ```elixir
    # Find users with emails matching "example.com" who have a "dark" theme
    # in their profile
    query =
      User
      |> User.by_email_query("example.com")
      |> User.preload_profile_query(:inner)
      |> Profile.by_theme_query("dark", :profile)
      |> Repo.all()
    ```

    The third parameter to any query function is an optional named binding.
    When provided, the filter applies to the field from the associated schema
    instead of the primary schema.

    ## Complete Example

    ```elixir
    # Schemas
    defmodule MyApp.Blog.Post do
      use VCUtils.FieldQueries
      use Ecto.Schema

      schema "posts" do
        field :title, :string
        field :body, :text
        field :published, :boolean
        field :published_at, :utc_datetime

        belongs_to :author, MyApp.Accounts.User
        has_many :comments, MyApp.Blog.Comment

        timestamps()
      end

      defbyq([
        {:title, :search},
        {:published, :boolean},
        {:published_at, :date}
      ])

      defpreloadq([:author, :comments])
    end

    defmodule MyApp.Blog.Comment do
      use VCUtils.FieldQueries
      use Ecto.Schema

      schema "comments" do
        field :content, :text
        field :approved, :boolean

        belongs_to :post, MyApp.Blog.Post
        belongs_to :user, MyApp.Accounts.User

        timestamps()
      end

      defbyq([
        {:content, :search},
        {:approved, :boolean}
      ])
    end

    # Query Example: Find all published posts with approved comments
    # containing the word "awesome"
    query =
      Post
      |> Post.is_published_query()
      |> Post.preload_comments_query(:inner)
      |> Comment.is_approved_query(:comments)
      |> Comment.by_content_query("awesome", :comments)
      |> Repo.all()
    ```

    ## How It Works

    The `defbyq` macro generates functions that append `where` clauses to your queries.

    The `defpreloadq` macro generates functions that join and preload the specified association
    with a named binding. This named binding can then be used in subsequent query functions.

    All generated functions follow a standard pattern:

    - They accept an optional Ecto queryable as the first parameter
    - They return a query that can be further composed
    - Functions from `defbyq` support an optional binding parameter to target joined schemas
  """
  import Ecto.Query

  defmacro __using__(_opts) do
    quote location: :keep do
      import Ecto.Query, only: [from: 2]
      import VCUtils.FieldQueries
    end
  end

  defmacro defbyq(fields) do
    # Check __schema__ functions in https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection for field/type info
    for field <- fields, do: define_field_funs(field)
  end

  # For date fields with optional binding
  defp define_field_funs({field, :date}) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      # Without binding (uses default binding)
      def unquote(name)(queryable \\ __MODULE__, start_and_end_dates, binding \\ nil)

      def unquote(name)(queryable, start_and_end_dates, _binding)
          when start_and_end_dates in [nil, ""],
          do: queryable

      def unquote(name)(queryable, %{start_date: nil, end_date: nil}, _binding), do: queryable

      def unquote(name)(queryable, %{start_date: start_date, end_date: nil}, nil) do
        from(q in queryable, where: field(q, ^unquote(field)) >= ^start_date)
      end

      def unquote(name)(queryable, %{start_date: nil, end_date: end_date}, nil) do
        from(q in queryable, where: field(q, ^unquote(field)) <= ^end_date)
      end

      def unquote(name)(queryable, %{start_date: start_date, end_date: end_date}, nil) do
        from(q in queryable,
          where: field(q, ^unquote(field)) >= ^start_date,
          where: field(q, ^unquote(field)) <= ^end_date
        )
      end

      # With named binding
      def unquote(name)(queryable, %{start_date: start_date, end_date: nil}, binding)
          when is_atom(binding) do
        from(q in queryable, where: field(as(^binding), ^unquote(field)) >= ^start_date)
      end

      def unquote(name)(queryable, %{start_date: nil, end_date: end_date}, binding)
          when is_atom(binding) do
        from(q in queryable, where: field(as(^binding), ^unquote(field)) <= ^end_date)
      end

      def unquote(name)(queryable, %{start_date: start_date, end_date: end_date}, binding)
          when is_atom(binding) do
        from(q in queryable,
          where: field(as(^binding), ^unquote(field)) >= ^start_date,
          where: field(as(^binding), ^unquote(field)) <= ^end_date
        )
      end
    end
  end

  # For search fields with optional binding
  defp define_field_funs({field, :search}) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, field, binding \\ nil)

      def unquote(name)(queryable, field, _binding) when field in ["", nil, []],
        do: queryable

      # Without binding (uses default binding)
      def unquote(name)(queryable, field, nil) do
        from(q in queryable, where: ilike(field(q, ^unquote(field)), ^"%#{field}%"))
      end

      # With named binding
      def unquote(name)(queryable, field, binding) when is_atom(binding) do
        from(q in queryable, where: ilike(field(as(^binding), ^unquote(field)), ^"%#{field}%"))
      end
    end
  end

  # For boolean fields with optional binding
  defp define_field_funs({field, :boolean}) when is_atom(field) do
    truthy_name = :"is_#{field}_query"
    falsy_name = :"is_not_#{field}_query"
    name = :"by_#{field}_query"

    quote location: :keep do
      # Without binding
      def unquote(truthy_name)(queryable \\ __MODULE__, binding \\ nil)

      def unquote(truthy_name)(queryable, nil) do
        from(q in queryable, where: field(q, ^unquote(field)))
      end

      def unquote(truthy_name)(queryable, binding) when is_atom(binding) do
        from(q in queryable, where: field(as(^binding), ^unquote(field)))
      end

      def unquote(falsy_name)(queryable \\ __MODULE__, binding \\ nil)

      def unquote(falsy_name)(queryable, nil) do
        from(q in queryable, where: not field(q, ^unquote(field)))
      end

      def unquote(falsy_name)(queryable, binding) when is_atom(binding) do
        from(q in queryable, where: not field(as(^binding), ^unquote(field)))
      end

      def unquote(name)(queryable \\ __MODULE__, term, binding \\ nil) do
        case term do
          t when t in [true, "true"] ->
            apply(__ENV__.module, unquote(truthy_name), [queryable, binding])

          t when t in [false, "false"] ->
            apply(__ENV__.module, unquote(falsy_name), [queryable, binding])

          _ ->
            queryable
        end
      end
    end
  end

  # For standard fields with optional binding
  defp define_field_funs(field) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, field, binding \\ nil)

      def unquote(name)(queryable, field, _binding) when field in ["", nil, []],
        do: queryable

      # Without binding
      def unquote(name)(queryable, [_ | _] = fields, nil) do
        from(q in queryable, where: field(q, ^unquote(field)) in ^fields)
      end

      def unquote(name)(queryable, field, nil) do
        from(q in queryable, where: field(q, ^unquote(field)) == ^field)
      end

      # With named binding
      def unquote(name)(queryable, [_ | _] = fields, binding) when is_atom(binding) do
        from(q in queryable, where: field(as(^binding), ^unquote(field)) in ^fields)
      end

      def unquote(name)(queryable, field, binding) when is_atom(binding) do
        from(q in queryable, where: field(as(^binding), ^unquote(field)) == ^field)
      end
    end
  end

  defmacro defpreloadq(fields) do
    for field <- fields, do: define_preload_funs(field)
  end

  defp define_preload_funs(field) when is_atom(field) do
    name = :"preload_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, join_type)
          when join_type in [:cross, :full, :inner, :inner_lateral, :left, :left_lateral, :right] do
        queryable
        |> join(join_type, [q], f in assoc(q, unquote(field)), as: unquote(field))
        |> preload([q, {unquote(field), f}], [{unquote(field), f}])
      end
    end
  end
end
