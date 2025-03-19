defmodule Nvir.CastError do
  @moduledoc """
  Exception defining an invalid cast. For instance with this dotenv file:

      NOT_AN_INT=some string

  Calling `Nvir.env!/2` with the `:integer!` caster will raise an
  `#{inspect(__MODULE__)}` exception.

      Nvir.env!("NOT_AN_INT", :integer!)
  """
  defexception [:var, :caster, :reason]

  @impl true
  def message(%{var: var, caster: caster, reason: reason}) do
    "could not cast environment variable #{inspect(var)}: #{format_reason(reason, caster)}"
  end

  defp format_reason(:bad_cast, caster) when is_atom(caster) do
    "value does not satisfy #{inspect(caster)}"
  end

  defp format_reason(:bad_cast, caster) when is_function(caster) do
    "value does not satisfy custom caster"
  end

  defp format_reason(:empty, caster) when is_atom(caster) do
    "value does not satisfy #{inspect(caster)} (empty value)"
  end

  defp format_reason(message, caster) when is_binary(message) and is_function(caster, 1) do
    message
  end
end
