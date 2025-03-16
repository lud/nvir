# Nvir [![Hex.pm Version](https://img.shields.io/hexpm/v/nvir?color=4e2a8e)](https://hex.pm/packages/nvir) [![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/lud/nvir/elixir.yaml?label=CI)](https://github.com/lud/nvir/actions/workflows/elixir.yaml)

An easy dotenv implementation for Elixir that provides:

* Simple loading of `.env` files with support for inheritance and interpolation.
* Strong validation and type casting of environment variables.
* Environment specific configuration.

This library is heavily inspired from
[Dotenvy](https://github.com/fireproofsocks/dotenvy) and provides a similar
experience.



- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [File loading](#file-loading)
  - [Defining the sources](#defining-the-sources)
    - [The classic dotenv experience](#the-classic-dotenv-experience)
    - [A list of sources](#a-list-of-sources)
    - [Tagged sources](#tagged-sources)
    - [Mixing it all together](#mixing-it-all-together)
  - [Overwrite mechanics](#overwrite-mechanics)
  - [File load order](#file-load-order)
  - [Custom loaders](#custom-loaders)
    - [Using a custom loader](#using-a-custom-loader)
    - [Disabling default tags](#disabling-default-tags)
    - [Disabling all tags by default](#disabling-all-tags-by-default)
    - [Using a custom parser](#using-a-custom-parser)
    - [Transforming the variables](#transforming-the-variables)
- [The `env!` functions](#the-env-functions)
  - [Disclaimer](#disclaimer)
  - [Requiring a variable](#requiring-a-variable)
  - [Default values](#default-values)
  - [Casting values](#casting-values)
    - [String Casters](#string-casters)
    - [Boolean Casters](#boolean-casters)
    - [Number Casters](#number-casters)
    - [Atom Casters](#atom-casters)
    - [Deprecated casters](#deprecated-casters)
  - [Custom Casters](#custom-casters)
- [Dotenv File Syntax Cheatsheet](#dotenv-file-syntax-cheatsheet)
  - [Basic Syntax](#basic-syntax)
  - [Comments](#comments)
  - [Trailing Whitespace](#trailing-whitespace)
  - [Quoted Values](#quoted-values)
    - [Raw Strings](#raw-strings)
    - [Double Quotes](#double-quotes)
    - [Single Quotes](#single-quotes)
  - [Multiline Strings](#multiline-strings)
    - [Triple Double Quotes](#triple-double-quotes)
    - [Triple Single Quotes](#triple-single-quotes)
  - [Variable Interpolation](#variable-interpolation)
- [Environment Files Inheritance](#environment-files-inheritance)
  - [Rules for regular files](#rules-for-regular-files)
  - [Examples](#examples)
  - [Important Edge Case](#important-edge-case)
  - [Rules for overwrite files](#rules-for-overwrite-files)



## Installation

As usual, pull the library from your `mix.exs` file.

```elixir
def deps do
  [
    {:nvir, "~> 0.11"},
  ]
end
```


## Basic Usage

You will generally use `Nvir` from your `config/runtime.exs` file.

* Import the module functions, and call `dotenv!/1` to load your files.
* Use `env!/2` to require a variable and validate it.
* Use `env!/3` to provide a default value. Default values are not validated.

Note that you do not have to call `dotenv!/1` to use the `env` functions. You can
use this library for validation only.

```elixir
# runtime.exs

# Import the library
import Nvir

# Load your env files for local development
dotenv!([".env", ".env.#{config_env()}"])

# Configure your different services with the env!/2 and env!/3 functions.
config :my_app, MyAppWeb.Endpoint,
  # expect values to exist
  secret_key_base: env!("SECRET_KEY_BASE", :string!),
  url: [host: env!("HOST", :string!), port: 443, scheme: "https"],
  # or provide a sane default
  http: [ip: {0, 0, 0, 0}, port: env!("PORT", :integer!, 4000)]
```

This is most of what you need to know to start using this library. Below is an
advanced guide that covers all configuration and usage options.


## File loading

### Defining the sources

The `dotenv!/1` function accepts paths to files, either absolute or relative to
`File.cwd!()` (which points to your app root where `mix.exs` is present).

There are different possible ways to chose the files to load.


#### The classic dotenv experience

```elixir
dotenv!(".env")
```


#### A list of sources

Non-existing files are safely ignored.  Your `.env` file will likely
not be present in production, and you may have a `.env.test` file but no
`.env.dev` file.

```elixir
dotenv!([".env", ".env.#{config_env()}"])
```


#### Tagged sources

It is possible to wrap the sources in tagged tuples, to limit the loading of
the sources to certain conditions:

In this example, a different file is loaded depending on the current
`Config.config_env()`.

```elixir
dotenv!(
  dev: ".env",
  test: ".env.test"
)
```

This gives you more control on the files that are loaded, and ensures that no
file will be loaded in production if the env files are committed to git by
mistake and/or included in your releases.

Refer to the documentation of `Nvir.dotenv!/1` to know the default enabled tags.


#### Mixing it all together

Tagged tuples and lists do not have to contain a single file. They can also
contain other valid sources, that is, nested lists or tuples.

For instance, here in `:test` environment we will load two files, plus an
additional file if the `:ci` tag is enabled.

```elixir
dotenv!(
  dev: ".env",
  test: [".env", ".env.test", ci: ".env.ci"]
)
```

It is also possible to pass the same key multiple times:

```elixir
dotenv!([
  test: ".env.test",
  ci: ".env.ci",
  test: ".env.test.extra"
])
```

### Overwrite mechanics

The files loaded by this library will not replace variables already defined in
the real environment.

That is, as your `HOME` variable already exists, defining `HOME=/somewhere/else`
in an `.env` file will have no effect.

A special tag can be given to `dotenv!/1` to overwrite system variables:

```elixir
dotenv!([".env", overwrite: ".env.local"])
```

With the code above, any variable from `.env` that does not already exists will
be added to the system env, but _all_ variables from `.env.local` will be set.

Just like environment specific keys, the `:overwrite` key accepts any nested
source types. The following forms are equivalent:

```elixir
dotenv!(
  dev: [".env.dev", overwrite: ".env.local.dev"],
  test: [".env.test", overwrite: ".env.local.test"]
)

dotenv!(
  dev: ".env.dev",
  test: ".env.test",
  overwrite: [dev: ".env.local.dev", test: ".env.local.test"]
)
```

In `:dev` environment, the two snippets above would both result in loading
`".env.dev"` then `".env.local.dev"`.

The first level of `:overwrite` will determine which group a file belongs to.
Nesting `:overwrite` tags has no effect. In the following snippet, all files
except `1.env` are overwrite files.

```elixir
dotenv!(
  dev: "1.env",
  overwrite: ["2.env", dev: ["3.env", overwrite: "4.env"]]
)
```

The `3.env` file is wrapped in an `:overwrite` tag, indirectly.


### File load order

The `dotenv!/1` function follows a couple rules when loading the different
sources:

* Files are separated in two groups, "regular" and "overwrites".
* Within each group, files are always loaded in order of appearance. This is
  important for files that reuse variables defined in previous files.
* The "regular" group is loaded first. The files from the "overwrite" group will
  see the variables defined by the "regular" group.

The order of execution is the following:

* Load all regular files in order.
* Patch system environment with non-existing keys.
* Load all overwrite files in order.
* Overwrite system environment with all their values.

This means that the following expression will **not** load and apply
`.env.local` first because it belongs to the "overwrite" group, which is applied
last. But `.env1` will always be loaded before `.env2`.

```elixir
dotenv!(overwrite: ".env.local", dev: ".env1", dev: ".env2")
```


### Custom loaders

It is possible to customize the way the files are loaded. The order of the files
is deterministic and cannot be changed, but options exist to change how they are
loaded.


#### Using a custom loader

The simple way is to start from the default loader and change its properties:

```elixir
# runtime.exs
import Config
import Nvir

dotenv_loader()
|> enable_sources(:docs, config_env() == :docs)
|> enable_sources(:release, env!("RELEASE_NAME", :boolean, false))
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

Plus, we changed the directory where the .env files are loaded from. This will
not affect the `/var/release.env` file since it's an absolute path.

Please refer to the documentation of `dotenv_configure/2` to learn more about
the available options.

#### Disabling default tags

It is also possible to redefine predefined tags. Here we replace the `:test` tag
with a possibly different boolean value.

```elixir
# runtime.exs
import Config
import Nvir

dotenv_loader()
|> enable_sources(:test, config_env() == :test and MyApp.some_custom_check())
|> dotenv!(
  dev: ".env",
  test: ".env.test"
)
```

The `:overwrite` tag cannot be changed, as it is handled separately from other
tags.


#### Disabling all tags by default

Use `dotenv_new()` instead of `dotenv_loader()` to get an empty loader without
any enabled tag.


#### Using a custom parser

If you want to parse the .env files yourself, or add support for other file
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


#### Transforming the variables

It is possible to change the keys and values of the variables before they are
defined in the environment, by using the `:before_env_set` hook.

The function is passed a tuple with the variable name and value, and must return
a name and value.

The returned name and value must be encodable as strings using the `to_string/1`
Elixir function.

It _is_ possible to return a different name from there. The original variable name will _not_ be defined. We use this in the example below but it's generally not recommended for clarity's sake.

An example using values that are not strings and swaps the variable name.

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
    {"USERNAME", username} ->
      {:HOMEPAGE, to_homepage.(username)}
    other ->
      other
  end
)
|> dotenv!(".env")
```

In the example above, the defined variable will be `"HOMEPAGE"` and not the
equivalent atom. The value will be `"http://example.com/some-username"` as a
string too.

## The `env!` functions

The `env!` functions allow you to load an environment variable and cast it to
the appropriate type by passing an optional caster:

```elixir
import Nvir


# This will raise if the variable is not defined
host = env!("HOST")

# This will raise if the variable is not defined or is empty
host = env!("HOST", :string!)

# This will use a default value if the variable is not defined, or otherwise
# convert the value to an integer.
port = env!("PORT", :integer!, 4000)
```

### Disclaimer

Note that the `env!` functions are merely _helpers_ built around
`System.fetch_env!/1` with support for casting. They _do not_ require
`dotenv!/1` to have been called beforehand and are safe to call wherever you
would call `System.fetch_env!/1` instead.

The corollary is that you do not have to use `env!/2` or `env!/3` to fetch
variables loaded by `dotenv!/1`. Using `System.fetch_env!/1`,
`System.get_env/3`, etc. is still perfectly fine.

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


### Requiring a variable

Calling `env!(var, caster)` will attempt to fetch the variable, just like
`System.fetch_env!/1` does, cast the value, and return it.

The `env!(var)` form is a shorthand for `env!(var, :string)`.

Two exceptions may be raised from that call:

* `System.EnvError` if the variable is not defined.
* `Nvir.CastError` if the cast fails.

### Default values

Calling `env!(var, caster, default)` will use the default value if and only if
the key is not defined. There is no version of the function that would use the
default value instead of the variable value.

The function will **not** use the default value if the cast of an existing key
fails. This will still raise an `Nvir.CastError`.

The default value is not validated, so you can for instance call
`env!("SOME_VAR", :integer!, :infinity)`, whereas `:infinity` is not a valid
integer.


### Casting values

Casters come into three flavors that behave differently when an environment variable value is an empty string.

* Casters suffixed with `!` like `:integer!` or `:string!` will raise if the
  variable contains an empty string.
* Casters suffixed with `?` like `:integer?` or `:string?` will convert empty
  strings to `nil` instead of casting.
* Casters without a suffix like `:string` or `:atom` exist for types that can be
  cast from an empty string, _i.e._ the string type and atom types.

See below for a complete list of built-in casters and custom casters.

Empty strings occur when a variable is defined without a value:

```
HOST=localhost # value is "localhost"
PORT=          # value is ""
```

Remember, as long as the key exists, the default value is never used; this holds
true for empty string values.

* Calling `env!("PORT", :integer!, 4000)` will raise because `""` can't be cast
  to an integer.
* Calling `env!("PORT", :integer?, 4000)` will return `nil`.


#### String Casters

| Caster | Description |
|--------|-------------|
| `:string` | Returns the value as-is. |
| `:string?` | Converts empty strings to `nil`. |
| `:string!` | Raises for empty strings. |

#### Boolean Casters

| Caster | Description |
|--------|-------------|
| `:boolean` | `"false"`, `"0"` and empty strings become `false`, any other value is `true`. Case insensitive. It is recommended to use `:boolean!` instead. |
| `:boolean!` | Accepts only `"true"`, `"false"`, `"1"`, and `"0"`. Case insensitive. |

#### Number Casters

| Caster | Description |
|--------|-------------|
| `:integer!` | Strict integer parsing. |
| `:integer?` | Like `:integer!` but empty strings becomes `nil`. |
| `:float!` | Strict float parsing. |
| `:float?` | Like `:float!` but empty strings becomes `nil`. |

#### Atom Casters

| Caster | Description |
|--------|-------------|
| `:atom` | Converts the value to an atom. Use the `:existing_atom` variants when possible. |
| `:atom?` | Like `:atom` but empty strings becomes `nil`. |
| `:atom!` | Like `:atom` but rejects empty strings. |
| `:existing_atom` | Converts to existing atom only, raises otherwise. |
| `:existing_atom?` | Like `:existing_atom` but empty strings becomes `nil`. |
| `:existing_atom!` | Like `:existing_atom` but rejects empty strings. |

Note that using `:existing_atom` with empty strings will not raise an exception
because the `:""` atom is valid and is generally defined by the system on boot.

#### Deprecated casters

Those exist for legacy reasons and should be avoided. They will trigger a
runtime warning when used.

In some languages, using `null` where an number is expected will cast the value
to a _default type value_, generally `0` and `+0.0` for integers and floats.
This behaviour does not exist in Elixir so casters for such types behave the
same with and without the `!` suffix: `:integer` and `:float` will raise for
empty strings.

| Caster | Description |
|--------|-------------|
| `:boolean?` | Same as `:boolean`. ⚠️ Returns `false` instead of `nil` for empty strings. |
| `:integer` | Same as `:integer!`. |
| `:float` | Same as `:float!`. |

### Custom Casters

The second argument to `env!/2` and `env/3` also accept custom validators using an `fn`. The given function must return `{:ok, value}` or `{:error, message}` where `message` is a string.

```elixir
env!("URL", fn
  "https://" <> _ = url -> {:ok, url}
  _ -> {:error, "https:// is required"}
end)
```

It is also possible to return directly an error from `Nvir.cast/2`:

```elixir
env!("PORT", fn value ->
  case Nvir.cast(value, :integer!) do
    {:ok, port} when port > 1024 -> {:ok, port}
    {:ok, port} -> {:error, "invalid port: #{port}"}
    {:error, reason} -> {:error, reason}
  end
end)
```

## Dotenv File Syntax Cheatsheet

### Basic Syntax
```bash
# Simple assignment
KEY=value

# With spaces around =
KEY = value

# Empty value
EMPTY=
EMPTY=""
EMPTY=''

# The parser will ignore an "export" prefix
export KEY=value

# Interpolation with previously defined variable
PATH=/usr/bin
PATH=$PATH:/home/alice/bin
PATH=/usr/local/bin:$PATH
```

### Comments

Comments are supported on their own line or at the end of a line.

**Important**, when a value is not quoted, the comment `#` character must be
separated by at least one space, otherwise the comment will be included in the
value.

```bash
# This is a comment on it's own line

KEY=value # Inline comment

KEY=value# No preceding space, this is part of the value
```

### Trailing Whitespace

Trailing whitespace is automatically removed from the end of a value

In this example, some spaces are represented with the `_` symbol to make it look
more explicit.

```bash

# KEY will contain "value"
KEY=value # Inline comment

# KEY will contain "value" too
KEY=value____

# Multiline strings (with simple and double quotes) are NOT trimmed.
# KEY will contain "Hello!    \nHow are you    \n"
KEY="""
Hello____
How are you____
"""

# Empty Whitespace is trimmed
# KEY will contain ""
KEY=____

# Use quotes to express whitespace
INDENT="    "
```

### Quoted Values

* Quotes are optional.
* Double quotes let you write escape sequences.
* Single quotes define verbatim values. No escaping is done except for the
  single quote itself.

#### Raw Strings
```bash
KEY=raw value with spaces
```

#### Double Quotes
```bash
KEY="value with spaces"
KEY="escape \"quotes\" inside"
KEY="supports \n \r \t \b \f escapes"
```

#### Single Quotes
```bash
KEY='value with spaces'
KEY='no escapes \n' # value will have a "\" character followed by a "n".
# Do not trust Github syntax highlighting here ;)
KEY='escape \'quotes\' inside'
```

### Multiline Strings

The same rules apply for escaping as in single line values:

* Double quotes let you write escape sequences.
* Single quotes define verbatim values. No escaping is done except for the
  single quote itself.


#### Triple Double Quotes

```bash
KEY="""
Line 1
Line 2 with "quotes"
"""
```

#### Triple Single Quotes

```bash
KEY='''
Line 1
Line 2 with 'quotes'
'''
```

### Variable Interpolation

`Nvir` supports variable interpolation within env files. Please refer to the
"Environment Files Inheritance" section for more details on which value is used
on different setups.

```bash
# This variable can be used below in the same file
GREETING=Hello

# Basic syntax
MSG=$GREETING World

# Enclosed syntax
MSG=${GREETING} World

# Not interpolated (single quotes)
MSG='$GREETING World'

# In raw values, a comment without a preceding space will be included in the
# value
MSG=$GREETING# This is part of the value
MSG=${GREETING}# This too
MSG=$GREETING # Actual comment
```

## Environment Files Inheritance

### Rules for regular files

These rules apply to the regular group. Overwrite files will always have their
values added to system environment.

1. System environment variables always take precedence over env files.
2. Multiple env files can be loaded in sequence, with later files overwriting
   earlier ones
3. Variable interpolation (`$VAR`) uses values from the system first, then from
   the most recently defined value.

### Examples

```elixir
# System state:
# WHO=world

# .env
WHO=moon
HELLO=hello $WHO   # Will use WHO=world from system since we are not overwriting

# Result:
# HELLO=hello world
```

With multiple files, we use the latest value. In this exemple the variable is
not already defined in the system:

```elixir
# .env
WHO=world

# .env.dev
WHO=mars
HELLO=hello $WHO # This defines HELLO=hello mars

# .env.dev.2
WHO=moon
HELLO=hello $WHO # this defines HELLO=hello moon

# With loading order of .env, .env.dev, .env.dev.2
# we will have the following:
# WHO=moon
# HELLO=hello moon
```

So, "regular" files do not overwrite the system environment, but they act as a
group and overwrite themselves as if they were a single file.

### Important Edge Case

When a variable using interpolation is not redefined in subsequent files, it
keeps using the value from when it was defined.

```elixir
# .env
WHO=world

# .env.dev
WHO=mars
HELLO=hello $WHO    # HELLO is defined here, uses WHO=mars

# .env.dev.2
WHO=moon           # WHO is updated, but HELLO keeps its value
                   # since it's not redefined here

# Final result:
# WHO=moon
# HELLO=hello mars  # Not "hello moon"!
```

This may cause inconsistencies if you code depends on the values of both `HELLO`
and `WHO`.

### Rules for overwrite files

Overwrite files follow the same logic, each file overwrites the previous ones.

The only difference is that the values in the files take precedence over any
preexisting variable in the system environment.

The edge case documented above still applies.
