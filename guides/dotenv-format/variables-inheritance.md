# Variables Inheritance

This documentation describes how Nvir figures out which value to use when a
variable uses interpolation with other variables in a dotenv file.

```
GREETING=Hello $USERNAME!
```

## System inheritance

When loading multiple files, Nvir will load the files in a deterministic order
and splits those files into "regular" and "overwrite" files.

See the file loading documentation for more details. The important part here is
that it changes the inheritance behaviour.


### System inheritance for regular files

Regular files do not overwrite the system environment, so the variables used in
interpolation always use the actual system environment variables first, and then
falls back to the variables defined in the dotenv files.


In this example with a regular file, the `WHO=moon` variable will not be set in
the environment as it is already defined in the system environment as
`WHO=world`.

Nvir will respect that logic when building interpolated values:

```elixir
# System state:
# WHO=world

# .env, a regular file.
WHO=moon
GREETING=hello $WHO   # Will use WHO=world from system since we are not overwriting

# Result:
# GREETING=hello world
```

If the variable does not already exist in the system, then it will use
`WHO=moon` for interpolation because it will also define the variable in the
runtime environment.


### System inheritance for overwrite files

When dealing with overwrite files, the logic is simpler, each variable is always
defined to the latest seen value, in interpolation as well as in the final set
of variables added to the runtime environment.


## Multiple files

With multiple files, we use the latest value. In this example the variable is
not already defined in the system:

```elixir
# .env
WHO=world

# .env.dev
WHO=mars
GREETING=hello $WHO # This defines GREETING=hello mars

# .env.dev.2
WHO=moon
GREETING=hello $WHO # this defines GREETING=hello moon

# With loading order of .env, .env.dev, .env.dev.2
# we will have the following:
# WHO=moon
# GREETING=hello moon
```

So, "regular" files do not overwrite the system environment, but they act as a
group and overwrite themselves as if they were a single file.

If the variable is already defined in the system, the values from all regular
files are ignored just as in the single-file example.


## Important edge case

When a variable used in interpolation is later redefined in subsequent files,
dependent variables that used its value will not use the last defined value:

```elixir
# .env
WHO=world

# .env.dev
WHO=mars
GREETING=hello $WHO     # GREETING is defined here, using WHO=mars

# .env.dev.2
WHO=moon                # WHO is updated, but GREETING keeps its value
                        # since it's not redefined here

# Final result:
# WHO=moon
# GREETING=hello mars  # The result is not "hello moon"
```

This may cause inconsistencies if you code depends on the values of both
`GREETING` and `WHO`.