defmodule Nvir do
  require Config

  @moduledoc """
  This is the main API for Nvir, an environment variable loader and validator.

  The most useful documentation is generally:

  * The [README](README.md#basic-usage) for usage instructions.
  * The `dotenv!/1` function.
  """

  @enforce_keys [:enabled_sources]
  defstruct enabled_sources: %{},
            parser: Nvir.Parser.DefaultParser,
            cd: nil,
            before_env_set: nil

  @type t :: %__MODULE__{enabled_sources: %{atom => boolean}, parser: module, cd: nil | Path.t()}
  @type source :: binary | {atom, source} | [source]
  @type sources :: source | [sources] | {atom, sources}
  @type var_def :: {String.t(), String.t()}
  @type transformer :: (var_def -> var_def)
  @type config_opt ::
          {:enabled_sources, %{atom => boolean}}
          | {:parser, module}
          | {:cd, nil | Path.t()}
          | {:before_env_set, transformer}

  @doc """
  Returns a configuration for `dotenv!/2` without any enabled source.

  Generally this is used for custom loading strategies, see `dotenv_loader/0` to
  use reasonable defaults.
  """
  @spec dotenv_new :: t
  def dotenv_new do
    %__MODULE__{enabled_sources: %{}}
  end

  @doc """
  Returns the default configuration for the `dotenv!/2` function.

  ### Examples

  Implement loading a custom `:docs` environment:

      import Config
      import Nvir

      dotenv_loader()
      |> dotenv_enable_source(:docs, config_env() == :docs)
      |> dotenv!(
        docs: ".env.docs",
        dev: ".env.dev",
        test: ".env.test"
      )
  """
  @spec dotenv_loader :: t
  def dotenv_loader do
    dotenv_configure(dotenv_new(), enabled_sources: default_dotenv_sources())
  end

  @doc """
  Returns the sources enabled by default when using `dotenv/1` or
  `dotenv_loader/0`. The value changes dynamically depending on the current
  environment and operating system.

  See the "Predefined tags" section on the `dotenv!/1` documentation.
  """
  def default_dotenv_sources do
    defaults = %{}

    defaults =
      case guess_env() do
        {:ok, env} when env in [:dev, :test] -> Map.put(defaults, env, true)
        _ -> defaults
      end

    defaults =
      Enum.reduce(ci_checks(), defaults, fn {tag, var}, acc ->
        if System.get_env(var) == "true" do
          Map.put(acc, tag, true)
        else
          acc
        end
      end)

    defaults =
      case :os.type() do
        {:unix, :linux} -> Map.put(defaults, :linux, true)
        {:win32, _} -> Map.put(defaults, :windows, true)
        _ -> defaults
      end

    defaults
  end

  @doc false
  @deprecated "Use `default_dotenv_sources/0`"
  def default_enabled_sources do
    default_dotenv_sources()
  end

  defp guess_env do
    with :error <- guess_env_config() do
      guess_env_mix()
    end
  end

  defp guess_env_config do
    {:ok, Config.config_env()}
  rescue
    _ in RuntimeError -> :error
  end

  defp guess_env_mix do
    if Code.ensure_loaded?(Mix) do
      {:ok, Mix.env()}
    else
      :error
    end
  end

  defp ci_checks do
    %{
      ci: "CI",
      ci@github: "GITHUB_ACTIONS",
      ci@travis: "TRAVIS",
      ci@circle: "CIRCLECI",
      ci@gitlab: "GITLAB_CI"
    }
  end

  @doc """
  Updates the given configuration with the given options.

  The options are not merged.

  ### Options

  * `:enabled_sources` - A map of `%{atom => boolean}` values to declare which
    source tags will be enabled when collecting sources. Defaults to the return
    value of `default_enabled_sources/0`.
  * `:parser` - The module to parse environment variables files. Defaults to
    `Nvir.Parser.RDB`.
  * `:cd` - A directory path to load relative source paths from.
  * `:before_env_set` - A function that accepts a `{varname, value}` tuple and
    must return a similar tuple. This gives the possibility to change or
    transform the parsed variables before the environment is altered. Returned
    `varname` and `value` must implement the `String.Chars` protocol. Returning
    `nil` as a value will delete the environment variable.

  ### Example

  Implement loading a custom `:docs` environment and load a file when running a
  release:

      import Nvir

      dotenv_loader()
      |> dotenv_configure(
        enabled_sources: %{
          # Enable sources tagged with :docs depending on an environment variable
          docs: System.get_env("MIX_ENV") == "docs",

          # Enable sources tagged with :rel when running a release
          rel: env!("RELEASE_NAME", :boolean, false)
        },

        # Load dotenv files relative to this directory
        cd: "~/projects/apps/envs"
      )
      |> dotenv!(
        docs: ".env.docs",
        rel: "releases.env",
        dev: ".env.dev",
        test: ".env.test"
      )
  """
  @spec dotenv_configure(t, [config_opt]) :: t
  def dotenv_configure(nvir, opts) do
    struct!(nvir, Map.new(opts, &validate_opt!/1))
  end

  defp validate_opt!({k, v} = opt) do
    if valid_opt?(opt) do
      opt
    else
      raise(ArgumentError, "invalid dotenv option: #{inspect({k, v})}")
    end
  end

  defp valid_opt?({:enabled_sources, flags}) do
    (is_list(flags) or is_map(flags)) and
      Enum.all?(flags, fn
        {:overwrite, _} ->
          raise ArgumentError, "changing the :overwrite tag is not allowed"

        {k, v} ->
          is_atom(k) and is_boolean(v)

        _ ->
          false
      end)
  end

  defp valid_opt?({:parser, module}) do
    is_atom(module)
  end

  defp valid_opt?({:cd, dir}) do
    is_binary(dir) or is_nil(dir) or is_list(dir)
  end

  defp valid_opt?({:before_env_set, fun}) do
    is_function(fun, 1)
  end

  defp valid_opt?(_other) do
    false
  end

  @doc """
  Enables or disables environment variable sources under the given tag.

  For instance, the following call will load both files:

      Nvir.dotenv_loader()
      |> Nvir.enable_sources(:custom, true)
      |> Nvir.dotenv!(["global.env", custom: "local.env"])

  Whereas the following call will only load files that are not wrapped in a tag.

      Nvir.dotenv_loader()
      |> Nvir.dotenv!(["global.env", custom: "local.env"])

  It is also possible to disable some defaults by overriding them. In the
  following code, the `.env.test` file will never be loaded:

      Nvir.dotenv_loader()
      |> Nvir.enable_sources(:test, false)
      |> Nvir.dotenv!(["global.env", dev: ".env.dev", test: ".env.test"])

  """
  def dotenv_enable_sources(nvir, tag, enabled?) when is_atom(tag) and is_boolean(enabled?) do
    dotenv_configure(nvir, enabled_sources: Map.put(nvir.enabled_sources, tag, enabled?))
  end

  @deprecated "Use `dotenv_enable_sources/3`"
  @doc false
  def enable_sources(nvir, tag, enabled?) when is_atom(tag) and is_boolean(enabled?) do
    dotenv_enable_sources(nvir, tag, enabled?)
  end

  @doc """
  Like `dotenv_enable_sources/3` but accepts a keyword list or map of sources.

      Nvir.dotenv_loader()
      |> Nvir.dotenv_enable_source(
        custom: true,
        docs: config_env() == :docs
      )
      |> Nvir.dotenv!(["global.env", custom: "local.env", docs: "docs.env"])
  """
  def dotenv_enable_sources(nvir, enum) when is_list(enum) when is_map(enum) do
    dotenv_configure(nvir, enabled_sources: Map.merge(nvir.enabled_sources, Map.new(enum)))
  end

  @deprecated "Use `dotenv_enable_sources/2`"
  @doc false
  def enable_sources(nvir, enum) when is_list(enum) when is_map(enum) do
    dotenv_enable_sources(nvir, enum)
  end

  @doc """
  Loads specified dotenv files in the system environment. Intended usage is from
  `config/runtime.exs` in your project

  Variables defined in the files will not overwrite the system environment if
  they are already defined. To overwrite the system env, please list your files
  under an `:overwrite` key.

  This function takes multiple sources and will select the sources to actually
  load based on system properties.

  Valid sources are:

  * A string, this is an actual file that we want to load.
  * A `{tag, value}` tuple where the tag is an atom and the value is a source.
    Predefined tags are listed below. Additional tags can be defined with
    `enable_sources/3`.
  * A list of sources. So a keyword list is a valid source, _i.e._ a list of
    tagged tuples.

  Files are loaded in order of appearance, in two phases:

  * First, files that are not wrapped in an `:overwrite` tagged tuple.
  * Then files that are wrapped in such tuples.

  Files that do not exist are safely ignored.

  ### Examples

      import Config
      import Nvir

      # Load a single file
      dotenv!(".env")

      # Load multiple files
      dotenv!([".env", ".env.\#{config_env()}"])

      # Load files depending on environment
      dotenv!(
        dev: ".env.dev",
        test: ".env.test"
      )

      # Load files with and without overwrite
      dotenv!(
        dev: ".env",
        test: [".env", ".env.test"],
        overwrite: [test: ".env.test.local"]
      )

      # Overwrite the system with all existing files
      dotenv!(
        overwrite: [
          dev: ".env",
          test: [".env", ".env.test", ".env.test.local"]
        ]
      )

      # Totally useless but valid :)
      dotenv!(test: [test: [test: ".env.test"]])
      # Same without wrapping the tuples in lists
      dotenv!({:test, {:test, {:test, ".env.test"}}})

      # This will not load the file as `:test` and `:dev` will not be
      # enabled at the same time
      dotenv!(dev: [test: ".env.test"])

  ### Predefined tags

  Tags are enabled under different circumstances.

  #### Mix environment

  * `:dev` - When `Config.config_env()` or `Mix.env()` is `:dev`.
  * `:test` - When `Config.config_env()` or `Mix.env()` is `:test`.

  There is no predefined tag for `:prod` as using dotenv files in production is
  strongly discouraged.

  #### Continuous integration

  * `:ci` - When the `CI` environment variable is `"true"`.
  * `:ci@github` - When the `GITHUB_ACTIONS` environment variable is `"true"`.
  * `:ci@travis` - When the `TRAVIS` environment variable is `"true"`.
  * `:ci@circle` - When the `CIRCLECI` environment variable is `"true"`.
  * `:ci@gitlab` - When the `GITLAB_CI` environment variable is `"true"`.

  #### Operating system

  * `:linux` - On Linux machines.
  * `:windows` - On Windows machines.
  * `:darwin` - On MacOS machines.
  """
  @spec dotenv!(sources) :: %{binary => binary}
  def dotenv!(sources) do
    dotenv!(dotenv_loader(), sources)
  end

  @doc """
  Same as `dotenv!/1` but accepts a custom configuration to load dotenv files.
  """
  @spec dotenv!(t, sources) :: %{binary => binary}
  def dotenv!(nvir, sources) do
    {regular, overwrites} = collect_sources(nvir, sources)

    existing_vars = System.get_env()
    parsed_regular = load_files(nvir, regular)
    to_add_regular = build_vars_regular(parsed_regular, existing_vars)
    transformed_regular = before_env_set(nvir.before_env_set, to_add_regular)

    existing_vars_1 = Map.merge(existing_vars, transformed_regular)

    parsed_overwrites = load_files(nvir, overwrites)
    to_add_overwrites = build_vars_overwrite(parsed_overwrites, existing_vars_1)
    transformed_overwrites = before_env_set(nvir.before_env_set, to_add_overwrites)

    to_add = Map.merge(transformed_regular, transformed_overwrites)
    :ok = System.put_env(to_add)

    to_add
  end

  @doc false
  @spec collect_sources(t, sources) :: {sources, sources}
  def collect_sources(nvir, sources) do
    %{enabled_sources: enabled} = nvir

    {_regular, _overwrites} =
      sources
      # source order is reversed on collection
      |> collect_sources([], [])
      # and reversed again on filtering
      |> filter_sources(enabled)
  end

  defp collect_sources(list, rev_prefix, accin) when is_list(list) do
    Enum.reduce(list, accin, fn sub, acc -> collect_sources(sub, rev_prefix, acc) end)
  end

  defp collect_sources({tag, sub}, rev_prefix, acc) do
    collect_sources(sub, [tag | rev_prefix], acc)
  end

  defp collect_sources(file, rev_prefix, acc) when is_binary(file) do
    [{rev_prefix, file} | acc]
  end

  defp filter_sources(tagged_sources, enabled) do
    Enum.reduce(tagged_sources, {[], []}, fn {tags, file}, {regular_acc, overwrite_acc} ->
      case match_tags(tags, enabled, :regular) do
        :overwrite -> {regular_acc, [file | overwrite_acc]}
        :regular -> {[file | regular_acc], overwrite_acc}
        :ignore -> {regular_acc, overwrite_acc}
      end
    end)
  end

  defp match_tags([], _enabled, kind) do
    kind
  end

  defp match_tags([:overwrite | t], enabled, _kind) do
    match_tags(t, enabled, :overwrite)
  end

  defp match_tags([h | t], enabled, kind) when :erlang.map_get(h, enabled) do
    match_tags(t, enabled, kind)
  end

  defp match_tags(_, _, _) do
    :ignore
  end

  defp load_files(nvir, files) do
    %{parser: parser, cd: cd} = nvir

    Enum.flat_map(files, fn file ->
      path = expand_path(file, cd)

      case load_file(path, parser) do
        {:ok, entries} ->
          [entries]

        {:error, :enoent} ->
          []

        {:error, parse_error} ->
          raise Nvir.LoadError, reason: parse_error, path: path
      end
    end)
  end

  defp expand_path(file, nil) do
    file
  end

  defp expand_path(file, cd) do
    Path.expand(file, cd)
  end

  defp load_file(path, parser) do
    if File.regular?(path) do
      parser.parse_file(path)
    else
      {:error, :enoent}
    end
  end

  defp build_vars_regular(files_vars, sys_env) do
    to_add =
      for file_vars <- files_vars, {k, v} <- file_vars, reduce: %{} do
        to_add ->
          case Map.fetch(sys_env, k) do
            {:ok, _} -> to_add
            :error -> Map.put(to_add, k, build_value(v, sys_env, to_add))
          end
      end

    to_add
  end

  defp build_vars_overwrite(files_vars, sys_env) do
    to_add =
      for file_vars <- files_vars, {k, v} <- file_vars, reduce: %{} do
        # On overwrite, we pass (to_add, sys_env) instead of (sys_env, to_add),
        # so getting a variable will use the current overwrites first.
        to_add -> Map.put(to_add, k, build_value(v, to_add, sys_env))
      end

    to_add
  end

  defp build_value(v, _, _) when is_binary(v) do
    # skip building a resolver when the var value is already a string
    v
  end

  defp build_value(v, vars, vars_fallback) do
    interpolate_var(v, resolver(vars, vars_fallback))
  end

  defp resolver(vars, vars_fallback) do
    # The resolver will always return a string, as $UNKNOWN returns an empty
    # string in a linux shell.
    fn key ->
      with :error <- Map.fetch(vars, key),
           :error <- Map.fetch(vars_fallback, key) do
        ""
      else
        ({:ok, v} -> v)
      end
    end
  end

  defp before_env_set(nil, variables) do
    variables
  end

  defp before_env_set(fun, variables) do
    Map.new(variables, fn pair ->
      case fun.(pair) do
        {k, v} when is_binary(k) and is_binary(v) ->
          {k, v}

        {k, v} ->
          try do
            k = to_string(k)
            v = to_string(v)
            {k, v}
          rescue
            e in Protocol.UndefinedError ->
              reraise "invalid :before_env_set return value (could not convert to string): #{inspect(e.value)}",
                      __STACKTRACE__
          end

        other ->
          raise "invalid :before_env_set return value: #{inspect(other)}"
      end
    end)
  end

  @doc """
  Returns the value of the given `var`, transformed and validated by the given
  `caster`.

  Raises if the variable is not defined or if the caster validation fails.

  Please see the [README](README.md#available-casters) for available casters.
  """
  def env!(var, caster \\ :string) do
    case env(var, caster) do
      {:ok, value} -> value
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Returns the value of the given `var`, transformed and validated by the given
  `caster`.

  Returns the `default` value if the variable is not defined.

  If `default` is a function, it is called only if the variable is not defined.
  The returned value from `env!/3` will be the return value of the function.

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
      {:ok, value} ->
        cast(var, value, caster)

      :error ->
        if is_function(default, 0) do
          {:ok, default.()}
        else
          {:ok, default}
        end
    end
  end

  defp cast(var, value, caster) do
    case cast(value, caster) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, cast_error(var, caster, reason)}
    end
  end

  @doc false
  @deprecated "Use Nvir.Cast.cast/2"
  defdelegate cast(value, caster), to: Nvir.Cast

  defp cast_error(var, caster, reason) do
    %Nvir.CastError{var: var, caster: caster, reason: reason}
  end

  @doc false
  @deprecated "Use `Nvir.Parser.interpolate_var/2`"
  def interpolate_var(chunks, resolver) do
    Nvir.Parser.interpolate_var(chunks, resolver)
  end
end
