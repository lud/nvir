# Custom loaders

Nvir allows you to customize the way the files are loaded. The order of the
files is deterministic and cannot be changed, but options exist to change how
they are loaded.


## Using a custom loader

The simple way is to start from the default loader and change its properties.


```elixir
# runtime.exs
import Config
import Nvir

dotenv_loader()
|> dotenv_enable_sources(:docs, config_env() == :docs)
|> dotenv_enable_sources(:release, env!("RELEASE_NAME", :boolean, false))
|> dotenv_configure(cd: "/app/release/env")
|> dotenv!(
  dev: ".env",
  test: ".env.test",
  docs: ".env.docs",
  release: "/var/release.env"
)
```

In the example above, we will enable the `:docs` and `:release` tags when the
defined conditions are met.

Plus, we changed the directory where the dotenv files are loaded from. This will
not affect the `/var/release.env` file since it's an absolute path.

Please refer to the documentation of `Nvir.dotenv_configure/2` to learn more
about the available options.


## Disabling default tags

It is also possible to redefine predefined tags. Here we replace the `:test` tag
with a possibly different boolean value.

```elixir
# runtime.exs
import Config
import Nvir

dotenv_loader()
|> dotenv_enable_sources(:test, config_env() == :test and MyApp.some_custom_check())
|> dotenv!(
  dev: ".env",
  test: ".env.test"
)
```

The `:overwrite` tag cannot be changed, as it is handled separately from other
tags.


## Disabling all tags by default

Use `dotenv_new()` instead of `dotenv_loader()` to get an empty loader without
any enabled tag.


## Using a custom parser

If you want to parse the dotenv files yourself, or add support for other file
formats, pass an implementation of the `Nvir.Parser` behaviour as the `:parser`
option:

```elixir
# runtime.exs
import Config
import Nvir

dotenv_new()
|> dotenv_configure(parser: MyApp.YamlEnvParser)
|> dotenv!("priv/dev-env.yaml")
```


## Transforming the variables

It is possible to change the keys and values of the variables before they are
defined in the environment, by using the `:before_env_set` hook.

The function is passed a tuple with the variable name and value, and must return
a name and value.

The returned name and value must be encodable as strings using the `to_string/1`
Elixir function.

It _is_ possible to return a different name from there. The original variable name will _not_ be defined. We use this in the example below but it's generally not recommended for clarity's sake.

Example:

```elixir
# runtime.exs
import Config
import Nvir

to_homepage = fn username ->
  uri = URI.parse("http://example.com/")
  %{uri | path: "/" <> username}
end

dotenv_new()
|> dotenv_configure(
  before_env_set: fn
    {"USERNAME", username} -> {:HOMEPAGE, to_homepage.(username)}
    other -> other
  end
)
|> dotenv!(".env")
```

* The transformation returns a different variable name.
* The `USERNAME` variable will not be set by Nvir.
* The `HOMEPAGE` variable is returned with an atom key and a `URI` struct value.
* Nvir will set both key and values as strings in the System environment.