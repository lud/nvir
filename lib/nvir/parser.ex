# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Nvir.Parser do
  @moduledoc """
  A behaviour for environment variables sources parser.

  The default implementation used in Nvir is `Nvir.Parser.RDB`. It can only
  parse classic dotenv files.

  Parsing other sources such as YAML files or encrypted files requires to
  provide your own parser.

  See the documentation of the `c:parse_file/1` callback for implementation
  guidelines.
  """

  @type key :: String.t()
  @type template :: [binary | {:var, binary}]
  @type variable :: {key, binary | template}

  @type template_resolver :: (String.t() -> nil | String.t())

  @doc """
  This callback must return a `{:ok, variables}` or `{:error, reason}` tuple.

  The `variables` is a list of `{key, value}` tuples where:

  * `key` is a string
  * `value` is either a string or a `template`
  * A `template` is a list of `chunks`
  * A `chunk` is either a string or a `{:var, varname}` tuple.

  Templates are used for interpolation. When a variable uses interpolation, the
  parser must not attempt to read the interpolated variables from environment,
  but rather return a template instead of a binary value.

  Variables used in interpolation within other variables values do not have to
  exist in the file. Nvir uses a resolver to provide those values to execute the
  templates.

  In this example, the `INTRO` variable is defined in the same file, but the
  `WHO` variable is not. This makes not difference, as the parser must not
  require those values.

      iex> file_contents = "INTRO=hello\\nGREETING=$INTRO $WHO!"
      iex> Nvir.Parser.RDB.parse_string(file_contents)
      {:ok, [{"INTRO", "hello"}, {"GREETING", [{:var, "INTRO"}, " ", {:var, "WHO"}, "!"]}]}

  You can test and debug your parser by using `Nvir.Parser.interpolate_var/2`
  and a simple resolver.

      iex> file_contents = "GREETING=$INTRO $WHO!"
      iex> {:ok, [{"GREETING", template}]} = Nvir.Parser.RDB.parse_string(file_contents)
      iex> resolver = fn
      ...>   "INTRO" -> "Hello"
      ...>   "WHO" -> "World"
      ...> end
      iex> Nvir.Parser.interpolate_var(template, resolver)
      "Hello World!"

  ### Expected results examples

  Given this file content:

  ```bash
  WHO=World
  GREETING=Hello $WHO!
  ```

  The `c:parse_file/1` callback should return the following:

  ```elixir
  {:ok,
    [
      {"WHO", "World"},
      {"GREETING", ["Hello ", {:var, "WHO"}, "!"]}
    ]}
  ```

  With this one using accumulative interpolation:

  ```bash
  PATH=/usr/local/bin
  PATH=$PATH:/usr/bin
  PATH=/home/me/bin:$PATH
  ```

  The parser should produce the following:

  ```elixir
  {:ok,
    [
      {"PATH", "/usr/local/bin"},
      {"PATH", [{:var, "PATH"}, ":/usr/bin"]},
      {"PATH", ["/home/me/bin:", {:var, "PATH"}]}
    ]}
  ```
  """
  @callback parse_file(path :: String.t()) :: {:ok, [variable]} | {:error, Exception.t()}

  @doc ~S'''
  Takes a parsed value returned by the parser implementation, and a resolver
  for the interpolated variables.

  A resolver is a function that takes a variable name and returns a string or
  `nil`.

  ### Example

      iex> envfile = """
      iex> GREETING=Hello $NAME!
      iex> """
      iex> {:ok, [{"GREETING", variable}]} = Nvir.Parser.RDB.parse_string(envfile)
      iex> resolver = fn "NAME" -> "World" end
      iex> Nvir.Parser.interpolate_var(variable, resolver)
      "Hello World!"
  '''
  @spec interpolate_var(String.t(), template_resolver) :: String.t()
  def interpolate_var(string, _resolver) when is_binary(string) do
    string
  end

  def interpolate_var(chunks, resolver) when is_list(chunks) do
    :erlang.iolist_to_binary(interpolate_chunks(chunks, resolver))
  end

  defp interpolate_chunks([{:var, key} | t], resolver) do
    chunk_value =
      case resolver.(key) do
        nil ->
          ""

        binary when is_binary(binary) ->
          binary

        other ->
          raise "resolver must return a string for variable #{inspect(key)}, got: #{inspect(other)}"
      end

    [chunk_value | interpolate_chunks(t, resolver)]
  end

  defp interpolate_chunks([h | t], resolver) do
    [h | interpolate_chunks(t, resolver)]
  end

  defp interpolate_chunks([], _resolver) do
    []
  end
end
