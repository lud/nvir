defmodule Nvir.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/nvir"
  @version "0.9.0"

  def project do
    [
      app: :nvir,
      name: "Nvir",
      description:
        "A fully-featured dotenv parser with environment variables helpers. Fork of Dotenvy with fallback to system environment variables.",
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      modkit: modkit(),
      dialyzer: dialyzer(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test],
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: @source_url,
        extras: extras()
      ]
    ]
  end

  def extras do
    [
      "README.md"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    []
  end

  def links do
    %{}
  end

  def application do
    []
  end

  defp aliases do
    []
  end

  defp deps do
    [
      # Test
      {:briefly, "~> 0.5.1", only: :test},

      # Doc
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Checks

      {:ex_check, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp modkit do
    [
      mount: [
        {Nvir, "lib/nvir"}
      ]
    ]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit, :mix],
      plt_local_path: "_build/plts"
    ]
  end
end