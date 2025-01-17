defmodule Nvir.LoadError do
  @moduledoc """
  Exception raised when `Nvir` failed to parse an env file.
  """
  defexception [:reason, :path]

  @impl true
  def message(%{reason: %Nvir.Parser.ParseError{} = pe} = e) do
    "could not load file #{e.path}, syntax error found on #{e.path}:#{pe.line}:#{pe.col}"
  end

  def message(e) do
    "could not load file #{e.path}, got: #{format_reason(e.reason)}"
  end

  defp format_reason(%{__struct__: _, __exception__: true} = e) do
    Exception.message(e)
  end

  defp format_reason(reason) when is_binary(reason) do
    reason
  end

  defp format_reason(reason) do
    inspect(reason)
  end
end
