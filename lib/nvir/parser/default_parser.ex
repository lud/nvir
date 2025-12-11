defmodule Nvir.Parser.DefaultParser do
  @behaviour Nvir.Parser
  @moduledoc """
  The default parser implementation for dotenv files.
  """

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

  defguard is_key_char(c)
           when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_ or c in @accented

  defguard is_start_key_char(c)
           when c in ?A..?Z or c in ?a..?z or c == ?_

  defguard is_whitespace(c) when c in [?\s, ?\t]

  defguard is_raw_char(c)
           when not is_whitespace(c) and c not in [?\n, ?#, ?", ?', ?$] and not is_whitespace(c)

  @impl true
  def parse_file(path) do
    path
    |> File.read!()
    |> parse_string(path)
  end

  def parse_string(content, source_path \\ "(nofile)") when is_binary(content) do
    tokens = tokenize(content)
    entries = parse(tokens)
    {:ok, entries}
  catch
    {:parse_error, line, col, errmsg} ->
      {:error, convert_error(line, col, errmsg, content, source_path)}
  end

  defp convert_error(line, col, errmsg, content, source_path) do
    error = %Nvir.Parser.ParseError{
      line: line,
      col: col,
      errmsg: errmsg,
      source: source_path
    }

    attach_error_content(error, content)
  end

  if Application.compile_env!(:nvir, :display_file_contents_in_errors) == true do
    defp attach_error_content(error, content) do
      Nvir.Parser.ParseError.with_debug_content(error, content)
    end
  else
    defp attach_error_content(error, _content) do
      error
    end
  end

  # ---------------------------------------------------------------------------
  #                                 Tokenizer
  # ---------------------------------------------------------------------------

  defp tokenize(string) do
    tokenize(string, 1, 1, [])
  end

  defp tokenize(<<>>, _line, _col, tokens) do
    :lists.reverse(tokens)
  end

  defp tokenize(<<c::utf8, rest::binary>>, line, col, tokens) when is_start_key_char(c) do
    {val_rest, col, rest} = take_key_chars(rest, col + 1, [])
    val = <<c::utf8, val_rest::binary>>
    tokens = [{:keychars, {line, col}, val} | tokens]
    tokenize(rest, line, col, tokens)
  end

  defp tokenize(<<?\n, rest::binary>>, line, col, tokens) do
    tokens = [{:newline, {line, col}} | tokens]
    tokenize(rest, line + 1, 1, tokens)
  end

  defp tokenize(<<?=, rest::binary>>, line, col, tokens) do
    tokens = [{:assign_op, {line, col}} | tokens]
    tokenize(rest, line, col + 1, tokens)
  end

  # Dollar with chars behind
  defp tokenize(<<?$, c::utf8, rest::binary>>, line, col, tokens)
       when is_start_key_char(c)
       when c == ?{ do
    {varname, next_col, rest} = take_variable(<<c::utf8, rest::binary>>, line, col + 1)

    tokens = [{:varname, {line, col + 1}, varname}, {:dollar, {line, col}} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  # Dollar ignored in other cases
  defp tokenize(<<?$, rest::binary>>, line, col, tokens) do
    tokens = [{:rawchars, {line, col}, "$"} | tokens]
    tokenize(rest, line, col + 1, tokens)
  end

  defp tokenize(<<?#, rest::binary>>, line, col, tokens) do
    {val_rest, next_col, rest} = take_comment(rest, col + 1, [])
    val = <<?#, val_rest::binary>>
    tokens = [{:comment, {line, col}, val} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  defp tokenize(<<?", ?", ?", rest::binary>>, line, col, tokens) do
    rest =
      case rest do
        <<?\n, string_start::binary>> ->
          string_start

        <<>> ->
          throw({:parse_error, line, col + 3, "unexpected eof after multiline string start"})

        <<_char, _::binary>> ->
          throw(
            {:parse_error, line, col + 3, "unexpected character after multiline string start"}
          )
      end

    # Double quote values are always wrapped in a list as they can contain
    # variable interpolation

    {val, next_line, next_col, rest} = take_double_quoted_multi(rest, line + 1, 1, [])
    tokens = [{:dquoted_list, {line, col}, val} | tokens]
    tokenize(rest, next_line, next_col, tokens)
  end

  defp tokenize(<<?", rest::binary>>, line, col, tokens) do
    {val, next_col, rest} = take_double_quoted(rest, line, col + 1, [])
    tokens = [{:dquoted_list, {line, col}, val} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  defp tokenize(<<?', ?', ?', rest::binary>>, line, col, tokens) do
    rest =
      case rest do
        <<?\n, string_start::binary>> ->
          string_start

        <<>> ->
          throw({:parse_error, line, col + 3, "unexpected eof after multiline string start"})

        <<_char, _::binary>> ->
          throw(
            {:parse_error, line, col + 3, "unexpected character after multiline string start"}
          )
      end

    {val, next_line, next_col, rest} = take_single_quoted_multi(rest, line + 1, 1, [])
    # we keep all comment chars because they can be part of a value
    tokens = [{:squoted, {line, col}, val} | tokens]
    tokenize(rest, next_line, next_col, tokens)
  end

  defp tokenize(<<?', rest::binary>>, line, col, tokens) do
    {val, next_col, rest} = take_single_quoted(rest, line, col + 1, [])
    # we keep all comment chars because they can be part of a value
    tokens = [{:squoted, {line, col}, val} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  defp tokenize(<<c::utf8, rest::binary>>, line, col, tokens) when is_raw_char(c) do
    {val_rest, next_col, rest} = take_raw_chars(rest, col + 1, [])
    val = <<c::utf8, val_rest::binary>>
    tokens = [{:rawchars, {line, col}, val} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  defp tokenize(<<c::utf8, rest::binary>>, line, col, tokens) when is_whitespace(c) do
    {val_rest, next_col, rest} = take_whitespace(rest, col + 1, [])
    val = <<c::utf8, val_rest::binary>>
    tokens = [{:ws, {line, col}, val} | tokens]
    tokenize(rest, line, next_col, tokens)
  end

  # -- Key Chars --------------------------------------------------------------

  defp take_key_chars(<<c::utf8, rest::binary>>, col, acc) when is_key_char(c) do
    take_key_chars(rest, col + 1, [c | acc])
  end

  defp take_key_chars(rest, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col, rest}
  end

  # -- Raw Chars --------------------------------------------------------------

  defp take_raw_chars(<<c::utf8, rest::binary>>, col, acc) when is_raw_char(c) do
    take_raw_chars(rest, col + 1, [c | acc])
  end

  defp take_raw_chars(rest, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col, rest}
  end

  # -- Whitespace -------------------------------------------------------------

  defp take_whitespace(<<c::utf8, rest::binary>>, col, acc) when is_whitespace(c) do
    take_whitespace(rest, col + 1, [c | acc])
  end

  defp take_whitespace(rest, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col, rest}
  end

  # -- Comment ----------------------------------------------------------------

  defp take_comment(<<?\n, _::binary>> = rest, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col, rest}
  end

  defp take_comment(<<>>, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col, <<>>}
  end

  defp take_comment(<<c::utf8, rest::binary>>, col, acc) do
    take_comment(rest, col + 1, [c | acc])
  end

  # -- Single Line Double Quoted ----------------------------------------------

  # This function returns a raw list to support variable interpolation

  defp take_double_quoted(<<?\n, _::binary>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected newline in double quoted string"})
  end

  defp take_double_quoted(<<?\\, c::utf8, rest::binary>>, line, col, acc) do
    take_double_quoted(rest, line, col + 2, [unescape(c) | acc])
  end

  defp take_double_quoted(<<?$, c::utf8, rest::binary>>, line, col, acc)
       when is_start_key_char(c)
       when c == ?{ do
    {varname, col, rest} = take_variable(<<c::utf8, rest::binary>>, line, col + 1)
    # The variable will be added in the characters accumulator, this is a
    # special case.
    #
    # We will return the same form as in the parser step, a 2-tuple
    take_double_quoted(rest, line, col, [{:var, varname} | acc])
  end

  defp take_double_quoted(<<?", rest::binary>>, _line, col, acc) do
    val = :lists.reverse(acc)
    {val, col + 1, rest}
  end

  defp take_double_quoted(<<c::utf8, rest::binary>>, line, col, acc) do
    take_double_quoted(rest, line, col + 1, [c | acc])
  end

  defp take_double_quoted(<<>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected eof in double quoted string"})
  end

  # -- Multi Line Double Quoted -----------------------------------------------

  # This function returns a raw list to support variable interpolation

  defp take_double_quoted_multi(<<?\n, rest::binary>>, line, _col, acc) do
    take_double_quoted_multi(rest, line + 1, 1, [?\n | acc])
  end

  defp take_double_quoted_multi(<<?\\, c::utf8, rest::binary>>, line, col, acc) do
    take_double_quoted_multi(rest, line, col + 2, [unescape(c) | acc])
  end

  defp take_double_quoted_multi(<<?$, c::utf8, rest::binary>>, line, col, acc)
       when is_start_key_char(c)
       when c == ?{ do
    {varname, col, rest} = take_variable(<<c::utf8, rest::binary>>, line, col + 1)
    # Same as single-line for interpolation
    take_double_quoted_multi(rest, line, col, [{:var, varname} | acc])
  end

  defp take_double_quoted_multi(<<?", ?", ?", rest::binary>>, line, col, acc) do
    val = :lists.reverse(acc)
    {val, line, col + 3, rest}
  end

  defp take_double_quoted_multi(<<c::utf8, rest::binary>>, line, col, acc) do
    take_double_quoted_multi(rest, line, col + 1, [c | acc])
  end

  defp take_double_quoted_multi(<<>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected eof in multiline double quoted string"})
  end

  # -- Single Line Double Quoted ----------------------------------------------

  defp take_single_quoted(<<?\n, _::binary>> = _rest, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected newline in single quoted string"})
  end

  defp take_single_quoted(<<?\\, ?', rest::binary>>, line, col, acc) do
    take_single_quoted(rest, line, col + 2, [?' | acc])
  end

  defp take_single_quoted(<<?', rest::binary>>, _line, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col + 1, rest}
  end

  defp take_single_quoted(<<c::utf8, rest::binary>>, line, col, acc) do
    take_single_quoted(rest, line, col + 1, [c | acc])
  end

  defp take_single_quoted(<<>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected eof in single quoted string"})
  end

  # -- Multi Line Single Quoted -----------------------------------------------

  defp take_single_quoted_multi(<<?\n, rest::binary>>, line, _col, acc) do
    take_single_quoted_multi(rest, line + 1, 1, [?\n | acc])
  end

  defp take_single_quoted_multi(<<?\\, ?', rest::binary>>, line, col, acc) do
    take_single_quoted_multi(rest, line, col + 2, [?' | acc])
  end

  defp take_single_quoted_multi(<<?\\, ?\\, rest::binary>>, line, col, acc) do
    take_single_quoted_multi(rest, line, col + 2, [?\\ | acc])
  end

  defp take_single_quoted_multi(<<?\\, c::utf8, rest::binary>>, line, col, acc) do
    take_single_quoted_multi(rest, line, col + 2, [c, ?\\ | acc])
  end

  defp take_single_quoted_multi(<<?', ?', ?', rest::binary>>, line, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, line, col + 3, rest}
  end

  defp take_single_quoted_multi(<<c::utf8, rest::binary>>, line, col, acc) do
    take_single_quoted_multi(rest, line, col + 1, [c | acc])
  end

  defp take_single_quoted_multi(<<>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected eof in multiline single quoted string"})
  end

  # -- Variable Parse ---------------------------------------------------------

  defp take_variable(<<?{, rest::binary>>, line, col) do
    take_enclosed_var(rest, line, col + 1, [])
  end

  defp take_variable(<<c::utf8, rest::binary>>, _line, col) when is_key_char(c) do
    {varname_rest, col, rest} = take_key_chars(rest, col + 1, [])
    {<<c::utf8, varname_rest::binary>>, col, rest}
  end

  # the opening curly brace is already removed

  defp take_enclosed_var(<<c, _::binary>>, line, col, _acc) when is_whitespace(c) do
    throw({:parse_error, line, col, "unexpected whitespace in variable braces"})
  end

  defp take_enclosed_var(<<?\n, _::binary>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected newline in variable braces"})
  end

  defp take_enclosed_var(<<?}, rest::binary>>, _line, col, acc) do
    val = List.to_string(:lists.reverse(acc))
    {val, col + 1, rest}
  end

  defp take_enclosed_var(<<c::utf8, rest::binary>>, line, col, acc) when is_key_char(c) do
    take_enclosed_var(rest, line, col + 1, [c | acc])
  end

  defp take_enclosed_var(<<_bad_char::utf8, _::binary>>, line, col, _acc) do
    throw({:parse_error, line, col, "invalid variable name"})
  end

  defp take_enclosed_var(<<>>, line, col, _acc) do
    throw({:parse_error, line, col, "unexpected eof in variable braces"})
  end

  # -----

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp unescape(c) do
    case c do
      ?n -> ?\n
      ?r -> ?\r
      ?t -> ?\t
      ?f -> ?\f
      ?b -> ?\b
      ?" -> ?\"
      ?' -> ?\'
      ?\\ -> ?\\
      other -> other
    end
  end

  # ---------------------------------------------------------------------------
  #                                   Parser
  # ---------------------------------------------------------------------------

  def parse(tokens) do
    tokens
    |> Enum.chunk_by(fn
      {:newline, _} -> true
      _ -> false
    end)
    |> Enum.filter(fn
      [{:newline, _} | _] -> false
      # a chunk made of whitespace/comment only
      [{:ws, _, _}] -> false
      [{:comment, _, _}] -> false
      [{:ws, _, _}, {:comment, _, _}] -> false
      _ -> true
    end)
    |> Enum.map(&parse_definition/1)
  end

  defp parse_definition(tokens) do
    {key, tokens} = parse_key(tokens)
    {value, tokens} = parse_value(tokens, [])

    :ok =
      case tokens do
        [] ->
          :ok

        [{:ws, _, _}, {:comment, _, _}] ->
          :ok

        [{tag, {line, col}, _value} | _] ->
          throw({:parse_error, line, col, "unexpected token #{tag}"})

        [{tag, {line, col}} | _] ->
          throw({:parse_error, line, col, "unexpected token #{tag}"})
      end

    {key, value}
  end

  defp parse_key(tokens) do
    {key, tokens} =
      case skip_ws_token(tokens) do
        [{:keychars, _, "export"}, {:ws, _, _}, {:keychars, _, key} | rest] -> {key, rest}
        [{:keychars, _, key} | rest] -> {key, rest}
      end

    tokens =
      case skip_ws_token(tokens) do
        [{:assign_op, _} | rest] -> rest
      end

    # no skip after the assign op
    {key, tokens}
  end

  defp skip_ws_token([{:ws, _, _} | rest]) do
    rest
  end

  defp skip_ws_token(tokens) do
    tokens
  end

  # Skips optional WS and/or comment, but in that order only

  defp skip_ws_comment_token([{:ws, _, _} | rest]) do
    skip_ws_comment_token(rest)
  end

  defp skip_ws_comment_token([{:comment, _, _} | rest]) do
    rest
  end

  defp skip_ws_comment_token(rest) do
    rest
  end

  defp parse_value([{tag, _, val} | tokens], acc) when tag in [:keychars, :rawchars] do
    parse_value(tokens, [val | acc])
  end

  defp parse_value([{:squoted, _, val} | tokens], []) do
    tokens = skip_ws_comment_token(tokens)

    {val, tokens}
  end

  defp parse_value([{:dquoted_list, _, val} | tokens], []) do
    tokens = skip_ws_comment_token(tokens)

    {build_value(val), tokens}
  end

  # whitespace+comment when acc is empty can be skipped
  defp parse_value([{:ws, _, _}, {:comment, _, _} | tokens], [] = acc) do
    parse_value(tokens, acc)
  end

  # whitespace when acc is empty can be skipped
  defp parse_value([{:ws, _, _} | tokens], [] = acc) do
    parse_value(tokens, acc)
  end

  # whitespace followed by comment is not part of the value
  # we return the ws and comment tokens
  defp parse_value([{:ws, _, _}, {:comment, _, _} | _] = all_tokens, acc) do
    {rev_build_value(acc), all_tokens}
  end

  # whitespace followed by value is used
  defp parse_value([{:ws, _, val} | [_next | _] = tokens], acc) do
    parse_value(tokens, [val | acc])
  end

  # trailing whitespace
  defp parse_value([{:ws, _, _}], acc) do
    parse_value([], acc)
  end

  # comment at the head of the list means previous tokens were not whitespace,
  # it is part of the value
  defp parse_value([{:comment, _, val} | tokens], acc) do
    parse_value(tokens, [val | acc])
  end

  defp parse_value([{:dollar, _}, {:varname, _, key} | tokens], acc) do
    parse_value(tokens, [{:var, key} | acc])
  end

  defp parse_value([], acc) do
    {rev_build_value(acc), []}
  end

  defp parse_value([_ | _] = unexpected_tokens, _acc) do
    {[], unexpected_tokens}
  end

  defp build_value(acc) do
    case concat_value(acc) do
      # we respect the original parser output, if there is only a single
      # binary string after concatenation it is unwrapped from a list.
      [single] when is_binary(single) -> single
      # no tokens after assign op is an empty value
      [] -> ""
      list -> list
    end
  end

  defp rev_build_value(acc) do
    build_value(:lists.reverse(acc))
  end

  defp concat_value([a, b | t]) when is_binary(a) and is_binary(b) do
    concat_value([<<a::binary, b::binary>> | t])
  end

  defp concat_value([a, b | t]) when is_integer(a) and is_integer(b) do
    concat_value([<<a::utf8, b::utf8>> | t])
  end

  defp concat_value([a, b | t]) when is_binary(a) and is_integer(b) do
    concat_value([<<a::binary, b::utf8>> | t])
  end

  defp concat_value([c]) when is_integer(c) do
    [<<c>>]
  end

  defp concat_value([h | t]) do
    [h | concat_value(t)]
  end

  defp concat_value([]) do
    []
  end
end
