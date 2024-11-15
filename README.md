# Nvir

Easy environment variables and Dotenv implementation for Elixir.

This library helps to load your "dotenv" files easily and provides validation
for environment variables.

It is a fork of [Dotenvy](https://github.com/fireproofsocks/dotenvy) that uses
the predefined system environment variables by default.


- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Loading files](#loading-files)
  - [Single file](#single-file)
  - [A list of files](#a-list-of-files)
  - [Per environment files](#per-environment-files)
- [The `env!` functions](#the-env-functions)
  - [Requiring a variable](#requiring-a-variable)
  - [Default values](#default-values)
  - [Available Casters](#available-casters)
  - [Custom Casters](#custom-casters)
- [Overriding system variables](#overriding-system-variables)
  - [File load order with overrides](#file-load-order-with-overrides)
- [Mix Config environments](#mix-config-environments)
  - [Defining the current environment](#defining-the-current-environment)
- [Dotenv File Syntax Cheatsheet](#dotenv-file-syntax-cheatsheet)
  - [Basic Syntax](#basic-syntax)
  - [Comments](#comments)
  - [Quoted Values](#quoted-values)
  - [Multiline Strings](#multiline-strings)
  - [Variable Interpolation](#variable-interpolation)
- [Environment Files Inheritance](#environment-files-inheritance)
  - [Rules for regular files](#rules-for-regular-files)
  - [Examples](#examples)
  - [Important Edge Case](#important-edge-case)
  - [Rules for override files](#rules-for-override-files)

## Installation

As usual, pull the library from you `mix.exs` file.

```elixir
def deps do
  [
    {:nvir, "~> 1.0"},
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

# Load your files for local environment
dotenv!([".env", ".env.#{config_env()}"])

# Configure your different services with the env!/2 and env!/3 functions.
config :my_app, MyAppWeb.Endpoint,
  secret_key_base: env!("SECRET_KEY_BASE", :string!),
  url: [host: env!("HOST", :string!), port: 443, scheme: "https"],
  # ...

config :my_app, MyApp.Repo,
  username: env!("DB_USERNAME", :string!),
  password: env!("DB_PASSWORD", :string!),
  database: env!("DB_DATABASE", :string!),
  hostname: env!("DB_HOSTNAME", :string!, "localhost"),
  port: env!("DB_PORT", :integer, 5432),
  pool_size: env!("POOL_SIZE", :integer, 10),
  queue_target: env!("REPO_QUEUE_TARGET", :integer, 50),
  queue_interval: env!("REPO_QUEUE_INTERVAL", :integer, 5000)

config :my_app, Oban,
  queues: [
    emailing: env!("SOME_QUEUE_CONCURRENCY", :integer, 10),
  ]
```

## Loading files

The `dotenv!/1` function accepts paths to files, either absolute or relative to `File.cwd!()` (which points to your app root where `mix.exs` is present).

There are different possible ways to chose what file to load.

### Single file

The classic dotenv experience.

```elixir
dotenv!(".env")
```

### A list of files

Non-existing files are safely ignored.  Your `.env` file will likely
not be present in production, and you may have a `.env.test` file but no
`.env.dev` file.

```elixir
dotenv!([".env", ".env.#{config_env()}"])
```

Files are loaded in order. If a value is present in multiple files, the last
file wins.

The `config_env()` function is provided by `import Config` at the top of your config files.

### Per environment files

When files are listed in a keyword list, the file is only loaded if the key matches the current environment.

This gives you more control on the files that are loaded, and ensures that no
file will be loaded in production if the env files are committed to git and/or
included in your releases.

```elixir
dotenv!(
  dev: ".env",
  test: [".env", ".env.test"]
)
```

As you can see, keyword values can themselves be lists or strings. The files are
loaded in order of appearance (as long as the environment matches). Just as
above, when a variable is defined in multiple files, the latter file has the
final say on a variable's value.

It is also possible to pass the same key multiple times.

Files under a `:*` key are always loaded, regardless of the current
environment. That key is mostly a syntax tool, as `["a", key: "b"]` is valid
Elixir syntax, but `[key: "a", "b"]` is not.

A wildcard key allows a file to be loaded in any environment:

```elixir
dotenv!(*: ".env", test: ".env.test")

# Equivalent to
dotenv!([".env", test: ".env.test"])
```

The following are **not** equivalent, as it changes the order of the files:

```elixir
dotenv!(*: ".env", dev: ".env.dev")
dotenv!(dev: ".env.dev", *: ".env")
```


## The `env!` functions

The `env!` functions allows you to load an environment variable and cast its
content to the appropriate type.

### Requiring a variable

Calling `env!(var, caster)` will attempt to fetch the variable, just like
`System.fetch_env!/1` does, cast its value, and return it.

A `System.EnvError` exception will be raised if the variable is not defined.

An `Nvir.CastError` exception will be raised if the cast fails.

### Default values

Calling `env!(var, caster, default)` will use the default value if the key is
not defined.

The function will **not** use the default value if the cast of an existing key
fails. This will still raise an `Nvir.CastError`.

The default value is not validated, so you can for instance call
`env!("SOME_VAR", :integer, :infinity)`, whereas `:infinity` is not a valid
integer.

### Available Casters

Casters come into three flavors:

* The "value as is" one.
* The "nil" one with a `?` suffix that converts empty strings to `nil`. It will
  however not fallback to the default value given to `env!/3` if the key exists.
* The "bang" one with a `!` suffix that will raise an `Nvir.CastError` exception for
  empty strings and special cases described below.

In some languages, using `null` where an integer is expected will cast the value
to a "default value", generally `0` for integers. This is not the case in
Elixir. To respect that, casters for such types behave the same with and without
the `!` suffix. Namely, `:integer` and `:float` will raise for empty strings.

It is however not the case for `:existing_atom`, because the `:""` atom is
generally defined by the system long before an application starts, in Erlang
just as in Elixir.

Empty strings occur when a variable is defined without a value:

```
HOST=localhost # value is "localhost"
PORT=          # value is ""
```

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

#### Deprecated casters

Those exist for legacy reasons and should not be used.

| Caster | Description |
|--------|-------------|
| `:boolean?` | Same as `:boolean`. |
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



## Overriding system variables

The files loaded by this library will not overwrite already existing variables. That is, as your `HOME` variable already exists, defining `HOME=/somewhere/else` in your `.env` file will have no effect.

Another special key can be given to `dotenv!/1` to override system variables:

```elixir
dotenv!([".env", override: ".env.local"])

# load more files
dotenv!([".env", override: [".env.local", ".env.local.#{config_env()}"]])
```

With the code above, any variable from `.env` that does not already exists will be added to the system env, but _all_ variables from `.env.local` will be set.

Just like environment specific keys, the `:override` key accepts strings or
lists, and the lists may contain environments too. The following forms are
equivalent:

```elixir
dotenv!(
  *: [".env", override: ".env.local"],
  dev: [".env.dev", override: ".env.local.dev"],
  test: [".env.test", override: ".env.local.test"]
)

dotenv!(
  *: ".env",
  dev: ".env.dev",
  test: ".env.test",
  override: [*: ".env.local", dev: ".env.local.dev", test: ".env.local.test"]
)
```

The `:*` key applies to all environments, and the files belong to the same group
as files under a `:dev` or `:test` key. The final file in order still has the
final say for a variable.

The two snippets above would both result in loading `".env"` and `".env.dev"` as regular files, and then `".env.local"` and `".env.local.dev"` as overrides, in those orders.

### File load order with overrides

Regular and override files are separated into two groups. As stated earlier,
each group files are loaded in order of appearance, but all files from the
regular files group are applied before loading the override files.

The `dotenv/1` function will do the following:

* Load all regular files in order.
* Patch system environment with non-existing keys.
* Load all override files in order.
* Overwrite system environment with all their values.

This means that the following expression will not load and apply `.env.local`
before `.env` because they do not belong to the same group, and the `:override`
group is applied last.

```elixir
dotenv!(override: ".env.local", dev: ".env")
```

## Mix Config environments

The list of possible environment names is not predefined. You can pass any key and the files will be loaded if that key matches the current environment.

So for instance it is possible to list files under a `:prod` key, while not recommended.

Some projects use a dedicated environment for CI, so a custom `:ci` key can be used in this case.

### Defining the current environment

The current environment that will match the keys given to `dotenv!/1` is the
value of `config_env()` when called from a config file. Otherwise it is set to
the value of `Mix.env()`.

It is not recommended to call `dotenv!/1` directly from modules at runtime
because the current environment will be undefined in a production release.
`dotenv!/1` belongs to `runtime.exs`.



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
KEY='escape \'quotes\' inside'
```

### Multiline Strings

The same rules applies for escaping as in single line values:

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

These rules apply to the regular group. Override files will always have their values added to system environment.

1. System environment variables always take precedence over env files
2. Multiple env files can be loaded in sequence, with later files overriding
   earlier ones
3. Variable interpolation (`$VAR`) uses values from the system first, then from
   the most recently defined value

### Examples

```elixir
# System state:
# WHO=moon

# .env
WHO=world
HELLO=hello $WHO   # Will use WHO=moon from system

# Result:
# HELLO=hello moon
```

With multiple files, we use the latest value. In this exemple the variable is
not already defined in the system:

```elixir
# .env
WHO=world

# .env.dev
WHO=mars
HELLO=hello $WHO

# .env.dev.2
WHO=moon
HELLO=hello $WHO

# Loading order: .env -> .env.dev -> .env.dev.2
# Result:
# WHO=moon
# HELLO=hello moon
```

### Important Edge Case
When a variable using interpolation is not redefined in subsequent files, it keeps using the value from when it was defined.

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

This may cause inconsistencies if you code depends on the values of both `HELLO` and `WHO`.

### Rules for override files

Override files follow the same logic, each file overrides the previous ones.

The only difference is that the values in the files take precedence over any
preexisting variable in the system environment.

The edge case documented above still applies.