# credo:disable-for-this-file Credo.Check.Refactor.Nesting

defmodule Nvir.Parser do
  @moduledoc """
  A simple .env file parser.
  """

  require Record
  # TODO unused level ?
  Record.defrecord(:buffer, [:text, :line, :column, :level, :stack])

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

  defmacro debug(label \\ nil, function) do
    {callsite_fun, arity} = __CALLER__.function

    label =
      case label do
        nil ->
          case function do
            {:fn, _, _} -> callsite_fun
            _ -> Macro.to_string(function)
          end

        _ ->
          label
      end

    if Mix.env() == :prod do
      IO.warn(
        "debug called for #{callsite_fun}/#{arity} in :prod compile environment",
        __CALLER__
      )

      quote do
        unquote(function)
      end
    else
      Module.put_attribute(__CALLER__.module, :verbose_dbg, true)

      quote do
        fn the_input ->
          text = elem(the_input, 1)
          label = unquote(label)

          IO.puts("#{indentation(the_input)}#{inspect(label)} #{inspect(text)}")
          the_input = bufdown(the_input, unquote(label))
          sub = unquote(function)
          retval = sub.(the_input)

          case retval do
            {:ok, retval, rest} ->
              IO.puts("#{indentation(rest)}=> #{inspect(label)} = #{inspect(retval)}")
              rest = bufup(rest)
              {:ok, retval, rest}

            {:error, reason} = err when is_binary(reason) ->
              IO.puts("#{indentation(the_input, -1)}/#{unquote(label)} FAIL: #{inspect(reason)}")
              err
          end
        end
      end
    end
  end

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

  defp newline do
    char(?\n)
  end

  defp comment_line do
    sequence([
      many0(space()),
      char(?#),
      many0(not_char(?\n)),
      char(?\n)
    ])
  end

  defp ignore_spaces do
    tag_ignore(many0(space()))
  end

  defp key_char do
    char([?A..?Z, ?a..?z, ?0..?9, ?_] ++ @accented)
  end

  defp key do
    many1(key_char())
  end

  defp value do
    choice([
      raw_value_opt_comment_eol(),
      double_quoted_string_opt_comment(),
      single_quoted_string_opt_comment(),
      multiline_double_quoted_string(),
      multiline_single_quoted_string()
    ])
  end

  defp raw_value_opt_comment_eol do
    sequence([
      many0(
        choice([
          interpolation_variable(),
          tag_ignore(sequence([many1(space()), char(?#), many0(not_eol())])),
          not_char([?", ?', ?\n])
        ])
      )
      |> skip_ignored(),
      tag_ignore(eol())
    ])
    |> skip_ignored()
  end

  defp double_quoted_string_opt_comment do
    sequence([
      tag_ignore(char(?")),
      many0(char_in_double_quotes()),
      tag_ignore(char(?")),
      tag_ignore(maybe(comment_after_quote())),
      tag_ignore(eol())
    ])
    |> skip_ignored()
  end

  defp char_in_double_quotes(allow_double_quote? \\ false) do
    bad_chars = [?\n]
    bad_chars = if allow_double_quote?, do: bad_chars, else: [?" | bad_chars]

    choice([
      interpolation_variable(),
      map(sequence([char(?\\), char()]), &unescape_sequence/1),
      not_char(bad_chars)
    ])
  end

  defp multiline_double_quoted_string do
    sequence([
      tag_ignore(string(~s("""\n))),
      many0(
        sequence([
          lookahead_not(string(~s("""))),
          many0(char_in_double_quotes(true)),
          eol()
        ])
      ),
      tag_ignore(string(~s("""\n)))
    ])
    |> skip_ignored()
  end

  defp interpolation_variable do
    choice([
      sequence([char(?$), key(), lookahead_not(key_char())])
      |> map(fn [_, key, _] -> {:getvar, List.to_string(key)} end),
      sequence([char(?$), char(?{), key(), char(?})])
      |> map(fn [_, _, key, _] -> {:getvar, List.to_string(key)} end),
      # Empty key, for backward compatibility
      sequence([char(?$), char(?{), char(?})])
      |> map(fn _ -> {:getvar, ""} end)
    ])
  end

  defp single_quoted_string_opt_comment do
    sequence([
      tag_ignore(char(?')),
      many0(char_in_single_quotes()),
      tag_ignore(char(?')),
      tag_ignore(maybe(comment_after_quote())),
      tag_ignore(eol())
    ])
    |> skip_ignored()
  end

  defp char_in_single_quotes(allow_single_quote? \\ false) do
    bad_chars = [?\n]
    bad_chars = if allow_single_quote?, do: bad_chars, else: [?' | bad_chars]

    choice([
      replace(string("\\'"), ?'),
      not_char(bad_chars)
    ])
  end

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
      tag_ignore(string(~s('''\n)))
    ])
    |> skip_ignored()
  end

  defp comment_after_quote do
    sequence([
      many0(space()),
      char(?#),
      many0(not_eol())
    ])
  end

  defp space do
    char(?\s)
  end

  defp eol do
    char(?\n)
  end

  defp not_eol do
    not_char(?\n)
  end

  defp satisfy(parser, acceptor) do
    fn input ->
      with {:ok, term, rest} <- parser.(input) do
        if acceptor.(term),
          do: {:ok, term, rest},
          else: {:error, {:predicate, input}}
      end
    end
  end

  defp lookahead_not(parser) do
    fn input ->
      case parser.(input) do
        {:ok, _, _} -> {:error, {:lookahead_not, input}}
        {:error, _} -> {:ok, [], input}
      end
    end
  end

  defp char(expected), do: satisfy(char(), fn char -> char_match?(char, expected) end)

  defp char_match?(char, codepoint) when is_integer(codepoint), do: char == codepoint
  defp char_match?(char, list) when is_list(list), do: Enum.any?(list, &char_match?(char, &1))
  defp char_match?(char, _.._//_ = range), do: char in range

  defp char_match?(char, f) when is_function(f, 1) do
    case f.(char) do
      true -> true
      false -> false
    end
  end

  defp string(expected) do
    fn input ->
      case consume_string(input, expected) do
        {:ok, rest} -> {:ok, expected, rest}
        :error -> {:error, {:string_nomtach, expected, input}}
      end
    end
  end

  defp not_char(rejected),
    do: satisfy(char(), fn char -> not char_match?(char, rejected) end)

  defp char do
    fn input ->
      case take(input) do
        :EOI -> {:error, {:EOI, input}}
        {char, buf} -> {:ok, char, buf}
      end
    end
  end

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

  defp choice(parsers, prev_reason \\ nil) do
    fn input ->
      case parsers do
        [] ->
          {:error, prev_reason}

        [first_parser | other_parsers] ->
          with {:error, reason} <- first_parser.(input),
               do: choice(other_parsers, reason).(input)
      end
    end
  end

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

  defp maybe(parser) do
    fn input ->
      case parser.(input) do
        {:error, _reason} -> {:ok, [], input}
        {:ok, term, rest} -> {:ok, [term], rest}
      end
    end
  end

  defp tag_ignore(parser) do
    map(parser, &{:ignore, &1})
  end

  defp skip_ignored(parser) do
    map(parser, &filter_ignored/1)
  end

  defp map(parser, mapper) do
    fn
      input when is_function(mapper, 1) ->
        with {:ok, term, rest} <- parser.(input),
             do: {:ok, mapper.(term), rest}
    end
  end

  defp replace(parser, replacement) do
    fn input ->
      case parser.(input) do
        {:ok, _, rest} -> {:ok, replacement, rest}
        {:error, _} = err -> err
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

  defp buffer(text, line, column) do
    buffer(text: text, line: line, column: column, level: 0, stack: [])
  end

  defp buffer(buf, text, line, column) do
    buffer(buf, text: text, line: line, column: column)
  end

  defp empty_buffer?(buffer(text: text)), do: text == ""

  defp take(buffer(text: text, line: line, column: column) = buf) do
    case text do
      <<?\n, rest::binary>> -> {?\n, buffer(buf, rest, line + 1, 0)}
      <<char::utf8, rest::binary>> -> {char, buffer(buf, rest, line, column + 1)}
      "" -> :EOI
    end
  end

  defp consume_string(
         buffer(text: text, line: line, column: column) = buf,
         <<_, _::binary>> = str
       ) do
    case text do
      <<^str::binary, rest::binary>> ->
        {line, column} = next_cursor(str, line, column)
        {:ok, buffer(buf, rest, line, column)}

      _ ->
        :error
    end
  end

  defp next_cursor(<<?\n, rest::binary>>, line, _),
    do: next_cursor(rest, line + 1, 0)

  defp next_cursor(<<_::utf8, rest::binary>>, line, column),
    do: next_cursor(rest, line, column + 1)

  defp next_cursor(<<>>, line, column),
    do: {line, column}

  if Module.get_attribute(__MODULE__, :verbose_dbg) do
    defp bufdown(buffer(level: level, stack: stack) = buf, fun),
      do: buffer(buf, level: level + 1, stack: [fun | stack])

    defp bufup(buffer(level: level) = buf) when level > 0, do: buffer(buf, level: level - 1)
    defp indentation(_, add \\ 0)
    defp indentation(buffer(level: level), add), do: indentation(level, add)
    defp indentation(level, add), do: String.duplicate("  ", level + add)
  end

  # -- Entrypoint -------------------------------------------------------------

  @doc """
  Returns a list of `{key, value}` for all variables in the given content.

  This function only parses strings, and will not attempt to read from the given
  `path`. The `path` variable is only useful to give more information when an
  error is returned.
  """
  def parse(input, path \\ "(nofile)") do
    # path is only used for error reporting here
    input = input <> "\n"
    buf = buffer(input, 1, 0)
    parser = expressions()

    case do_parse(buf, parser, []) do
      {:ok, tokens} -> {:ok, build_entries(:lists.flatten(tokens))}
      {:error, reason} -> {:error, to_error(reason, path)}
    end
  end

  defp to_error({tag, arg, buffer(line: line)}, path) do
    %Nvir.ParseError{line: line, tag: tag, arg: arg, path: path}
  end

  defp consume_whitespace(buf) do
    case take(buf) do
      {char, buf} when char in [?\n, ?\t, ?\s, ?\r] -> consume_whitespace(buf)
      _ -> buf
    end
  end

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
    chunks = chunk_value(:lists.flatten(v), [], [])

    if Enum.any?(chunks, &match?({:getvar, _}, &1)) do
      fn get_var -> interpolate_var(chunks, get_var) end
    else
      :erlang.iolist_to_binary(chunks)
    end
  end

  # optimization, skip empty chunk
  defp chunk_value([{:getvar, _} = h | t], [], acc) do
    chunk_value(t, [], [h | acc])
  end

  defp chunk_value([{:getvar, _} = h | t], chars, acc) do
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

  defp interpolate_var(chunks, get_var) do
    :erlang.iolist_to_binary(interpolate_chunks(chunks, get_var))
  end

  defp interpolate_chunks([{:getvar, key} | t], get_var) do
    chunk_value =
      case get_var.(key) do
        {:ok, value} when is_binary(value) -> value
        :error -> ""
      end

    [chunk_value | interpolate_chunks(t, get_var)]
  end

  defp interpolate_chunks([h | t], get_var) do
    [h | interpolate_chunks(t, get_var)]
  end

  defp interpolate_chunks([], _get_var) do
    []
  end
end
