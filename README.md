# Nvir – Elixir environment variables made simple

<!-- rdmx :badges
    hexpm         : "nvir?color=4e2a8e"
    github_action : "lud/nvir/elixir.yaml?label=CI&branch=main"
    license       : nvir
    -->
[![hex.pm Version](https://img.shields.io/hexpm/v/nvir?color=4e2a8e)](https://hex.pm/packages/nvir)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lud/nvir/elixir.yaml?label=CI&branch=main)](https://github.com/lud/nvir/actions/workflows/elixir.yaml?query=branch%3Amain)
[![License](https://img.shields.io/hexpm/l/nvir.svg)](https://hex.pm/packages/nvir)
<!-- rdmx /:badges -->
Nvir is a powerful environment variable loader for Elixir that provides:

* Simple loading of dotenv files with support for inheritance and interpolation.
* Optional loading of dotenv files depending on the `:test`, `:dev` environment, CI environment, operating system, and custom conditions.
* Strong validation and type casting of environment variables.
* Support for custom casters and variables transformers.

This library is inspired from
[Dotenvy](https://github.com/fireproofsocks/dotenvy) and provides a similar
experience.


## Installation

As usual, pull the library from your `mix.exs` file.

<!-- rdmx :app_dep vsn:$app_vsn -->
```elixir
def deps do
  [
    {:nvir, "~> 0.13"},
  ]
end
```
<!-- rdmx /:app_dep -->




## Basic Usage

You will generally use Nvir from your `config/runtime.exs` file.

* Import the module functions, and call `dotenv!/1` to load your files.
* Use `env!/2` to require a variable and validate it.
* Use `env!/3` to provide a default value.

```elixir
# runtime.exs
import Config
import Nvir

dotenv!([".env", ".env.#{config_env()}"])

config :my_app, MyAppWeb.Endpoint,
  secret_key_base: env!("SECRET_KEY_BASE", :string!),
  url: [host: env!("HOST", :string!), port: 443, scheme: "https"],
  http: [ip: {0, 0, 0, 0}, port: env!("PORT", :integer!, 4000)]

config :my_app, MyApp.Repo,
  username: env!("DB_USERNAME", :string!),
  password: env!("DB_PASSWORD", :string!),
  database: env!("DB_DATABASE", :string!),
  hostname: env!("DB_HOSTNAME", :string!),
  port: env!("DB_PORT", :integer!, 5432)
```

This is most of what you need to know to start using this library.

Please refer to the documentation for advanced usage.


## Documentation

Nvir provides advanced capabilities to work with your dotenv files in different
scenarios. This is all described in the [documentation on
hexdocs.pm](https://hexdocs.pm/nvir/readme.html) including the starter guides:

* [Loading dotenv files](https://hexdocs.pm/nvir/loading-files.html)
* [Reading environment variables](https://hexdocs.pm/nvir/the-env-functions.html)


## Interoperability

This library is built around the native Elixir support for environment variables:

* The `dotenv!/1` function will patch the actual runtime environment. You do not
  have to use `env!/2` or `env!/3` to fetch variables loaded by `dotenv!/1`.
  Using `System.fetch_env!/1`, `System.get_env/2`, etc. is perfectly fine.
* The `env!` functions are helpers built around `System.fetch_env!/1` with
  support for casting. They do not require `dotenv!/1` to have been called
  beforehand and are safe to call wherever you would call `System.fetch_env!/1`
  instead.

You may also use another library like
[Enviable](https://github.com/halostatue/enviable) that provides more advanced
casters:

```elixir
import Nvir
import Enviable

dotenv!(".env")

secret_key = fetch_env_as_pem!("SECRET_KEY")
dns_config = fetch_env_as_json!("DNS_CONFIG_JSON")
```


## Difference with Dotenvy

Dotenvy considers the dotenv files to be configuration helpers only. They are
only available in the Elixir process executing `runtime.exs`.

The `System.fetch_env/1` function and other variants cannot access those
variables. It is possible to make Dotenvy actually declare system variables with
a _side effect_, but then their `env!` function will not find the variables.

Nvir philosophy is that the dotenv files are patches for the environment
_around_ the application, and so the application should be able to use those
variables from anywhere with `System.fetch_env/1` or `Nvir.env!/2`.

Nvir will _always_ patch the system environment. The development environment and
production environment will use the same code paths. This also works well with
libraries that expect some environment variables to be defined.