defmodule Nvir.ParseError do
  @moduledoc """
  Exception raised when `Nvir` failed to parse an env file.
  """
  defexception [:line, :tag, :arg, :path]

  @impl true
  def message(%{path: path, line: line}) do
    "could not parse #{path}, got parse error on line #{line}"
  end
end
