defmodule Nvir.ParserTest do
  alias Nvir.Parser.ParseError
  use ExUnit.Case, async: false

  doctest Nvir.Parser
  doctest Nvir.Parser.RDB

  defp parse(string) do
    Nvir.Parser.parse_string(string)
  end

  defp parse_map!(string) do
    {:ok, values} = parse(string)
    Map.new(values)
  end

  # We use parse_map! in this test to make it easy, but the parser returns the
  # vars in order
  test "the parser actually returns an ordered list of entries" do
    assert {:ok, entries} =
             parse("""
             K1=v1.1
             K1=v1.2
             K2=v2.1
             K2=v2.2
             """)

    assert is_list(entries)
    assert [{"K1", "v1.1"}, {"K1", "v1.2"}, {"K2", "v2.1"}, {"K2", "v2.2"}] == entries
  end

  test "empty lines" do
    assert %{} == parse_map!("")

    assert %{} ==
             parse_map!("""


             """)
  end

  test "doc test" do
    env = """
    WHO=World
    GREETING=Hello $WHO!
    """

    expected =
      {:ok,
       [
         {"WHO", "World"},
         {"GREETING", ["Hello ", {:var, "WHO"}, "!"]}
       ]}

    assert expected == parse(env)
  end

  test "doc test self interpolate" do
    env = """
    PATH=b
    PATH=$PATH:c
    PATH=a:$PATH
    """

    expected =
      {:ok,
       [
         {"PATH", "b"},
         {"PATH", [{:var, "PATH"}, ":c"]},
         {"PATH", ["a:", {:var, "PATH"}]}
       ]}

    assert expected == parse(env)
  end

  test "can parse a simple line" do
    assert %{"SOME_KEY" => "some value"} = parse_map!("SOME_KEY=some value")
  end

  test "supports utf8" do
    assert %{"HÉHÉ" => "héhé"} = parse_map!("HÉHÉ=héhé")
  end

  test "supports newlines" do
    assert %{"SOME_KEY" => "some value"} =
             parse_map!("""


             SOME_KEY=some value


             """)
  end

  test "supports multiple entries" do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!("""
             K1=v1
             K2=v2
             """)
  end

  test "supports multiple entries with newlines" do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!("""

             K1=v1


             K2=v2

             """)
  end

  test "supports comment lines" do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!("""
             # This is a comment
             K1=v1

             # This is a
             # multiline comment

             K2=v2

             # A final word?
             """)
  end

  test "supports inline comment" do
    assert %{"K1" => "v1", "K2" => "v2", "K3" => "v3", "INCLUDED" => "badline# no space"} =
             parse_map!("""

             K1=v1 # after the line

             INCLUDED=badline# no space

             K2=v2 # after the line too

             K3=v3                  # big space
             """)
  end

  test "supports spaces around keys" do
    assert %{"SOME_KEY" => "some value", "BEFORE" => "some value", "AFTER" => "some value"} =
             parse_map!("""
             SOME_KEY = some value
             BEFORE =some value
             AFTER= some value
             """)
  end

  describe "double quoted strings" do
    test "empty" do
      assert %{"SOME_KEY" => ""} = parse_map!(~S(SOME_KEY=""))
    end

    test "octo" do
      assert %{"SOME_KEY" => "# not a comment"} = parse_map!(~S(SOME_KEY="# not a comment"))
      assert %{"SOME_KEY" => "not a # comment"} = parse_map!(~S(SOME_KEY="not a # comment"))
    end

    test "simple" do
      assert %{"SOME_KEY" => "some value"} = parse_map!(~S(SOME_KEY="some value"))
    end

    test "simple with comment" do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(~S(SOME_KEY="some value"# touching comment))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(~S(SOME_KEY="some value" # spaced comment))
    end

    test "simple on its line" do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!("""
               SOME_KEY="some value"
               """)
    end

    test "escaped \"" do
      # quote at the end
      assert %{"K" => "some \"word\""} = parse_map!(~S(K="some \"word\""))

      # text at the end
      assert %{"K" => "some \"word\" hey"} = parse_map!(~S(K="some \"word\" hey"))
    end

    test "escaped \r", do: assert(%{"K" => "\r"} = parse_map!(~S(K="\r")))
    test "escaped \n", do: assert(%{"K" => "\n"} = parse_map!(~S(K="\n")))
    test "escaped \f", do: assert(%{"K" => "\f"} = parse_map!(~S(K="\f")))
    test "escaped \t", do: assert(%{"K" => "\t"} = parse_map!(~S(K="\t")))
    test "escaped \b", do: assert(%{"K" => "\b"} = parse_map!(~S(K="\b")))
    test "escaped '", do: assert(%{"K" => "'"} = parse_map!(~S(K="\'")))
    test "not escaped '", do: assert(%{"K" => "'"} = parse_map!(~S(K="'")))
    test "escaped \\", do: assert(%{"K" => "\\"} = parse_map!(~S(K="\\")))
    test "unknown escape", do: assert(%{"K" => "a"} = parse_map!(~S(K="\a")))

    test "multi escapes" do
      assert %{
               "SOME_KEY" => "first quoted",
               "SOME_KEY_WITH_ESCAPE" => ~s(say "hello" to the world),
               "SOME_KEY_WITH_ESCAPE_END" => ~s(say "hello"),
               "EMPTY" => ""
             } =
               parse_map!(~S"""
               SOME_KEY="first quoted"
               SOME_KEY_WITH_ESCAPE="say \"hello\" to the world"
               SOME_KEY_WITH_ESCAPE_END="say \"hello\""
               EMPTY="" # comment with " quote
               """)
    end

    test "unfinished quote" do
      assert {:error, _} = parse(~s(SOME_KEY="hello))
      assert {:error, _} = parse(~s(SOME_KEY="hello" ""))
    end
  end

  describe "leading whitespace" do
    test "offset on the key" do
      assert %{"SOME_KEY" => "some value"} = parse_map!("      SOME_KEY=some value")

      assert %{"A" => "1", "B" => "2"} =
               parse_map!("""
                       A=1
               B=2
               """)
    end
  end

  describe "trailing whitespace" do
    test "whitespace before newline is trimmed" do
      assert %{"SOME_KEY" => "some value"} = parse_map!("SOME_KEY=some value    \n")
    end

    test "whitespace is trimmed if there is a comment" do
      assert %{"SOME_KEY" => "some value"} = parse_map!("SOME_KEY=some value    # hello \n")
    end

    test "whitespace only" do
      assert %{"SOME_KEY" => ""} = parse_map!("SOME_KEY=    ")
    end

    test "whitespace is not part of the value if there are quotes" do
      assert %{"SOME_KEY" => "some value"} = parse_map!(~s(SOME_KEY="some value"       ))
      assert %{"SOME_KEY" => "some value"} = parse_map!(~s(SOME_KEY="some value"       \n))
      assert %{"SOME_KEY" => "some value"} = parse_map!(~s(SOME_KEY='some value'       ))
      assert %{"SOME_KEY" => "some value"} = parse_map!(~s(SOME_KEY='some value'       \n))
    end

    test "multiline whitespace is not trimmed" do
      assert %{"SOME_KEY" => "first    \nsecond    \n"} =
               parse_map!(~s(SOME_KEY="""\nfirst    \nsecond    \n"""))

      assert %{"SOME_KEY" => "first    \nsecond    \n"} =
               parse_map!(~s(SOME_KEY='''\nfirst    \nsecond    \n'''))
    end
  end

  describe "empty values" do
    test "raw", do: assert(%{"K" => ""} = parse_map!("K="))
    test "quoted", do: assert(%{"K" => ""} = parse_map!(~s(K="")))
    test "comment", do: assert(%{"K" => ""} = parse_map!(~s(K= #)))

    test "comment touching" do
      # just like raw values, if the octo touches the equal sign, it's the value
      assert %{"K" => "#"} = parse_map!(~s(K=#))
      assert %{"K" => "#hello"} = parse_map!("K=#hello")
    end
  end

  test "'export ' prefix" do
    assert %{"A" => "1", "B" => "2", "C" => "3", "D" => "4"} =
             parse_map!("""
             export A=1
                   export B = 2
             C=3
             export    D=4
             """)
  end

  test "duplicate value takes the last value" do
    assert %{"AA" => "second AA", "BB" => "second BB"} =
             parse_map!("""
             AA = first AA
             BB = first BB
             BB = second BB
             AA = second AA
             """)
  end

  describe "single quoted strings" do
    test "empty" do
      assert %{"SOME_KEY" => ""} = parse_map!(~S(SOME_KEY=''))
    end

    test "octo" do
      assert %{"SOME_KEY" => "# not a comment"} = parse_map!(~S(SOME_KEY='# not a comment'))
      assert %{"SOME_KEY" => "not a # comment"} = parse_map!(~S(SOME_KEY='not a # comment'))
    end

    test "simple" do
      assert %{"SOME_KEY" => "some value"} = parse_map!(~S(SOME_KEY='some value'))
    end

    test "simple with comment" do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(~S(SOME_KEY='some value'# touching comment))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(~S(SOME_KEY='some value' # spaced comment))
    end

    test "simple on its line" do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!("""
               SOME_KEY='some value'
               """)
    end

    test "escaped '" do
      # quote at the end
      assert %{"K" => "some 'word'"} = parse_map!(~S(K='some \'word\''))

      # text at the end
      assert %{"K" => "some 'word' hey"} = parse_map!(~S(K='some \'word\' hey'))
    end

    test "not escaped \r", do: assert(%{"K" => "\\r"} = parse_map!(~S(K='\r')))
    test "not escaped \n", do: assert(%{"K" => "\\n"} = parse_map!(~S(K='\n')))
    test "not escaped \f", do: assert(%{"K" => "\\f"} = parse_map!(~S(K='\f')))
    test "not escaped \t", do: assert(%{"K" => "\\t"} = parse_map!(~S(K='\t')))

    test "not escaped \b", do: assert(%{"K" => "\\b"} = parse_map!(~S(K='\b')))

    test "not escaped \\", do: assert(%{"K" => "\\ aaa"} = parse_map!(~S(K='\ aaa')))

    test "unknown escape", do: assert(%{"K" => "\\a"} = parse_map!(~S(K='\a')))

    test "multi escapes" do
      assert %{
               "SOME_KEY" => "first quoted",
               "SOME_KEY_WITH_ESCAPE" => ~s(say "hello" to the world),
               "SOME_KEY_WITH_ESCAPE_END" => ~s(say "hello"),
               "EMPTY" => ""
             } =
               parse_map!(~S"""
               SOME_KEY='first quoted'
               SOME_KEY_WITH_ESCAPE='say "hello" to the world'
               SOME_KEY_WITH_ESCAPE_END='say "hello"'
               EMPTY='' # comment with ' quote
               """)
    end

    test "unfinished quote" do
      assert {:error, _} = parse(~s(SOME_KEY='hello))
      assert {:error, _} = parse(~s(SOME_KEY='hello' ''))
    end
  end

  describe ~S(multiline strings with """) do
    test "correct" do
      assert %{"MESSAGE" => "Dear World,\nHello!\n"} =
               parse_map!(~S'''
               MESSAGE="""
               Dear World,
               Hello!
               """
               ''')
    end

    test "multiple" do
      assert %{"MESSAGE1" => "Dear World,\nHello!\n", "MESSAGE2" => "\tDear World,\nGoodbye!\n"} =
               parse_map!(~S'''
               MESSAGE1="""
               Dear World,
               Hello!
               """
               MESSAGE2="""
               \tDear World,
               Goodbye!
               """
               ''')
    end

    test "contains quote" do
      assert %{"A" => ~s(on " line\nat end "\n"\ndouble: ""\n)} =
               parse_map!(~S'''
               A="""
               on " line
               at end "
               "
               double: ""
               """
               ''')
    end
  end

  describe ~S(multiline strings with ''') do
    test "correct" do
      assert %{"MESSAGE" => "Dear World,\nHello!\n"} =
               parse_map!(~S"""
               MESSAGE='''
               Dear World,
               Hello!
               '''
               """)
    end

    test "multiple" do
      assert %{"MESSAGE1" => "Dear World,\nHello!\n", "MESSAGE2" => "\\tDear World,\nGoodbye!\n"} =
               parse_map!(~S"""
               MESSAGE1='''
               Dear World,
               Hello!
               '''
               MESSAGE2='''
               \tDear World,
               Goodbye!
               '''
               """)
    end

    test "contains quote" do
      assert %{"A" => ~s(on ' line\nat end '\n'\ndouble: ''\n)} =
               parse_map!(~S"""
               A='''
               on ' line
               at end '
               '
               double: ''
               '''
               """)
    end
  end

  describe "interpolation parsing" do
    test "in raw value" do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!("""
               ENCLOSED=hello ${WHO}
               NODELIM=hello $WHO
               """)

      assert ["hello ", {:var, "WHO"}] == enclosed
      assert ["hello ", {:var, "WHO"}] == nodelim

      assert "hello world" = Nvir.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world" = Nvir.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "in double quoted value" do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!("""
               ENCLOSED="hello ${WHO}"
               NODELIM="hello $WHO"
               """)

      assert ["hello ", {:var, "WHO"}] = enclosed
      assert ["hello ", {:var, "WHO"}] = nodelim

      assert "hello world" = Nvir.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world" = Nvir.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "in double quoted multiline" do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(~S'''
               ENCLOSED="""
               hello ${WHO}
               """
               NODELIM="""
               hello $WHO
               """
               ''')

      assert ["hello ", {:var, "WHO"}, "\n"] == enclosed
      assert ["hello ", {:var, "WHO"}, "\n"] == nodelim

      assert "hello world\n" = Nvir.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world\n" = Nvir.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "double quoted multiline whole line" do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(~S'''
               ENCLOSED="""
               ${WHO}
               """
               NODELIM="""
               $WHO
               """
               ''')

      assert [{:var, "WHO"}, "\n"] == enclosed
      assert [{:var, "WHO"}, "\n"] == nodelim

      assert "world\n" = Nvir.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "world\n" = Nvir.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "in single quoted, no interpolation" do
      assert %{"ENCLOSED" => "hello ${WHO}", "NODELIM" => "hello $WHO"} =
               parse_map!("""
               ENCLOSED='hello ${WHO}'
               NODELIM='hello $WHO'
               """)
    end

    test "in single quoted multiline, no interpolation" do
      assert %{"ENCLOSED" => "hello ${WHO}\n", "NODELIM" => "hello $WHO\n"} =
               parse_map!("""
               ENCLOSED='''
               hello ${WHO}
               '''
               NODELIM='''
               hello $WHO
               '''
               """)
    end

    defp build_sentence(map, vars) do
      Nvir.interpolate_var(Map.fetch!(map, "SENTENCE"), fn key -> Map.get(vars, key, "") end)
    end

    test "edge case - vars on both ends" do
      # test for removing empty chunks
      assert "hello world" =
               "SENTENCE=$GREETING $WHO"
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "hello world" =
               ~s(SENTENCE="$GREETING $WHO")
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "var touching comment, still included in the values just like raw files" do
      assert "world#this is a comment" =
               "SENTENCE=$WHO#this is a comment"
               |> parse_map!()
               |> build_sentence(%{"WHO" => "world"})

      # If the comment is spaces, it is not included in the value
      assert "world" =
               "SENTENCE=$WHO #this is a comment"
               |> parse_map!()
               |> build_sentence(%{"WHO" => "world"})

      # Quotes protect comments from touching
      assert "world" =
               ~s(SENTENCE="$WHO"#this is a comment)
               |> parse_map!()
               |> build_sentence(%{"WHO" => "world"})

      # Enclosing does not
      assert "world#this is a comment" =
               "SENTENCE=${WHO}#this is a comment"
               |> parse_map!()
               |> build_sentence(%{"WHO" => "world"})
    end

    test "edge case - vars touching" do
      assert "helloworld" =
               "SENTENCE=$GREETING$WHO"
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "helloworld" =
               ~s(SENTENCE="$GREETING$WHO")
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "edge case - enclosed vars touching" do
      assert "helloworld" =
               "SENTENCE=${GREETING}${WHO}"
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "helloworld" =
               ~s(SENTENCE="${GREETING}${WHO}")
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "edge case - vars and dollar" do
      assert "$hello" =
               "SENTENCE=$$GREETING"
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello"})

      assert "$hello" =
               ~s(SENTENCE="$$GREETING")
               |> parse_map!()
               |> build_sentence(%{"GREETING" => "hello"})
    end

    test "edge case - empty enclosure" do
      assert "no---space" =
               "SENTENCE=no${}space"
               |> parse_map!()
               |> build_sentence(%{"" => "---"})

      assert "no---space" =
               ~s(SENTENCE="no${}space")
               |> parse_map!()
               |> build_sentence(%{"" => "---"})
    end
  end

  defp valid_parse_error!(e) do
    msg = Exception.message(e)
    refute msg =~ "retrieving Exception.message/1"
    e
  end

  describe "parse errors" do
    test "no value" do
      assert {:error, parse_error} =
               parse(~S'''
               A=1
               B="""
               ''')

      assert %ParseError{line: 3} = parse_error

      valid_parse_error!(parse_error)
    end
  end
end
