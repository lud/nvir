# Reading Environment Variables


The `Nvir.env!/1`, `Nvir.env!/2` and `Nvir.env!/3` functions allow you to load
an environment variable and cast it to the appropriate type by passing an
optional caster:

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


## Requiring a variable

To fetch a variable, call `env!/2` with the variable name and an optional
caster. A caster is either a built-in caster (given as an atom) or a custom
caster. See later for a description of both.

```elixir
env!("PORT", :integer!)
```

This will attempt to fetch the variable as in `System.fetch_env!("SOME_KEY")`, cast its value to an integer and return that value.

Two exceptions may be raised from that call:

* `System.EnvError` if the variable is not defined.
* `Nvir.CastError` if the cast fails.

If no caster is given, Nvir will use the `:string` caster:

```elixir
env!("HOST")
```

Environment variables are always strings, so the `:string` caster will return
the value as-is, given it is defined.


## Default values

Use `env!/3` to provide a default value.

Default values are not used when a variable is found, even if the cast fails, if the variable is empty, or whatever.

```elixir
env!("PORT", :integer!, 4000)
```

Default values are not validated by the caster:

```elixir
# :infinity is not a valid integer but this works
env!("TIMEOUT", :integer!, :infinity)
```

If the default value is a function, it is called only if the variable is not defined. This is useful when the default value is expensive to compute.

```elixir
env!("SECRET_KEY_BASE", :string!, fn ->
  # This will only be called if SECRET_KEY_BASE is not set
  generate_secret_key_base()
end)
```


## Built-in Casters

Built-in casters are defined as atoms. There are three flavors that behave
differently when an environment variable value is an empty string.

* Casters suffixed with `!` like `:integer!` or `:string!` will raise if the
  variable contains an empty string.
* Casters suffixed with `?` like `:integer?` or `:string?` will convert empty
  strings to `nil` instead of casting.
* Casters without a suffix exist for types that can be cast from an empty
  string, _i.e._ `:string`, `:atom`, `:existing_atom` and `:boolean`.

See below for a complete list of built-in casters and custom casters.

Empty strings occur when a variable is defined without a value:

```
HOST=localhost # value is "localhost"
PORT=          # value is ""
```

Remember, as long as the key exists, the default value is never used; this holds
true for empty string values.

With `PORT=""` in the environment:

* Calling `env!("PORT", :integer!, 4000)` will raise because `""` can't be cast
  to an integer.
* Calling `env!("PORT", :integer?, 4000)` will return `nil`.

<!-- rdmx :section name:available_casters -->

### String Casters

| Caster     | Description                      |
| ---------- | -------------------------------- |
| `:string`  | Returns the value as-is.         |
| `:string?` | Converts empty strings to `nil`. |
| `:string!` | Raises for empty strings.        |

### Boolean Casters

| Caster      | Description                                                                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `:boolean`  | `"false"`, `"0"` and empty strings become `false`, any other value is `true`. Case insensitive. It is recommended to use `:boolean!` instead. |
| `:boolean!` | Accepts only `"true"`, `"false"`, `"1"`, and `"0"`. Case insensitive.                                                                         |

### Number Casters

| Caster      | Description                                       |
| ----------- | ------------------------------------------------- |
| `:integer!` | Strict integer parsing.                           |
| `:integer?` | Like `:integer!` but empty strings becomes `nil`. |
| `:float!`   | Strict float parsing.                             |
| `:float?`   | Like `:float!` but empty strings becomes `nil`.   |

### Atom Casters

| Caster            | Description                                                                     |
| ----------------- | ------------------------------------------------------------------------------- |
| `:atom`           | Converts the value to an atom. Use the `:existing_atom` variants when possible. |
| `:atom?`          | Like `:atom` but empty strings becomes `nil`.                                   |
| `:atom!`          | Like `:atom` but rejects empty strings.                                         |
| `:existing_atom`  | Converts to existing atom only, raises otherwise.                               |
| `:existing_atom?` | Like `:existing_atom` but empty strings becomes `nil`.                          |
| `:existing_atom!` | Like `:existing_atom` but rejects empty strings.                                |

Note that using `:existing_atom` with empty strings will not raise an exception
because the `:""` atom is valid and is generally defined by the system on boot.

### Deprecated casters

Those exist for legacy reasons and should be avoided. They will trigger a
runtime warning when used.

In some languages, using `null` where a number is expected will cast the value
to a _default type value_, generally `0` and `+0.0` for integers and floats.
This behaviour does not exist in Elixir so casters for such types behave the
same with-or-without the `!` suffix. This means `:integer` and `:float` will
raise for empty strings.

| Caster      | Description                                                               |
| ----------- | ------------------------------------------------------------------------- |
| `:boolean?` | Same as `:boolean`. ⚠️ Returns `false` instead of `nil` for empty strings. |
| `:integer`  | Same as `:integer!`.                                                      |
| `:float`    | Same as `:float!`.                                                        |

<!-- rdmx /:section -->

## Custom Casters

The second argument to `env!/2` and `env!/3` also accepts custom validators
using an anonymous function. The given function must return `{:ok, value}` or
`{:error, message}` where `message` is a string.

```elixir
env!("URL", fn
  "https://" <> _ = url -> {:ok, url}
  _ -> {:error, "https is required"}
end)
```

It is also possible to return errors from `Nvir.Cast.cast/2`. (Those are not
strings but they are properly handled.)


```elixir
env!("PORT", fn value ->
  case Nvir.Cast.cast(value, :integer!) do
    {:ok, port} when port > 1024 -> {:ok, port}
    {:ok, port} -> {:error, "invalid port: #{port}"}
    {:error, reason} -> {:error, reason}
  end
end)
```