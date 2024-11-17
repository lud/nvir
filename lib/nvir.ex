defmodule Nvir do
  @moduledoc """
  Nvir is an environment variable loader and validator.

  Please refer to the [README](README.md#basic-usage) for usage instructions.
  """
  require Config

  @doc ~S"""
  Loads specified env files in the system environment. Intended usage is from
  `config/runtime.exs` in your project

  Variables defined in the files will not override the system environment
  if they are already defined. To override the system env, please list your
  files under an `:override` key.

  Files that do not exist are safely ignored.

  Valid values are
  * A single binary string (a file path).
  * A list of paths.
  * A keyword list where the key are:
    - An environment name such as `:dev` or `:test`.
    - `:*` That will match any environment.
    - `:override` which will declare the files as system overrides.

    Values in keywords can be strings, lists, and nested keywords.

  ### Examples

      import Config
      import Nvir

      # Load a single file
      dotenv!(".env")

      # Load multiple files
      dotenv!([".env", ".env.#{config_env()}"])

      # Load files depending on environment
      dotenv!(
        *: ".env",
        dev: ".env.dev",
        test: ".env.test"
      )

      # Load files with and without override
      dotenv!(
        dev: ".env",
        test: ".env", ".env.test",
        override: [test: ".env.test.local"]
      )
  """
  def dotenv!(sources) do
    env = guess_env()
    {regular, overrides} = env_sources(env, sources)

    preexisting_regular = System.get_env()

    added_regular =
      regular
      |> parse_all()
      |> merge_vars(:regular, preexisting_regular)

    preexisting_override = System.get_env()

    overrides =
      overrides
      |> parse_all()
      |> merge_vars(:override, preexisting_override)

    Map.merge(added_regular, overrides)
  end

  defp guess_env do
    # Unpredictable value for "no current env" that cannot match an atom
    not_found = make_ref()

    with ^not_found <- guess_env_config(not_found),
         ^not_found <- guess_env_mix(not_found) do
      not_found
    end
  end

  defp guess_env_config(not_found) do
    Config.config_env()
  rescue
    _ in RuntimeError -> not_found
  end

  defp guess_env_mix(not_found) do
    if Code.ensure_loaded?(Mix) do
      Mix.env()
    else
      not_found
    end
  end

  defp parse_all(files) do
    Enum.flat_map(files, fn file ->
      case parse_file(file) do
        {:ok, entries} -> [entries]
        {:error, :enoent} -> []
        {:error, %Nvir.ParseError{} = parse_error} -> raise parse_error
      end
    end)
  end

  defp parse_file(file) do
    with {:ok, content} <- File.read(file), do: Nvir.Parser.parse(content, file)
  end

  defp merge_vars(files_vars, :regular, sys_env) do
    to_add =
      for file_vars <- files_vars, {k, v} <- file_vars, reduce: %{} do
        to_add ->
          case Map.fetch(sys_env, k) do
            {:ok, _} -> to_add
            :error -> Map.put(to_add, k, build_value(v, sys_env, to_add))
          end
      end

    System.put_env(to_add)
    to_add
  end

  defp merge_vars(files_vars, :override, sys_env) do
    to_add =
      for file_vars <- files_vars, {k, v} <- file_vars, reduce: %{} do
        # On override, we pass (to_add, sys_env) instead of (sys_env, to_add),
        # so getting a variable will use the current overrides first.
        to_add -> Map.put(to_add, k, build_value(v, to_add, sys_env))
      end

    System.put_env(to_add)
    to_add
  end

  defp build_value(v, _, _) when is_binary(v), do: v

  defp build_value(f, sys_env, current_group_acc) when is_function(f, 1) do
    # If the getter returns :error, the parsed function will use an empty string
    # for the value.
    f.(fn key -> find_interpolation_value(key, sys_env, current_group_acc) end)
  end

  defp find_interpolation_value(key, store, fallback) do
    with :error <- Map.fetch(store, key), do: Map.fetch(fallback, key)
  end

  @doc false
  def env_sources(env, sources) do
    regular = collect_regular(sources, env, [])
    overrides = collect_overrides(sources, env, [])
    {regular, overrides}
  end

  # collect_regular
  #
  # Collects every source in the top list or under the current env or :*

  defp collect_regular(file, _, acc) when is_binary(file), do: [file | acc]

  if Mix.env() == :test do
    # support integers for tests, to check on ordering
    defp collect_regular(n, _, acc) when is_integer(n), do: [n | acc]
  end

  defp collect_regular([], _, acc), do: acc

  defp collect_regular([h | t], env, acc),
    do: collect_regular(h, env, collect_regular(t, env, acc))

  defp collect_regular({:*, sub}, env, acc), do: collect_regular(sub, env, acc)
  defp collect_regular({env, sub}, env, acc), do: collect_regular(sub, env, acc)
  defp collect_regular({_, _}, _, acc), do: acc

  # collect_overrides
  #
  # Skips any source that is not under an :override tuple, and delegates the
  # rest to collect_overrides_sub

  defp collect_overrides([h | t], env, acc) do
    collect_overrides(h, env, collect_overrides(t, env, acc))
  end

  defp collect_overrides({env, sub}, env, acc), do: collect_overrides(sub, env, acc)
  defp collect_overrides({:override, sub}, env, acc), do: collect_overrides_sub(sub, env, acc)
  defp collect_overrides({:*, sub}, env, acc), do: collect_overrides(sub, env, acc)
  defp collect_overrides(_, _env, acc), do: acc

  # collect_overrides_sub
  #
  # Collects any source, including under override tuples, for the given env or
  # :*.

  defp collect_overrides_sub(file, _env, acc) when is_binary(file), do: [file | acc]

  defp collect_overrides_sub([h | t], env, acc),
    do: collect_overrides_sub(h, env, collect_overrides_sub(t, env, acc))

  defp collect_overrides_sub([], _env, acc), do: acc
  defp collect_overrides_sub({env, sub}, env, acc), do: collect_overrides_sub(sub, env, acc)
  defp collect_overrides_sub({:override, sub}, env, acc), do: collect_overrides_sub(sub, env, acc)
  defp collect_overrides_sub({:*, sub}, env, acc), do: collect_overrides_sub(sub, env, acc)
  defp collect_overrides_sub({_, _}, _, acc), do: acc

  if Mix.env() == :test do
    # support integers for tests, to check on ordering
    defp collect_overrides_sub(n, _, acc) when is_integer(n), do: [n | acc]
  end

  @doc """
  Returns the value of the given `var`, transformed and validated by the given
  `caster`.

  Raises if the variable is not defined or if the caster validation fails.

  Please see the [README](README.md#available-casters) for available casters.
  """
  def env!(var, caster) do
    case env(var, caster) do
      {:ok, value} -> value
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Returns the value of the given `var`, transformed and validated by the given
  `caster`.

  Returns the `default` value if the variable is not defined.

  Raises if the caster validation fails.

  Please see the [README](README.md#available-casters) for available casters.
  """
  def env!(var, caster, default) do
    case env(var, caster, default) do
      {:ok, value} -> value
      {:error, reason} -> raise reason
    end
  end

  @doc false
  def env(var, caster) do
    case System.fetch_env(var) do
      {:ok, value} -> cast(var, value, caster)
      :error -> {:error, %System.EnvError{env: var}}
    end
  end

  @doc false
  def env(var, caster, default) do
    case System.fetch_env(var) do
      {:ok, value} -> cast(var, value, caster)
      :error -> {:ok, default}
    end
  end

  defp cast(var, value, caster) do
    case cast(value, caster) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, cast_error(var, caster, reason)}
    end
  end

  defdelegate cast(value, caster), to: Nvir.Cast

  defp cast_error(var, caster, reason) do
    %Nvir.CastError{var: var, caster: caster, reason: reason}
  end
end
