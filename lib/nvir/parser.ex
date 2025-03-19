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

  @doc """
  This callback must return a `{:ok, variables}` or `{:error, reason}` tuple.

  The `variables` is a list of tuples `{key, value}` tuples where:

  * `key` is a string
  * `value` is either a string or a `template`
  * A `template` is a list of chunks where each chunk is either a string or a
    `{:var, varname}` tuple.

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

  You can test and debug your parser by using `Nvir.interpolate_var/2` and a
  simple resolver.

      iex> file_contents = "GREETING=$INTRO $WHO!"
      iex> {:ok, [{"GREETING", template}]} = Nvir.Parser.RDB.parse_string(file_contents)
      iex> resolver = fn
      ...>   "INTRO" -> "Hello"
      ...>   "WHO" -> "World"
      ...> end
      iex> Nvir.interpolate_var(template, resolver)
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
end
