defmodule Nvir.Cast do
  @moduledoc """
  Collection of casters for environment variables.
  """

  @type caster ::
          :string
          | :string?
          | :string!
          | :atom
          | :atom?
          | :atom!
          | :existing_atom
          | :existing_atom?
          | :existing_atom!
          | :boolean
          | :boolean!
          | :boolean?
          | :integer!
          | :integer?
          | :integer
          | :float!
          | :float?
          | :float
          | (term -> result)
  @type result ::
          {:ok, term}
          | {:error, String.t()}
          | {:error, :empty}
          | {:error, :bad_cast}
  @spec cast(term, caster) :: result

  @external_resource "guides/var-reading/the-env-functions.md"

  @doc """
  Casts the given value to the desired type.

  Environment variables are always defined as a string. Thus, the `cast/2`
  function will only accept strings for the `value` argument.

  Accepts a built-in caster or a custom function returning `{:ok, value}` or
  `{:error, String.t()}`. You may as well directly return an error tuple from a
  recursive `cast/2` call.

  The list of built-in casters is described in the [reading environment
  variables](guides/var-reading/the-env-functions.md#built-in-casters) guide.
  """
  @spec cast(String.t(), caster) :: result
  def cast(value, caster)

  # -- String -----------------------------------------------------------------

  def cast(value, :string), do: {:ok, value}

  def cast("", :string?), do: {:ok, nil}
  def cast(value, :string?), do: cast(value, :string)

  def cast("", :string!), do: {:error, :empty}
  def cast(value, :string!), do: cast(value, :string)

  # -- Atom -------------------------------------------------------------------

  # :atom converts everything
  def cast(value, :atom), do: {:ok, String.to_atom(value)}

  # :atom? converts "" to nil
  def cast("", :atom?), do: {:ok, nil}
  def cast(value, :atom?), do: {:ok, String.to_atom(value)}

  # :atom! rejects ""
  def cast("", :atom!), do: {:error, :empty}
  def cast(value, :atom!), do: cast(value, :atom)

  # :existing_atom rejects non existing atoms
  def cast(value, :existing_atom) do
    {:ok, String.to_existing_atom(value)}
  rescue
    _ in ArgumentError -> {:error, :bad_cast}
  end

  # :existing_atom? converts "" to nil
  def cast("", :existing_atom?), do: {:ok, nil}
  def cast(value, :existing_atom?), do: cast(value, :existing_atom)

  def cast("", :existing_atom!), do: {:error, :empty}
  def cast(value, :existing_atom!), do: cast(value, :existing_atom)

  # -- Boolean ----------------------------------------------------------------

  def cast(value, :boolean) do
    case String.downcase(value) do
      "" -> {:ok, false}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      _ -> {:ok, true}
    end
  end

  def cast(value, :boolean!) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      _ -> {:error, :bad_cast}
    end
  end

  # legacy
  def cast(value, :boolean?), do: warn_cast(value, :boolean?, :boolean)

  # -- Integer ----------------------------------------------------------------

  def cast("", :integer!), do: {:error, :empty}

  def cast(value, :integer!) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_cast}
    end
  end

  def cast("", :integer?), do: {:ok, nil}
  def cast(value, :integer?), do: cast(value, :integer!)

  # legacy
  def cast(value, :integer), do: warn_cast(value, :integer, :integer!)

  # -- Float ------------------------------------------------------------------

  def cast("", :float!), do: {:error, :empty}

  def cast(value, :float!) do
    case Float.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_cast}
    end
  end

  def cast("", :float?), do: {:ok, nil}
  def cast(value, :float?), do: cast(value, :float!)

  # legacy
  def cast(value, :float), do: warn_cast(value, :float, :float!)

  # -- Callback ---------------------------------------------------------------

  def cast(value, fun) when is_function(fun, 1) do
    case fun.(value) do
      {:ok, casted} ->
        {:ok, casted}

      {:error, errmsg} when is_binary(errmsg) ->
        {:error, errmsg}

      # Allow custom casters to return errors from other casts from this
      # module.
      {:error, :empty} = err ->
        err

      {:error, :bad_cast} = err ->
        err

      other ->
        raise "invalid return value from custom validator #{inspect(fun)}, expected result tuple but got: #{inspect(other)}"
    end
  end

  # -- Unknown ----------------------------------------------------------------

  def cast(_, other) do
    raise ArgumentError, "unknown cast type: #{inspect(other)}"
  end

  defp warn_cast(value, deprecated, replacement) do
    if Process.get(:nvir_deprecated_cast_warn, true) do
      IO.warn(
        "Environment variable caster #{inspect(deprecated)} is deprecated, use #{inspect(replacement)} instead."
      )
    end

    cast(value, replacement)
  end

  @doc false
  def ignore_warnings do
    Process.put(:nvir_deprecated_cast_warn, false)
  end
end
