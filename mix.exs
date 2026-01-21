defmodule Nvir.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/nvir"
  @version "0.16.0"

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
      versioning: versioning(),
      modkit: modkit(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        main: "readme",
        extra_section: "GUIDES",
        source_ref: "v#{@version}",
        source_url: @source_url,
        extras: doc_extras(),
        groups_for_extras: groups_for_extras()
      ]
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  def doc_extras do
    [
      "README.md",
      "CHANGELOG.md",
      "guides/file-loading/loading-files.md",
      "guides/file-loading/custom-loaders.md",
      "guides/var-reading/the-env-functions.md",
      "guides/dotenv-format/dotenv-syntax.md",
      "guides/dotenv-format/variables-inheritance.md"
    ]
  end

  defp groups_for_extras do
    [
      "Loading Files": ~r/guides\/file-loading\/.?/,
      "Reading Variables": ~r/guides\/var-reading\/.?/,
      "Dotenv Format": ~r/guides\/dotenv-format\/.?/
    ]
  end

  defp package do
    [
      description:
        "A fully-featured dotenv parser with environment variables helpers. Inspired from Dotenvy but using system environment by default.",
      licenses: ["MIT"],
      links: %{"Github" => @source_url, "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"},
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
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22.0", only: :dev, runtime: false},
      {:readmix, "~> 0.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp modkit do
    [
      mount: [
        {Nvir, "lib/nvir"},
        {Nvir.Test, "test/support"}
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

  def cli do
    [
      preferred_envs: [dialyzer: :test, "mod.relocate": :test]
    ]
  end

  defp versioning do
    [
      annotate: true,
      before_commit: [
        &update_readme/1,
        {:add, "README.md"},
        &gen_changelog/1,
        {:add, "CHANGELOG.md"}
      ]
    ]
  end

  def update_readme(vsn) do
    :ok = Readmix.update_file(Readmix.new(vars: %{app_vsn: vsn}), "README.md")
    :ok
  end

  defp gen_changelog(vsn) do
    case System.cmd("git", ["cliff", "--tag", vsn, "-o", "CHANGELOG.md"], stderr_to_stdout: true) do
      {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
      {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
    end
  end
end
