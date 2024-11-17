defmodule Nvir.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/nvir"
  @version "0.9.0"

  def project do
    [
      app: :nvir,
      name: "Nvir",
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      modkit: modkit(),
      dialyzer: dialyzer(),
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

  defp package do
    [
      description:
        "A fully-featured dotenv parser with environment variables helpers. Fork of Dotenvy with fallback to system environment variables.",
      licenses: ["MIT"],
      links: %{"Github" => @source_url, "CHANGELOG" => "#{@source_url}/blob/main/CHANGELOG.md"},
      maintainers: ["Ludovic Demblans <ludovic@demblans.com>"]
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      # Test
      {:briefly, "~> 0.5.1", only: :test},

      # Doc
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},

      # Checks
      {:ex_check, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: :dev, runtime: false}
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
