defmodule Nvir.Parser.ParseError do
  @moduledoc """
  Exception representing parse errors from the default parser `Nvir.Parser`.
  """
  @enforce_keys [:line, :col, :errmsg, :source]
  defexception [:line, :col, :errmsg, :source, :debug_content]

  @impl true
  def message(e) do
    %{line: line, col: col, source: source, errmsg: errmsg} = e
    message = "dotenv parse error at #{source}:#{line}:#{col} - #{errmsg}"

    case e.debug_content do
      nil -> message
      c -> message <> debug_block(c, line, col)
    end
  end

  @doc false
  def with_debug_content(e, content) do
    %{e | debug_content: content}
  end

  defp debug_block(content, line, col) do
    start_line = max(1, line - 3)

    line_range = (start_line - 1)..(line - 1)

    numwidth =
      cond do
        line < 10 -> 2
        line < 100 -> 3
        line < 1000 -> 4
        line < 10_000 -> 5
        true -> 6
      end

    extract =
      content
      |> String.split("\n", parts: line + 1)
      |> Enum.slice(line_range)
      # Add empty lines if missing
      |> Stream.concat(Stream.repeatedly(fn -> "" end))
      |> Stream.take(Range.size(line_range))
      |> Enum.with_index(start_line)
      |> Enum.map(fn {textline, lineno} ->
        ["\n", String.pad_leading(Integer.to_string(lineno), numwidth), " ", textline]
      end)

    marker = ["\n ", String.duplicate(" ", numwidth), String.duplicate("-", col - 1), "^"]

    IO.iodata_to_binary(["\n\n", extract, marker])
  end
end
