defmodule Nvir do
  @moduledoc """
  This is the main API for Nvir, an environment variable loader and validator.

  The most useful documentation is generally:

  * The [README](README.md#basic-usage) for usage instructions.
  * The the `dotenv!/1` function.
  """

  require Config

  @enforce_keys [:enabled_sources]
  defstruct enabled_sources: %{}, parser: Nvir.Parser, cd: nil

  @type t :: %__MODULE__{enabled_sources: %{atom => boolean}, parser: module, cd: nil | Path.t()}
  @type source :: binary | {atom, source} | [source]
  @type sources :: source | [sources] | {atom, sources}
  @type config_opt ::
          {:enabled_sources, %{atom => boolean}} | {:parser, module} | {:cd, nil | Path.t()}

  @doc """
  Returns a configuration for `dotenv!/2` without any enabled source.

  Generally this is used for custom loading strategies, see `dotenv_loader/0` or
  `dotenv_loader/1` to use reasonable defaults.
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
      |> enable_source(:docs, config_env() == "docs")
      |> dotenv!(
        docs: ".env.docs",
        dev: ".env.dev",
        test: ".env.test"
      )

  Disable loading

      import Config
      import Nvir

      dotenv_loader()
      |> enable_source(:docs, config_env() == "docs")
      |> dotenv!(
        docs: ".env.docs",
        dev: ".env.dev",
        test: ".env.test"
      )
  """
  @spec dotenv_loader :: t
  def dotenv_loader do
    dotenv_configure(dotenv_new(), enabled_sources: default_enabled_sources())
  end

  defp default_enabled_sources do
    defaults = %{*: true}

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

  defp guess_env do
    with :error <- guess_env_config(), do: guess_env_mix()
  end

  defp guess_env_config do
    {:ok, Config.config_env()}
  rescue
    _ in RuntimeError -> :error
  end

  defp guess_env_mix do
    if Code.ensure_loaded?(Mix),
      do: {:ok, Mix.env()},
      else: :error
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

        # Load env files relative to this directory
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
    if valid_opt?(opt),
      do: opt,
      else: raise(ArgumentError, "invalid #{inspect(k)} option: #{inspect(v)}")
  end

  defp valid_opt?({:enabled_sources, flags}) do
    (is_list(flags) or is_map(flags)) and
      Enum.all?(flags, fn
        {:overwrite, v} ->
          IO.warn("enabling source :overwrite has no effect")
          is_boolean(v)

        {k, v} ->
          is_atom(k) and is_boolean(v)

        _ ->
          false
      end)
  end

  defp valid_opt?({:parser, module}), do: is_atom(module)
  defp valid_opt?({:cd, dir}), do: is_binary(dir) or is_nil(dir) or is_list(dir)

  @doc """
  Enables or disables environment variable sources under the given tag.

  For instance, the following call will load both files:

      Nvir.dotenv_loader()
      |> Nvir.enable_sources(:custom, true)
      |> Nvir.dotenv!(["global.env", {:custom,  "local.env"}])

  Whereas the following call will only load files that are not wrapped in a tag.

      Nvir.dotenv_loader()
      |> Nvir.dotenv!(["global.env", {:custom,  "local.env"}])

  It is also possible to disable some defaults by overriding them. In the
  following code, the `.env.test` file will never be loaded:

      Nvir.dotenv_loader()
      |> Nvir.enable_sources(:test, false)
      |> Nvir.dotenv!(["global.env", dev: ".env.dev", test: ".env.test"])

  """
  def enable_sources(nvir, tag, enabled?) when is_atom(tag) and is_boolean(enabled?) do
    %__MODULE__{nvir | enabled_sources: Map.put(nvir.enabled_sources, tag, enabled?)}
  end

  def enable_sources(nvir, enum) when is_list(enum) when is_map(enum) do
    {_, _} = validate_opt!({:enabled_sources, enum})
    %__MODULE__{nvir | enabled_sources: Map.merge(nvir.enabled_sources, Map.new(enum))}
  end

  @doc """
  Loads specified env files in the system environment. Intended usage is from
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
        *: ".env",
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

  #### Always enabled

  * `:*` -  Acts as a syntactic sugar to avoid mixing keyword lists and strings.

  #### Mix environment

  * `:dev` - When `Config.config_env()` or `Mix.env()` is `:dev`.
  * `:test` - When `Config.config_env()` or `Mix.env()` is `:test`.

  There is no predefined tag for `:prod` as using .env files in production is
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
  Same as `dotenv!/1` but accepts a custom configuration to load env files.
  """
  @spec dotenv!(t, sources) :: %{binary => binary}
  def dotenv!(nvir, sources) do
    {regular, overwrites} = collect_sources(nvir, sources)

    preexisting_regular = System.get_env()
    parsed_regular = load_files(nvir, regular)
    added_regular = merge_vars_regular(parsed_regular, preexisting_regular)

    preexisting_overwrite = System.get_env()
    parsed_overwrites = load_files(nvir, overwrites)
    added_overwrites = merge_vars_overwrite(parsed_overwrites, preexisting_overwrite)

    Map.merge(added_regular, added_overwrites)
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

  defp expand_path(file, nil), do: file
  defp expand_path(file, cd), do: Path.expand(file, cd)

  defp load_file(path, parser) do
    if File.regular?(path),
      do: parser.parse_file(path),
      else: {:error, :enoent}
  end

  defp merge_vars_regular(files_vars, sys_env) do
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

  defp merge_vars_overwrite(files_vars, sys_env) do
    to_add =
      for file_vars <- files_vars, {k, v} <- file_vars, reduce: %{} do
        # On overwrite, we pass (to_add, sys_env) instead of (sys_env, to_add),
        # so getting a variable will use the current overwrites first.
        to_add -> Map.put(to_add, k, build_value(v, to_add, sys_env))
      end

    System.put_env(to_add)
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
           :error <- Map.fetch(vars_fallback, key),
           do: "",
           else: ({:ok, v} -> v)
    end
  end

  @doc false
  @spec collect_sources(t, sources) :: {sources, sources}
  def collect_sources(nvir, sources) do
    %{enabled_sources: enabled} = nvir

    regular =
      sources
      |> drop_overwrites()
      |> collect_matches(enabled, [])

    overwrites =
      sources
      |> take_overwrites()
      |> collect_matches(enabled, [])

    {regular, overwrites}
  end

  defp drop_overwrites(source) when is_binary(source), do: source

  defp drop_overwrites([source | sources]),
    do: [drop_overwrites(source) | drop_overwrites(sources)]

  defp drop_overwrites([]), do: []

  defp drop_overwrites({:overwrite, _}), do: []
  defp drop_overwrites({tag, source}), do: {tag, drop_overwrites(source)}

  if Mix.env() == :test do
    # support integers for tests, to check on ordering
    defp drop_overwrites(source) when is_integer(source), do: source
  else
    defp drop_overwrites(source) do
      raise ArgumentError, "invalid env source: #{inspect(source)}"
    end
  end

  defp take_overwrites([{:overwrite, source} | sources]),
    do: [unwrap_overwrites(source) | take_overwrites(sources)]

  defp take_overwrites([{tag, source} | sources]),
    do: [{tag, take_overwrites(source)} | take_overwrites(sources)]

  defp take_overwrites([source | sources]),
    do: [take_overwrites(source) | take_overwrites(sources)]

  defp take_overwrites(_), do: []

  # removes the :overwrite tag to all nested overwrites. Nested overwrites should
  # not be used as they are meaningless but they are still supported.
  defp unwrap_overwrites(source) when is_binary(source), do: source

  defp unwrap_overwrites([{:overwrite, source} | sources]),
    do: [unwrap_overwrites(source) | unwrap_overwrites(sources)]

  defp unwrap_overwrites([{keep_tag, source} | sources]),
    do: [{keep_tag, unwrap_overwrites(source)} | unwrap_overwrites(sources)]

  defp unwrap_overwrites([source | sources]),
    do: [unwrap_overwrites(source) | unwrap_overwrites(sources)]

  defp unwrap_overwrites([]), do: []

  if Mix.env() == :test do
    # support integers for tests, to check on ordering
    defp unwrap_overwrites(source) when is_integer(source), do: source
  else
    defp unwrap_overwrites(source) do
      raise ArgumentError, "invalid env source: #{inspect(source)}"
    end
  end

  defp collect_matches(source, _enabled, acc) when is_binary(source) do
    [source | acc]
  end

  defp collect_matches([h | t], enabled, acc) do
    collect_matches(h, enabled, collect_matches(t, enabled, acc))
  end

  defp collect_matches([], _enabled, acc), do: acc

  defp collect_matches({tag, source}, enabled, acc)
       when :erlang.map_get(tag, enabled) == true do
    collect_matches(source, enabled, acc)
  end

  defp collect_matches({:*, source}, enabled, acc) do
    collect_matches(source, enabled, acc)
  end

  defp collect_matches({_, _}, _enabled, acc) do
    acc
  end

  if Mix.env() == :test do
    # support integers for tests, to check on ordering
    defp collect_matches(source, _enabled, acc) when is_integer(source) do
      [source | acc]
    end
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

  @doc ~S'''
  Takes a parsed value returned by the parser implementation, and a resolver
  for the interpolated variables.

  ### Example

      iex> envfile = """
      iex> GREETING=Hello $NAME!
      iex> """
      iex> {:ok, [{"GREETING", variable}]} = Nvir.Parser.parse_string(envfile)
      iex> resolver = fn "NAME" -> "World" end
      iex> Nvir.interpolate_var(variable, resolver)
      "Hello World!"
  '''
  def interpolate_var(string, _resolver) when is_binary(string) do
    string
  end

  def interpolate_var(chunks, resolver) when is_list(chunks) do
    :erlang.iolist_to_binary(interpolate_chunks(chunks, resolver))
  end

  defp interpolate_chunks([{:var, key} | t], resolver) do
    chunk_value = resolver.(key)
    true = is_binary(chunk_value)
    [chunk_value | interpolate_chunks(t, resolver)]
  end

  defp interpolate_chunks([h | t], resolver) do
    [h | interpolate_chunks(t, resolver)]
  end

  defp interpolate_chunks([], _resolver) do
    []
  end
end
