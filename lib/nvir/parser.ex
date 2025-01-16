# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Nvir.Parser do
  @moduledoc """
  A simple .env file parser.
  """

  require Record
  Record.defrecordp(:buffer, [:text, :line, :column])

  @accented :lists.flatten([
              [?á, ?Á, ?à, ?À, ?â, ?Â, ?ä, ?Ä, ?ã, ?Ã, ?å, ?Å],
              [?æ, ?Æ],
              [?ç, ?Ç],
              [?é, ?É, ?è, ?È, ?ê, ?Ê, ?ë, ?Ë],
              [?í, ?Í, ?ì, ?Ì, ?î, ?Î, ?ï, ?Ï],
              [?ñ, ?Ñ],
              [?ó, ?Ó, ?ò, ?Ò, ?ô, ?Ô, ?ö, ?Ö, ?õ, ?Õ, ?ø, ?Ø, ?œ, ?Œ],
              ?ß,
              [?ú, ?Ú, ?ù, ?Ù, ?û, ?Û, ?ü, ?Ü]
            ])

  @type buffer :: buffer()
  @type parser :: (buffer -> {:ok, term, buffer} | {:error, {atom, term, buffer()}})
  @type key :: String.t()
  @type value :: String.t()
  @type variable :: {key, binary | [binary | {:var, binary}]}

  @doc """
  Must rturn a list of variable definitions in a result tuple.

  Variables definitions are defined as lists of `{key, value}` tuples where the
  `value` is either a string or a list of string and `{:var, string}` tuples.

  For instance, given this file content:

  ```bash
  # .env
  WHO=World
  GREETING=Hello $WHO!
  ```

  The `c:parse_file/1` callback should return the following:

  ```elixir
  {:ok,
    [
      {"WHO", "World"},
      {"GREETING", ["Hello ", {:var, "WHO"}, "!"]}
    ]}
  ```

  There is no need to handle different interpolation scenarios at the parser
  level. This env file:

  ```bash
  PATH=b
  PATH=$PATH:c
  PATH=a:$PATH
  ```

  Should produce the following:

  ```elixir
  {:ok,
    [
      {"PATH", "b"},
      {"PATH", [{:var, "PATH"}, ":c"]},
      {"PATH", ["a:", {:var, "PATH"}]}
    ]}
  ```

  Interpolation will be handled by `Nvir.dotenv!/1` when variables will be
  applied.
  """
  @callback parse_file(path :: String.t()) ::
              {:ok, [variable]} | {:error, Exception.t()}

  @behaviour __MODULE__

  @spec expressions :: parser
  defp expressions do
    many1(
      choice([
        tag_ignore(newline()),
        tag_ignore(comment_line()),
        entry()
      ])
    )
    |> skip_ignored()
  end

  @spec entry :: parser
  defp entry do
    sequence([
      ignore_spaces(),
      tag_ignore(maybe(string("export "))),
      ignore_spaces(),
      key(),
      ignore_spaces(),
      tag_ignore(char(?=)),
      # ignore comment when empty value is there
      tag_ignore(maybe(sequence([string(" #"), many0(not_eol())]))),
      ignore_spaces(),
      value()
    ])
    |> skip_ignored()
    |> map(fn [k, v] -> {:entry, k, v} end)
  end

  @spec newline :: parser
  defp newline do
    char(?\n)
  end

  @spec comment_line :: parser
  defp comment_line do
    sequence([
      many0(space()),
      char(?#),
      many0(not_char(?\n)),
      char(?\n)
    ])
  end

  @spec ignore_spaces :: parser
  defp ignore_spaces do
    tag_ignore(many0(space()))
  end

  @spec key_char :: parser
  defp key_char do
    char([?A..?Z, ?a..?z, ?0..?9, ?_] ++ @accented)
  end

  @spec key :: parser
  defp key do
    many1(key_char())
  end

  @spec value :: parser
  defp value do
    choice([
      raw_value_opt_comment(),
      double_quoted_string_opt_comment(),
      single_quoted_string_opt_comment(),
      multiline_double_quoted_string(),
      multiline_single_quoted_string()
    ])
  end

  @spec raw_value_opt_comment :: parser
  defp raw_value_opt_comment do
    sequence([
      many0(
        choice([
          interpolation_variable(),
          tag_ignore(sequence([many1(space()), char(?#), many0(not_eol())])),
          not_char([?", ?', ?\n])
        ])
      )
      |> skip_ignored(),
      tag_ignore(eol_or_eos())
    ])
    |> skip_ignored()
  end

  @spec double_quoted_string_opt_comment :: parser
  defp double_quoted_string_opt_comment do
    sequence([
      tag_ignore(char(?")),
      many0(char_in_double_quotes()),
      tag_ignore(char(?")),
      tag_ignore(maybe(comment_after_quote())),
      tag_ignore(eol_or_eos())
    ])
    |> skip_ignored()
  end

  @spec char_in_double_quotes :: parser
  defp char_in_double_quotes(allow_double_quote? \\ false) do
    bad_chars = [?\n]
    bad_chars = if allow_double_quote?, do: bad_chars, else: [?" | bad_chars]

    choice([
      interpolation_variable(),
      map(sequence([char(?\\), char()]), &unescape_sequence/1),
      not_char(bad_chars)
    ])
  end

  @spec multiline_double_quoted_string :: parser
  defp multiline_double_quoted_string do
    commit(
      tag_ignore(string(~s("""\n))),
      [
        many0(
          sequence([
            lookahead_not(string(~s("""))),
            many0(char_in_double_quotes(true)),
            eol()
          ])
        ),
        tag_ignore(choice([string(~s("""\n)), sequence([string(~s(""")), eos()])]))
      ]
    )
    |> skip_ignored()
  end

  @spec interpolation_variable :: parser
  defp interpolation_variable do
    choice([
      sequence([char(?$), key(), lookahead_not(key_char())])
      |> map(fn [_, key, _] -> {:var, List.to_string(key)} end),
      sequence([char(?$), char(?{), key(), char(?})])
      |> map(fn [_, _, key, _] -> {:var, List.to_string(key)} end),
      # Empty key, for backward compatibility
      sequence([char(?$), char(?{), char(?})])
      |> map(fn _ -> {:var, ""} end)
    ])
  end

  @spec single_quoted_string_opt_comment :: parser
  defp single_quoted_string_opt_comment do
    sequence([
      tag_ignore(char(?')),
      many0(char_in_single_quotes()),
      tag_ignore(char(?')),
      tag_ignore(maybe(comment_after_quote())),
      tag_ignore(eol_or_eos())
    ])
    |> skip_ignored()
  end

  @spec char_in_single_quotes :: parser
  defp char_in_single_quotes(allow_single_quote? \\ false) do
    bad_chars = [?\n]
    bad_chars = if allow_single_quote?, do: bad_chars, else: [?' | bad_chars]

    choice([
      replace(string("\\'"), ?'),
      not_char(bad_chars)
    ])
  end

  @spec multiline_single_quoted_string :: parser
  defp multiline_single_quoted_string do
    sequence([
      tag_ignore(string(~s('''\n))),
      many0(
        sequence([
          lookahead_not(string(~s('''))),
          many0(char_in_single_quotes(true)),
          eol()
        ])
      ),
      tag_ignore(choice([string(~s('''\n)), sequence([string(~s(''')), eos()])]))
    ])
    |> skip_ignored()
  end

  @spec comment_after_quote :: parser
  defp comment_after_quote do
    sequence([
      many0(space()),
      char(?#),
      many0(not_eol())
    ])
  end

  @spec space :: parser
  defp space do
    char(?\s)
  end

  @spec eol :: parser
  defp eol do
    char(?\n)
  end

  @spec eos :: parser
  defp eos do
    fn input ->
      case take(input) do
        :EOI -> {:ok, [], input}
        {c, rest} -> {:error, {:not_eoi, c, rest}}
      end
    end
  end

  @spec eol_or_eos :: parser
  defp eol_or_eos do
    choice([eol(), eos()])
  end

  @spec not_eol :: parser
  defp not_eol do
    not_char(?\n)
  end

  @spec satisfy(parser, function) :: parser
  defp satisfy(parser, acceptor) do
    fn input ->
      with {:ok, term, rest} <- parser.(input) do
        if acceptor.(term),
          do: {:ok, term, rest},
          else: {:error, {:predicate, nil, input}}
      end
    end
  end

  @spec lookahead_not(parser) :: parser
  defp lookahead_not(parser) do
    fn input ->
      case parser.(input) do
        {:ok, _, _} -> {:error, {:lookahead_not, nil, input}}
        {:error, _} -> {:ok, [], input}
      end
    end
  end

  @spec char(term) :: parser
  defp char(expected), do: satisfy(char(), fn char -> char_match?(char, expected) end)

  @spec char_match?(integer, term) :: boolean
  defp char_match?(char, codepoint) when is_integer(codepoint), do: char == codepoint
  defp char_match?(char, list) when is_list(list), do: Enum.any?(list, &char_match?(char, &1))
  defp char_match?(char, _.._//_ = range), do: char in range

  defp char_match?(char, f) when is_function(f, 1) do
    case f.(char) do
      true -> true
      false -> false
    end
  end

  @spec string(String.t()) :: parser
  defp string(expected) do
    fn input ->
      case consume_string(input, expected) do
        {:ok, rest} -> {:ok, expected, rest}
        :error -> {:error, {:string_nomtach, expected, input}}
      end
    end
  end

  @spec not_char(term) :: parser
  defp not_char(rejected),
    do: satisfy(char(), fn char -> not char_match?(char, rejected) end)

  @spec char :: parser
  defp char do
    fn input ->
      case take(input) do
        :EOI -> {:error, {:EOI, nil, input}}
        {char, buf} -> {:ok, char, buf}
      end
    end
  end

  @spec sequence([parser]) :: parser
  defp sequence(parsers) do
    fn input ->
      case parsers do
        [] ->
          {:ok, [], input}

        [first_parser | other_parsers] ->
          with {:ok, first_term, rest} <- first_parser.(input),
               {:ok, other_terms, rest} <- sequence(other_parsers).(rest),
               do: {:ok, [first_term | other_terms], rest}
      end
    end
  end

  @spec choice([parser]) :: parser
  defp choice([_, _ | _] = parsers) do
    # minimum 2 parsers so we always have a prev reason
    do_choice(parsers, nil)
  end

  defp do_choice(parsers, prev_reason) do
    fn input ->
      case parsers do
        [] ->
          {:error, prev_reason}

        [first_parser | other_parsers] ->
          with {:error, reason} <- first_parser.(input),
               do: do_choice(other_parsers, reason).(input)
      end
    end
  end

  @spec many0(parser) :: parser
  defp many0(many0_parser) do
    fn input ->
      case many0_parser.(input) do
        {:error, _reason} ->
          {:ok, [], input}

        {:ok, first_term, rest} ->
          {:ok, other_terms, rest} = many0(many0_parser).(rest)
          {:ok, [first_term | other_terms], rest}
      end
    end
  end

  @spec many1(parser) :: parser
  defp many1(many1_parser) do
    fn input ->
      case many1_parser.(input) do
        {:ok, token, rest} ->
          {:ok, more_tokens, rest} = many0(many1_parser).(rest)
          {:ok, [token | more_tokens], rest}

        {:error, _} = err ->
          err
      end
    end
  end

  @spec maybe(parser) :: parser
  defp maybe(parser) do
    fn input ->
      case parser.(input) do
        {:error, _reason} -> {:ok, [], input}
        {:ok, term, rest} -> {:ok, [term], rest}
      end
    end
  end

  @spec tag_ignore(parser) :: parser
  defp tag_ignore(parser) do
    map(parser, &{:ignore, &1})
  end

  @spec skip_ignored(parser) :: parser
  defp skip_ignored(parser) do
    map(parser, &filter_ignored/1)
  end

  @spec map(parser, function) :: parser
  defp map(parser, mapper) do
    fn
      input when is_function(mapper, 1) ->
        with {:ok, term, rest} <- parser.(input),
             do: {:ok, mapper.(term), rest}
    end
  end

  @spec replace(parser, term) :: parser
  defp replace(parser, replacement) do
    fn input ->
      case parser.(input) do
        {:ok, _, rest} -> {:ok, replacement, rest}
        {:error, _} = err -> err
      end
    end
  end

  @spec commit(parser, [parser]) :: parser
  # If the first parser succeeds, we will throw an error if the rest of the
  # parsers fail.
  defp commit(commit_parser, seq_parsers) do
    fn input ->
      with {:ok, token, postcommit_rest} <- commit_parser.(input) do
        case sequence(seq_parsers).(postcommit_rest) do
          {:ok, new_tokens, rest} ->
            {:ok, [token | new_tokens], rest}

          {:error, {tag, arg, failed_rest}} ->
            throw({:commit_error, tag, arg, postcommit_rest, failed_rest})
        end
      end
    end
  end

  # -- Helpers ----------------------------------------------------------------
  defp filter_ignored([{:ignore, _} | t]), do: filter_ignored(t)
  defp filter_ignored([h | t]), do: [h | filter_ignored(t)]
  defp filter_ignored([]), do: []
  defp unescape_sequence([?\\, c]), do: convert_escape(c)
  defp convert_escape(?n), do: ?\n
  defp convert_escape(?r), do: ?\r
  defp convert_escape(?t), do: ?\t
  defp convert_escape(?f), do: ?\f
  defp convert_escape(?b), do: ?\b
  defp convert_escape(?"), do: ?\"
  defp convert_escape(?'), do: ?\'
  defp convert_escape(?\\), do: ?\\
  defp convert_escape(other), do: other

  # -- Buffer -----------------------------------------------------------------

  @spec buffer :: buffer
  defp buffer(text, line, column) do
    buffer(text: text, line: line, column: column)
  end

  @spec buffer :: buffer
  defp buffer(buf, text, line, column) do
    buffer(buf, text: text, line: line, column: column)
  end

  @spec empty_buffer?(buffer) :: boolean
  defp empty_buffer?(buffer(text: text)), do: text == ""

  @spec take(buffer) :: {integer, buffer} | :EOI
  defp take(buffer(text: text, line: line, column: column) = buf) do
    case text do
      <<?\n, rest::binary>> -> {?\n, buffer(buf, rest, line + 1, 0)}
      <<char::utf8, rest::binary>> -> {char, buffer(buf, rest, line, column + 1)}
      "" -> :EOI
    end
  end

  @spec consume_string(buffer, binary) :: {:ok, buffer} | :error
  defp consume_string(
         buffer(text: text, line: line, column: column) = buf,
         <<_, _::binary>> = str
       ) do
    size = byte_size(str)

    case text do
      <<^str::binary-size(size), rest::binary>> ->
        {line, column} = next_cursor(str, line, column)
        {:ok, buffer(buf, rest, line, column)}

      _ ->
        :error
    end
  end

  @spec next_cursor(binary, integer, integer) :: {integer, integer}
  defp next_cursor(<<?\n, rest::binary>>, line, _),
    do: next_cursor(rest, line + 1, 0)

  defp next_cursor(<<_::utf8, rest::binary>>, line, column),
    do: next_cursor(rest, line, column + 1)

  defp next_cursor(<<>>, line, column),
    do: {line, column}

  # -- Entrypoint -------------------------------------------------------------

  @impl true
  def parse_file(path) do
    parse(File.read!(path))
  end

  @doc """
  Returns a list of `{key, value}` for all variables in the given content.

  This function only parses strings, and will not attempt to read from a path.

  Each returned value is either a string, or a list of chunks that are either a
  binary or a `{:var, name}` tuple. Those values can be used with
  `Nvir.interpolate_var/2` by providing a resolver calback that returns the
  value of previous variables.

  ### Resolver example

      iex> file_contents = "GREETING=$INTRO $WHO!"
      iex> {:ok, [{"GREETING", template}]} = Nvir.Parser.parse(file_contents)
      iex> resolver = fn
      ...>   "INTRO" -> "Hello"
      ...>   "WHO" -> "World"
      ...> end
      iex> Nvir.interpolate_var(template, resolver)
      "Hello World!"

  When working with the system env you will likely use `&System.get_env(&1, "")`
  as a resolver. It is common to use an empty string for undefined system
  variables, but you can of course raise from your function if it better suits
  your needs.
  """
  @spec parse(binary) :: {:ok, [variable]} | {:error, Exception.t()}
  def parse(input) do
    # path is only used for error reporting here

    buf = buffer(input, 1, 0)
    parser = expressions()

    case do_parse(buf, parser, []) do
      {:ok, tokens} -> {:ok, build_entries(:lists.flatten(tokens))}
      {:error, {_, _, _} = reason} -> {:error, to_error(reason)}
    end
  catch
    {:commit_error, tag, arg, _postcommit_buf, failed_buf} ->
      {:error, to_error({tag, arg, failed_buf})}
  end

  @spec to_error({atom, term, buffer}) :: Exception.t()
  defp to_error({tag, arg, buffer(line: line)}) do
    %Nvir.Parser.ParseError{line: line, tag: tag, arg: arg}
  end

  @spec consume_whitespace(buffer) :: buffer
  defp consume_whitespace(buf) do
    case take(buf) do
      {char, buf} when char in [?\n, ?\t, ?\s, ?\r] -> consume_whitespace(buf)
      _ -> buf
    end
  end

  @spec do_parse(buffer, parser, term) :: {:ok, term} | {:error, term}
  defp do_parse(buf, parser, tokens) do
    buf = consume_whitespace(buf)

    if empty_buffer?(buf) do
      {:ok, tokens}
    else
      case parser.(buf) do
        {:ok, new_tokens, rest} -> do_parse(rest, parser, [tokens, new_tokens])
        {:error, _} = err -> err
      end
    end
  end

  defp build_entries(entries) do
    Enum.map(entries, &build_entry/1)
  end

  defp build_entry({:entry, k, v}), do: {build_key(k), build_value(v)}
  defp build_key(k), do: List.to_string(k)

  defp build_value(v) do
    chunks = v |> :lists.flatten() |> chunk_value([], [])

    if Enum.any?(chunks, &match?({:var, _}, &1)) do
      chunks
    else
      :erlang.iolist_to_binary(chunks)
    end
  end

  # optimization, skip empty chunk
  defp chunk_value([{:var, _} = h | t], [], acc) do
    chunk_value(t, [], [h | acc])
  end

  defp chunk_value([{:var, _} = h | t], chars, acc) do
    chunk_value(t, [], [h, List.to_string(:lists.reverse(chars)) | acc])
  end

  defp chunk_value([h | t], chars, acc) do
    chunk_value(t, [h | chars], acc)
  end

  # optimization, skip empty chunk
  defp chunk_value([], [], acc) do
    :lists.reverse(acc)
  end

  defp chunk_value([], chars, acc) do
    :lists.reverse([List.to_string(:lists.reverse(chars)) | acc])
  end
end
