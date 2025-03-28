# Dotenv File Syntax Reference

## Basic Syntax

```elixir
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

## Comments

Comments are supported on their own line or at the end of a line.

**Important**, when a value is not quoted, the comment `#` character must be
separated by at least one space, otherwise the comment will be included in the
value.

```elixir
# This is a comment on its own line

KEY=value # Inline comment

KEY=value# No preceding space, this is part of the value
```

## Single-Line Values


### Raw Strings

Quotes are optional around single-line values.

```elixir
KEY=raw value with spaces
```

### Double Quotes

Double quotes let you write escape sequences and trailing whitespace.

```elixir
KEY="value with spaces"
KEY="escape \"quotes\" inside"
KEY="supports \n \r \t \b \f escapes"
PREFIX="hello "
```

### Single Quotes

Single quotes define verbatim values. No escaping is done except for the single
quote itself.

```elixir
KEY='value with spaces'
KEY='no escapes \n' # value will have a "\" character followed by a "n".
KEY='escape \'quotes\' inside'
```

## Multiline Strings

The same rules apply for escaping as in single line values.


### Triple Double Quotes

Double quotes let you write escape sequences

```elixir
KEY="""
Line 1
Line 2 with "quotes"
"""
```

### Triple Single Quotes

Single quotes define verbatim values. No escaping is done except for the single quote itself.

```elixir
KEY='''
Line 1
Line 2 with 'quotes'
'''
```

## Trailing Whitespace

Trailing whitespace is automatically removed from the end of single-line values
only.

In this example, some spaces are represented with the `_` symbol to make it look
more explicit.

```elixir
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

## Variable Interpolation

Nvir supports variable interpolation within dotenv files.

Single quotes are not interpolated.

Please refer to the "Variables Inheritance" documentation for more details on
which value is used on different setups.

```elixir
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