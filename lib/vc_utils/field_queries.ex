defmodule VCUtils.FieldQueries do
  @moduledoc """
    Field Queries

    Generates functions that add filters for fields provided in the call to the macro `defbyq`

    Take the example below;
    ``
      defmodule Identity.Accounts.User do
        use VCUtils.FieldQueries

        schema "users" do
          field :username, :string
          field(:first_name, :string)
          field(:last_name, :string)
          field(:other_names, :string)
          field(:email, :string)
          field(:msisdn, :string)

          timestamps()
          ...
        end

        defbyq([
          {:first_name, :search},
          :email,
          {:inserted_at, :date}
        ])

      end
    ``

    This implementation will yield the functions below

    ``
      # {:first_name, :search},
      def by_first_name_query(queryable \\ __MODULE__, field)
      def by_first_name_query(queryable, field) when field in ["", nil, []], do: queryable
      def by_first_name_query(queryable, field) do
        from(q in queryable, where: ilike(field(q, ^field), ^"%\#{field}%"))
      end

      # :email,
      def by_email_query(queryable \\ __MODULE__, field)
      def by_email_query(queryable, field) when field in ["", nil, []], do: queryable
      def by_email_query(queryable, field) do
        from(q in queryable, where: field(q, ^field) in ^fields)
      end
      def by_email_query(queryable, field), do: apply(__module__, :by_email_query, [[field]])

      # {:inserted_at, :date}
      def by_inserted_at_query(queryable \\ __MODULE__, start_and_end_dates)
      def by_inserted_at_query(queryable, %{start_date: nil, end_date: nil}), do: queryable
      def by_inserted_at_query(queryable, %{start_date: start_date, end_date: nil}) do
        from(q in queryable, where: field(q, ^field) >= ^start_date)
      end
      def by_inserted_at_query(queryable, %{start_date: nil, end_date: end_date}) do
        from(q in queryable, where: field(q, ^field) <= ^end_date)
      end
      def by_inserted_at_query(queryable, %{start_date: start_date, end_date: end_date}) do
        from(q in queryable,
          where: field(q, ^field) >= ^start_date,
          where: field(q, ^field) <= ^end_date
        )
      end
    ``

    Preloads

    Association preloads can also be defined with the macro `defpreloadq`, as in the example below:

    ``
      schema "users" do
        field :username, :string
        has_one :profile, MyApp.Profile
      end

      defpreloadq([:profile])
    ``

    ...this would define a function as follows.

    ``
      # :profile
      def preload_profile_query(queryable \\ __MODULE__, join_type)
          when join_type in [:cross, :full, :inner, :inner_lateral, :left, :left_lateral, :right] do
        queryable
        |> join(join_type, [q], f in assoc(q, unquote(field)), as: unquote(field))
        |> preload([q, {unquote(field), f}], [{unquote(field), f}])
      end
    ``
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

  defp define_field_funs({field, :date}) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, start_and_end_dates)

      def unquote(name)(queryable, start_and_end_dates) when start_and_end_dates in [nil, ""],
        do: queryable

      def unquote(name)(queryable, %{start_date: nil, end_date: nil}), do: queryable

      def unquote(name)(queryable, %{start_date: start_date, end_date: nil}) do
        from(q in queryable, where: field(q, ^unquote(field)) >= ^start_date)
      end

      def unquote(name)(queryable, %{start_date: nil, end_date: end_date}) do
        from(q in queryable, where: field(q, ^unquote(field)) <= ^end_date)
      end

      def unquote(name)(queryable, %{start_date: start_date, end_date: end_date}) do
        from(q in queryable,
          where: field(q, ^unquote(field)) >= ^start_date,
          where: field(q, ^unquote(field)) <= ^end_date
        )
      end
    end
  end

  defp define_field_funs({field, :search}) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, field)

      def unquote(name)(queryable, field) when field in ["", nil, []],
        do: queryable

      def unquote(name)(queryable, field) do
        from(q in queryable, where: ilike(field(q, ^unquote(field)), ^"%#{field}%"))
      end
    end
  end

  defp define_field_funs({field, :boolean}) when is_atom(field) do
    truthy_name = :"is_#{field}_query"
    falsy_name = :"is_not_#{field}_query"
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(truthy_name)(queryable \\ __MODULE__) do
        from(q in queryable, where: field(q, ^unquote(field)))
      end

      def unquote(falsy_name)(queryable \\ __MODULE__) do
        from(q in queryable, where: not field(q, ^unquote(field)))
      end

      def unquote(name)(queryable \\ __MODULE__, term) do
        case term do
          t when t in [true, "true"] -> apply(__ENV__.module, unquote(truthy_name), [queryable])
          t when t in [false, "false"] -> apply(__ENV__.module, unquote(falsy_name), [queryable])
          _ -> queryable
        end
      end
    end
  end

  defp define_field_funs(field) when is_atom(field) do
    name = :"by_#{field}_query"

    quote location: :keep do
      def unquote(name)(queryable \\ __MODULE__, field)

      def unquote(name)(queryable, field) when field in ["", nil, []],
        do: queryable

      def unquote(name)(queryable, [_ | _] = fields) do
        from(q in queryable, where: field(q, ^unquote(field)) in ^fields)
      end

      def unquote(name)(queryable, field),
        do: apply(__ENV__.module, unquote(name), [queryable, [field]])
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
