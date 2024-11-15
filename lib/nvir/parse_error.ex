defmodule Nvir.ParseError do
  defexception [:line, :tag, :arg, :path]

  def message(%{path: path, line: line}) do
    "could not parse #{path}, got parse error on line #{line}"
  end
end
