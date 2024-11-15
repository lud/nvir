defmodule Nvir.Cast do
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
  def cast(value, :boolean?), do: cast(value, :boolean)

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
  def cast(value, :integer), do: cast(value, :integer!)

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
  def cast(value, :float), do: cast(value, :float!)

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
end
