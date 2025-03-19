# Nvir – Elixir environment variables made simple

[![Hex.pm Version](https://img.shields.io/hexpm/v/nvir?color=4e2a8e)](https://hex.pm/packages/nvir)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/lud/nvir/elixir.yaml?label=CI)](https://github.com/lud/nvir/actions/workflows/elixir.yaml)
[![License](https://img.shields.io/hexpm/l/nvir.svg)](https://hex.pm/packages/nvir)

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

```elixir
def deps do
  [
    {:nvir, "~> 0.12"},
  ]
end
```


## Basic Usage

You will generally use Nvir from your `config/runtime.exs` file.

* Import the module functions, and call `dotenv!/1` to load your files.
* Use `env!/2` to require a variable and validate it.
* Use `env!/3` to provide a default value.

Note that you do not have to call `dotenv!/1` to use the `env` functions. You can
use this library for validation only.

```elixir
# runtime.exs

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

Dotenvy loads the dotenv files in the process dictionary of the process
executing `runtime.exs`. The defined variables are meant to be _part of_ your
application configuration.

The `System.fetch_env/1` function and other variants
cannot see those variables unless you tells the Dotenvy loader to actually patch
the environment.

Nvir philosophy is that the dotenv files are only patches for the environment
_around_ the application, and so the application should always be able to use
those variables from anywhere with `System.fetch_env/1` or `Nvir.env!/2`.

So Nvir will _always_ patch the system environment. The development environment
and production environment will use the same code paths. This also works well
with libraries that expect some environment variables to be defined.