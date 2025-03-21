# Loading dotenv files

This page describes different scenarios for using the `dotenv!/1` function.

Dotenv files should always be loaded from your `config/runtime.exs` file.
You may have to create it yourself if it does not exist.

## Loading a single file

This is the classic dotenv experience.

```elixir
# config/runtime.exs

# Import the Config and Nvir modules
import Config
import Nvir

# Load your dotenv file
dotenv!(".env")

# Start configuring your application
config :my_app, MyApp.Repo,
  username: env!("DB_USERNAME", :string!),
  password: env!("DB_PASSWORD", :string!),
  database: env!("DB_DATABASE", :string!),
  hostname: env!("DB_HOSTNAME", :string!),
  port: env!("DB_PORT", :integer!, 5432)
```



## Loading from different sources

The `Nvir.dotenv!/1` function accepts different types of sources to define which
dotenv files to load.

The sources can be different types of values like lists, nested tuples, _etc._,
but all of them must finally contain a file path..

Nvir accepts relative paths or absolute paths. Relative paths are relative to
`File.cwd!()`, which is the directory containing `mix.exs`.

See the custom loaders documentation to change the relative path target.



### Loading multiple files

You can pass a list of different files to the `dotenv!/1` function.

Nvir ignores the files that do not exist: your `.env` file will likely not be
present in production, and you may have a `.env.test` file but no `.env.dev`
file

```elixir
dotenv!([".env", ".env.#{config_env()}", ".env.local"])
```


### Tagged sources

Nvir has a concept of _enabled_ or _disabled_ sources. This works by wrapping the dotenv paths in tagged tuples.

This gives you more control over the files that are loaded, and ensures that no
file will be loaded in production if the dotenv files are committed to Git by
mistake and/or included in your releases.

In this example, a different file is loaded depending on the current Mix
environment.

```elixir
dotenv!(
  dev: ".env",
  test: ".env.test"
)
```

It is also valid to pass the same key multiple times:

```elixir
dotenv!(
  dev: ".env",
  test: ".env.test"
  test: ".env.test.local"
)
```

### Predefined tags

Those tags are defined automatically by Nvir based on the current environment.

See the custom loaders documentation to know how to define your own tags.

#### Mix environment

* `:dev` - When `Config.config_env()` or `Mix.env()` is `:dev`.
* `:test` - When `Config.config_env()` or `Mix.env()` is `:test`.

There is no predefined tag for `:prod`. Using dotenv files in production is an
anti-pattern. The guide on custom loaders will help you if you really need to.

#### Continuous integration

* `:ci` - When the `CI` environment variable is `"true"`. This variable is
  defined by most CI services.
* `:ci@github` - When the `GITHUB_ACTIONS` environment variable is `"true"`.
* `:ci@travis` - When the `TRAVIS` environment variable is `"true"`.
* `:ci@circle` - When the `CIRCLECI` environment variable is `"true"`.
* `:ci@gitlab` - When the `GITLAB_CI` environment variable is `"true"`.

#### Operating system

* `:linux` - On Linux machines.
* `:windows` - On Windows machines.
* `:darwin` - On MacOS machines.


### Nested sources

List and tuple source may contain other nested _sources_, they are not limited to paths.


```elixir
dotenv!(
  dev: ".env",
  test: [".env.test", ".env.test.local", ci: ".env.ci"]
)
```

In this example, the `:test` tag contains another list, and one element of this
list is a `:ci` tagged tuple.

If you are not familiar with Elixir's keyword lists, the following is an equivalent without the syntactic sugar.

```elixir
dotenv!([
  {:dev, ".env"},
  {:test, [".env", ".env.test", {:ci, ".env.ci"}]}
])
```

## Overwrite mechanics

The files loaded by Nvir will not replace variables already defined in the real
environment.

That is, as your `HOME` variable already exists, defining `HOME=/somewhere/else`
in a dotenv file will have no effect.

A special tag can be given to `dotenv!/1` to overwrite system variables:

```elixir
dotenv!([".env", overwrite: ".env.local"])
```

With the code above, any variable from `.env` that does not already exist will
be added to the system env, but _all_ variables from `.env.local` will be set.

Just like any source tag, the `:overwrite` key accepts any nested source types.
The following forms are equivalent:

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
`.env.dev` then `.env.local.dev`.

Nesting `:overwrite` tags has no effect. All sources nested in an `:overwrite`
tag are considered overwrites. In the following snippet, all files except
`1.env` are overwrite files.

```elixir
dotenv!(
  dev: "1.env",
  overwrite: ["2.env", dev: ["3.env", overwrite: "4.env"]]
)
```

The `3.env` file is considered wrapped in an `:overwrite` tag, albeit
indirectly. The `:overwrite` tag around `4.env` is useless.


## Load order

The `dotenv!/1` function follows a couple rules when loading multiple sources:

* Files are separated in two groups, "regular" and "overwrites".
* Within each group, files are always loaded in order of appearance in the
  sources list. This is important for files that reuse variables defined in
  previous files.
* The "regular" group is loaded first. The files from the "overwrite" group will
  see the variables defined by the "regular" group.

The order of execution is the following:

* Load all regular files in order.
* Patch system environment with non-existing keys.
* Load all overwrite files in order.
* Overwrite system environment with all keys.

This means that the following expression will **not** load and apply
`.env.local` first because it belongs to the "overwrite" group, which is applied
last. But `.env1` will always be loaded before `.env2`.

```elixir
dotenv!(overwrite: ".env.local", dev: ".env1", dev: ".env2")
```

In the following example, files are named in load order (without regard for
enabled or disabled tags).

```elixir
dotenv!(
  dev: "1",
  test: ["2", ci: "3", overwrite: "100"]
  overwrite: ["101", test: "102"]
  linux: "4",
)
```

**The load order impacts variable interpolation and inheritance for variables
that are repeated in multiple files.** Please refer to the Variable Inheritance
guide.
