defmodule Nvir.Parser.ParseError do
  @moduledoc """
  Exception representing parse errors from the default parser `Nvir.Parser`.
  """
  defexception [:line, :col, :tag, :arg]

  @impl true
  def message(e) do
    "parse error on line #{e.line}"
  end
end
