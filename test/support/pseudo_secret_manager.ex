defmodule Nvir.Test.PseudoSecretManager do
  @moduledoc """
  Mock secret manager for testing secret:// URI resolution with caching.
  """

  def resolve_all(vars) do
    {resolved, _stats} =
      Enum.reduce(vars, {%{}, %{cache: %{}}}, &resolve_var/2)

    resolved
  end

  def resolve_all_with_stats(vars) do
    Enum.reduce(vars, {%{}, %{cache: %{}, fetches: 0, hits: 0}}, &resolve_var_with_stats/2)
  end

  defp resolve_var({key, "secret://" <> rest}, {acc, stats}) do
    if key == "DB_URL" do
      raise "Unexpected key DB_URL - should have been renamed by before_env_set hook"
    end

    case String.split(rest, "#", parts: 2) do
      [path, json_key] ->
        decoded = get_or_fetch(path, stats)
        value = Map.fetch!(decoded, json_key)
        {Map.put(acc, key, value), stats}

      [path] ->
        decoded = get_or_fetch(path, stats)
        value = JSON.encode!(decoded)
        {Map.put(acc, key, value), stats}
    end
  end

  defp resolve_var({key, value}, {acc, stats}) do
    {Map.put(acc, key, value), stats}
  end

  defp resolve_var_with_stats({key, "secret://" <> rest}, {acc, stats}) do
    if key == "DB_URL" do
      raise "Unexpected key DB_URL - should have been renamed by before_env_set hook"
    end

    case String.split(rest, "#", parts: 2) do
      [path, json_key] ->
        case stats.cache do
          %{^path => decoded} ->
            value = Map.fetch!(decoded, json_key)
            {Map.put(acc, key, value), %{stats | hits: stats.hits + 1}}

          _ ->
            decoded = fetch_secret(path)
            value = Map.fetch!(decoded, json_key)

            {
              Map.put(acc, key, value),
              %{stats | cache: Map.put(stats.cache, path, decoded), fetches: stats.fetches + 1}
            }
        end

      [path] ->
        case stats.cache do
          %{^path => decoded} ->
            value = JSON.encode!(decoded)
            {Map.put(acc, key, value), %{stats | hits: stats.hits + 1}}

          _ ->
            decoded = fetch_secret(path)
            value = JSON.encode!(decoded)

            {
              Map.put(acc, key, value),
              %{stats | cache: Map.put(stats.cache, path, decoded), fetches: stats.fetches + 1}
            }
        end
    end
  end

  defp resolve_var_with_stats({key, value}, {acc, stats}) do
    {Map.put(acc, key, value), stats}
  end

  defp get_or_fetch(path, %{cache: cache}) do
    case cache do
      %{^path => decoded} -> decoded
      _ -> fetch_secret(path)
    end
  end

  def mock(secrets) do
    Process.put({__MODULE__, :mock}, secrets)
  end

  defp fetch_secret(path) do
    secrets = Process.get({__MODULE__, :mock}, :mock_not_set)
    Map.fetch!(secrets, path)
  end
end
