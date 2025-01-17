# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Nvir.Parser do
  @moduledoc """
  A simple .env file parser.
  """

  @type key :: String.t()
  @type variable :: {key, binary | [binary | {:var, binary}]}

  @doc """
  Must rturn a list of variable definitions in a result tuple.

  Variables definitions are defined as lists of `{key, value}` tuples where the
  `value` is either a string or a list of string and `{:var, string}` tuples.

  For instance, given this file content:

  ```bash
  # .env
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

  There is no need to handle different interpolation scenarios at the parser
  level. This env file:

  ```bash
  PATH=b
  PATH=$PATH:c
  PATH=a:$PATH
  ```

  Should produce the following:

  ```elixir
  {:ok,
    [
      {"PATH", "b"},
      {"PATH", [{:var, "PATH"}, ":c"]},
      {"PATH", ["a:", {:var, "PATH"}]}
    ]}
  ```

  Interpolation will be handled by `Nvir.dotenv!/1` when variables will be
  applied.
  """
  @callback parse_file(path :: String.t()) :: {:ok, [variable]} | {:error, Exception.t()}

  @behaviour __MODULE__

  # -- Entrypoint -------------------------------------------------------------

  @impl true
  @doc """
  Parses the given env file. Implementation of the #{inspect(__MODULE__)}
  Behaviour.
  """
  def parse_file(path) do
    parse_string(File.read!(path))
  end

  def parse_string(content) do
    case Nvir.Parser.RDB.parse(content) do
      {:ok, tokens} -> {:ok, build_entries(:lists.flatten(tokens))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_entries(entries) do
    Enum.map(entries, &build_entry/1)
  end

  defp build_entry({:entry, k, v}), do: {build_key(k), build_value(v)}
  defp build_key(k), do: List.to_string(k)

  defp build_value(v) do
    chunks = v |> :lists.flatten() |> chunk_value([], [])

    if Enum.any?(chunks, &match?({:var, _}, &1)) do
      chunks
    else
      :erlang.iolist_to_binary(chunks)
    end
  end

  # optimization, skip empty chunk
  defp chunk_value([{:var, _} = h | t], [], acc) do
    chunk_value(t, [], [h | acc])
  end

  defp chunk_value([{:var, _} = h | t], chars, acc) do
    chunk_value(t, [], [h, List.to_string(:lists.reverse(chars)) | acc])
  end

  defp chunk_value([h | t], chars, acc) do
    chunk_value(t, [h | chars], acc)
  end

  # optimization, skip empty chunk
  defp chunk_value([], [], acc) do
    :lists.reverse(acc)
  end

  defp chunk_value([], chars, acc) do
    :lists.reverse([List.to_string(:lists.reverse(chars)) | acc])
  end
end
