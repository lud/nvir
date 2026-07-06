defmodule Nvir.ParserTest do
  alias Nvir.Parser
  alias Nvir.Parser.ParseError

  use ExUnit.Case,
    async: false,
    parameterize: [
      # TODO remove parameterizing
      %{parser: Nvir.Parser.DefaultParser}
    ]

  doctest Nvir.Parser

  defp parse(parser, string) do
    # IO.puts("--------- PARSING -------")

    # if String.printable?(string) do
    #   IO.puts(string)
    # else
    #   IO.puts("NOT PRINTABLE")
    # end

    # IO.puts("-------------------------")
    parser.parse_string(string)
  end

  defp parse_map!(parser, string) do
    {:ok, values} = parse(parser, string)
    Map.new(values)
  end

  defp parse_map_with!(string, parser) do
    parse_map!(parser, string)
  end

  # The items are returned in order of definition
  test "the parser actually returns an ordered list of entries", %{parser: parser} do
    assert {:ok, entries} =
             parse(parser, """
             K1=v1.1
             K1=v1.2
             K2=v2.1
             K2=v2.2
             """)

    assert is_list(entries)
    assert [{"K1", "v1.1"}, {"K1", "v1.2"}, {"K2", "v2.1"}, {"K2", "v2.2"}] == entries
  end

  test "empty lines", %{parser: parser} do
    assert %{} == parse_map!(parser, "")

    assert %{} ==
             parse_map!(parser, """
             #{"    "}

             """)
  end

  test "doc test", %{parser: parser} do
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

    assert expected == parse(parser, env)
  end

  test "doc test self interpolate", %{parser: parser} do
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

    assert expected == parse(parser, env)
  end

  test "can parse a simple line", %{parser: parser} do
    assert %{"SOME_KEY" => "some value"} = parse_map!(parser, "SOME_KEY=some value")
  end

  test "supports utf8", %{parser: parser} do
    assert %{"HÉHÉ" => "héhé"} = parse_map!(parser, "HÉHÉ=héhé")
  end

  test "supports newlines", %{parser: parser} do
    assert %{"SOME_KEY" => "some value"} =
             parse_map!(parser, """


             SOME_KEY=some value


             """)
  end

  test "supports multiple entries", %{parser: parser} do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!(parser, """
             K1=v1
             K2=v2
             """)
  end

  test "supports multiple entries with newlines", %{parser: parser} do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!(parser, """

             K1=v1


             K2=v2

             """)
  end

  test "supports comment lines", %{parser: parser} do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!(parser, """
             # This is a comment
             K1=v1

             # This is a
             # multiline comment

             K2=v2

             # A final word?
             """)
  end

  test "supports comment lines without final newline", %{parser: parser} do
    assert %{"K1" => "v1", "K2" => "v2"} =
             parse_map!(parser, """
             # This is a comment
             K1=v1

             # This is a
             # multiline comment

             K2=v2

             # A final word? \
             """)
  end

  test "supports inline comment", %{parser: parser} do
    assert %{"K1" => "v1", "K2" => "v2", "K3" => "v3", "INCLUDED" => "badline# no space"} =
             parse_map!(parser, """

             K1=v1 # after the line

             INCLUDED=badline# no space

             K2=v2 # after the line too

             K3=v3                  # big space
             """)
  end

  test "supports comment lines at the end", %{parser: parser} do
    assert %{"GITHUB_API_TOKEN" => "some-token"} =
             parse_map!(parser, """
             GITHUB_API_TOKEN=some-token
             # BROWSER=
             """)

    assert %{"GITHUB_API_TOKEN" => "some-token"} =
             parse_map!(parser, """
             GITHUB_API_TOKEN=some-token
             # BROWSER=\
             """)

    assert %{"GITHUB_API_TOKEN" => "some-token"} =
             parse_map!(parser, """
             GITHUB_API_TOKEN=some-token
             # BROWSER=    \
             """)
  end

  test "supports spaces around keys", %{parser: parser} do
    assert %{"SOME_KEY" => "some value", "BEFORE" => "some value", "AFTER" => "some value"} =
             parse_map!(parser, """
             SOME_KEY = some value
             BEFORE =some value
             AFTER= some value
             """)
  end

  describe "double quoted strings" do
    test "empty", %{parser: parser} do
      assert %{"SOME_KEY" => ""} = parse_map!(parser, ~S(SOME_KEY=""))
    end

    test "octo", %{parser: parser} do
      assert %{"SOME_KEY" => "# not a comment"} =
               parse_map!(parser, ~S(SOME_KEY="# not a comment"))

      assert %{"SOME_KEY" => "not a # comment"} =
               parse_map!(parser, ~S(SOME_KEY="not a # comment"))
    end

    test "simple", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, ~S(SOME_KEY="some value"))
    end

    test "simple with comment", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~S(SOME_KEY="some value"# touching comment))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~S(SOME_KEY="some value" # spaced comment))
    end

    test "simple on its line", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, """
               SOME_KEY="some value"
               """)
    end

    test "escaped \"", %{parser: parser} do
      # quote at the end
      assert %{"K" => "some \"word\""} = parse_map!(parser, ~S(K="some \"word\""))

      # text at the end
      assert %{"K" => "some \"word\" hey"} = parse_map!(parser, ~S(K="some \"word\" hey"))
    end

    test "escaped \r", %{parser: parser} do
      assert(%{"K" => "\r"} = parse_map!(parser, ~S(K="\r")))
    end

    test "escaped \n", %{parser: parser} do
      assert(%{"K" => "\n"} = parse_map!(parser, ~S(K="\n")))
    end

    test "escaped \f", %{parser: parser} do
      assert(%{"K" => "\f"} = parse_map!(parser, ~S(K="\f")))
    end

    test "escaped \t", %{parser: parser} do
      assert(%{"K" => "\t"} = parse_map!(parser, ~S(K="\t")))
    end

    test "escaped \b", %{parser: parser} do
      assert(%{"K" => "\b"} = parse_map!(parser, ~S(K="\b")))
    end

    test "escaped '", %{parser: parser} do
      assert(%{"K" => "'"} = parse_map!(parser, ~S(K="\'")))
    end

    test "not escaped '", %{parser: parser} do
      assert(%{"K" => "'"} = parse_map!(parser, ~S(K="'")))
    end

    test "escaped \\", %{parser: parser} do
      assert(%{"K" => "\\"} = parse_map!(parser, ~S(K="\\")))
    end

    test "unknown escape", %{parser: parser} do
      assert(%{"K" => "a"} = parse_map!(parser, ~S(K="\a")))
    end

    test "multi escapes", %{parser: parser} do
      assert %{
               "SOME_KEY" => "first quoted",
               "SOME_KEY_WITH_ESCAPE" => ~s(say "hello" to the world),
               "SOME_KEY_WITH_ESCAPE_END" => ~s(say "hello"),
               "EMPTY" => ""
             } =
               parse_map!(parser, ~S"""
               SOME_KEY="first quoted"
               SOME_KEY_WITH_ESCAPE="say \"hello\" to the world"
               SOME_KEY_WITH_ESCAPE_END="say \"hello\""
               EMPTY="" # comment with " quote
               """)
    end

    test "unfinished quote", %{parser: parser} do
      assert {:error, _} = parse(parser, ~s(SOME_KEY="hello))
      assert {:error, _} = parse(parser, ~s(SOME_KEY="hello" ""))
    end
  end

  describe "leading whitespace" do
    test "offset on the key", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, "      SOME_KEY=some value")

      assert %{"A" => "1", "B" => "2"} =
               parse_map!(parser, """
                       A=1
               B=2
               """)
    end
  end

  describe "trailing whitespace" do
    test "whitespace before newline is trimmed", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, "SOME_KEY=some value    \n")
    end

    test "whitespace is trimmed if there is a comment", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, "SOME_KEY=some value    # hello \n")
    end

    test "whitespace only", %{parser: parser} do
      assert %{"SOME_KEY" => ""} = parse_map!(parser, "SOME_KEY=    ")
    end

    test "whitespace is not part of the value if there are quotes", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, ~s(SOME_KEY="some value"       ))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~s(SOME_KEY="some value"       \n))

      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, ~s(SOME_KEY='some value'       ))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~s(SOME_KEY='some value'       \n))
    end

    test "multiline whitespace is not trimmed", %{parser: parser} do
      assert %{"SOME_KEY" => "first    \nsecond    \n"} =
               parse_map!(parser, ~s(SOME_KEY="""\nfirst    \nsecond    \n"""))

      assert %{"SOME_KEY" => "first    \nsecond    \n"} =
               parse_map!(parser, ~s(SOME_KEY='''\nfirst    \nsecond    \n'''))
    end
  end

  describe "empty values" do
    test "raw", %{parser: parser} do
      assert(%{"K" => ""} = parse_map!(parser, "K="))
    end

    test "quoted", %{parser: parser} do
      assert(%{"K" => ""} = parse_map!(parser, ~s(K="")))
    end

    test "comment", %{parser: parser} do
      assert(%{"K" => ""} = parse_map!(parser, ~s(K= #)))
    end

    test "comment touching", %{parser: parser} do
      # just like raw values, if the octo touches the equal sign, it's the value
      assert %{"K" => "#"} = parse_map!(parser, ~s(K=#))
      assert %{"K" => "#hello"} = parse_map!(parser, "K=#hello")
    end
  end

  test "'export ' prefix", %{parser: parser} do
    assert %{"A" => "1", "B" => "2", "C" => "3", "D" => "4"} =
             parse_map!(parser, """
             export A=1
                   export B = 2
             C=3
             export    D=4
             """)
  end

  test "export can be a variable", %{parser: parser} do
    assert %{"export" => "true"} =
             parse_map!(parser, """
             export = true
             """)
  end

  test "duplicate value takes the last value", %{parser: parser} do
    # /!\ This test is stupid. The list-to-map conversion is done in the test.
    # The parser returns a list of tuples
    assert %{
             "AA" => "second AA",
             "BB" => "second BB"
           } =
             parse_map!(parser, """
             AA = first AA
             BB = first BB
             BB = second BB
             AA = second AA
             """)

    # The parser will return everything. I guess I wanted to test the fact that
    # Nvir.dotenv!() will use Map.new() too with that. I can't remember.
    assert {:ok,
            [
              {"AA", "first AA"},
              {"BB", "first BB"},
              {"BB", "second BB"},
              {"AA", "second AA"}
            ]} =
             parse(parser, """
             AA = first AA
             BB = first BB
             BB = second BB
             AA = second AA
             """)
  end

  describe "single quoted strings" do
    test "empty", %{parser: parser} do
      assert %{"SOME_KEY" => ""} = parse_map!(parser, ~S(SOME_KEY=''))
    end

    test "octo", %{parser: parser} do
      assert %{"SOME_KEY" => "# not a comment"} =
               parse_map!(parser, ~S(SOME_KEY='# not a comment'))

      assert %{"SOME_KEY" => "not a # comment"} =
               parse_map!(parser, ~S(SOME_KEY='not a # comment'))
    end

    test "simple", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} = parse_map!(parser, ~S(SOME_KEY='some value'))
    end

    test "simple with comment", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~S(SOME_KEY='some value'# touching comment))

      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, ~S(SOME_KEY='some value' # spaced comment))
    end

    test "simple on its line", %{parser: parser} do
      assert %{"SOME_KEY" => "some value"} =
               parse_map!(parser, """
               SOME_KEY='some value'
               """)
    end

    test "escaped '", %{parser: parser} do
      # quote at the end
      assert %{"K" => "some 'word'"} = parse_map!(parser, ~S(K='some \'word\''))

      # text at the end
      assert %{"K" => "some 'word' hey"} = parse_map!(parser, ~S(K='some \'word\' hey'))
    end

    test "not escaped \r", %{parser: parser} do
      assert(%{"K" => "\\r"} = parse_map!(parser, ~S(K='\r')))
    end

    test "not escaped \n", %{parser: parser} do
      assert(%{"K" => "\\n"} = parse_map!(parser, ~S(K='\n')))
    end

    test "not escaped \f", %{parser: parser} do
      assert(%{"K" => "\\f"} = parse_map!(parser, ~S(K='\f')))
    end

    test "not escaped \t", %{parser: parser} do
      assert(%{"K" => "\\t"} = parse_map!(parser, ~S(K='\t')))
    end

    test "not escaped \b", %{parser: parser} do
      assert(%{"K" => "\\b"} = parse_map!(parser, ~S(K='\b')))
    end

    test "not escaped \\", %{parser: parser} do
      assert(%{"K" => "\\ aaa"} = parse_map!(parser, ~S(K='\ aaa')))
    end

    test "unknown escape", %{parser: parser} do
      assert(%{"K" => "\\a"} = parse_map!(parser, ~S(K='\a')))
    end

    test "multi escapes", %{parser: parser} do
      assert %{
               "SOME_KEY" => "first quoted",
               "SOME_KEY_WITH_ESCAPE" => ~s(say "hello" to the world),
               "SOME_KEY_WITH_ESCAPE_END" => ~s(say "hello"),
               "EMPTY" => ""
             } =
               parse_map!(parser, ~S"""
               SOME_KEY='first quoted'
               SOME_KEY_WITH_ESCAPE='say "hello" to the world'
               SOME_KEY_WITH_ESCAPE_END='say "hello"'
               EMPTY='' # comment with ' quote
               """)
    end

    test "unfinished quote", %{parser: parser} do
      assert {:error, _} = parse(parser, ~s(SOME_KEY='hello))
      assert {:error, _} = parse(parser, ~s(SOME_KEY='hello' ''))
    end
  end

  describe ~S(multiline strings with """) do
    test "correct", %{parser: parser} do
      assert %{"MESSAGE" => "Dear World,\nHello!\n"} =
               parse_map!(parser, ~S'''
               MESSAGE="""
               Dear World,
               Hello!
               """
               ''')
    end

    test "multiple", %{parser: parser} do
      assert %{"MESSAGE1" => "Dear World,\nHello!\n", "MESSAGE2" => "\tDear World,\nGoodbye!\n"} =
               parse_map!(parser, ~S'''
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

    test "contains quote", %{parser: parser} do
      assert %{"A" => ~s(on " line\nat end "\n"\ndouble: ""\n)} =
               parse_map!(parser, ~S'''
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
    test "correct", %{parser: parser} do
      assert %{"MESSAGE" => "Dear World,\nHello!\n"} =
               parse_map!(parser, ~S"""
               MESSAGE='''
               Dear World,
               Hello!
               '''
               """)
    end

    test "multiple", %{parser: parser} do
      assert %{"MESSAGE1" => "Dear World,\nHello!\n", "MESSAGE2" => "\\tDear World,\nGoodbye!\n"} =
               parse_map!(parser, ~S"""
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

    test "contains quote", %{parser: parser} do
      assert %{"A" => ~s(on ' line\nat end '\n'\ndouble: ''\n)} =
               parse_map!(parser, ~S"""
               A='''
               on ' line
               at end '
               '
               double: ''
               '''
               """)

      # The \' escape is allowed, though not useful

      assert %{"A" => ~s(on ' line\nat end '\n'\ndouble: ''\n)} =
               parse_map!(parser, ~S"""
               A='''
               on \' line
               at end \'
               \'
               double: \'\'
               '''
               """)
    end
  end

  describe "interpolation parsing" do
    test "no interpolation if alone", %{parser: parser} do
      assert %{
               "WITH_LEADING" => "$",
               "WITH_TRAILING" => "$",
               "WITH_WORD" => "$ aaa"
             } =
               parse_map!(parser, """
               WITH_LEADING= $
               WITH_WORD= $ aaa
               WITH_TRAILING= $  #{"    "}
               """)
    end

    test "in raw value", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed} =
               parse_map!(parser, """
               ENCLOSED=hello ${WHO}

               """)

      assert ["hello ", {:var, "WHO"}] == enclosed

      assert "hello world" = Parser.interpolate_var(enclosed, fn "WHO" -> "world" end)
    end

    test "in raw value, enclosed", %{parser: parser} do
      assert %{"NODELIM" => nodelim} =
               parse_map!(parser, """

               NODELIM=hello $WHO
               """)

      assert ["hello ", {:var, "WHO"}] == nodelim

      assert "hello world" = Parser.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "both types can be mixed", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(parser, """
               ENCLOSED=hello ${WHO}
               NODELIM=hello $WHO
               """)

      assert ["hello ", {:var, "WHO"}] == enclosed
      assert ["hello ", {:var, "WHO"}] == nodelim

      assert "hello world" = Parser.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world" = Parser.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "when resolver returns nil", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(parser, """
               ENCLOSED=hello ${WHO}
               NODELIM=hello $WHO
               """)

      assert ["hello ", {:var, "WHO"}] == enclosed
      assert ["hello ", {:var, "WHO"}] == nodelim

      assert "hello " = Parser.interpolate_var(enclosed, fn "WHO" -> nil end)
      assert "hello " = Parser.interpolate_var(nodelim, fn "WHO" -> nil end)
    end

    test "in double quoted value", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(parser, """
               ENCLOSED="hello ${WHO}"
               NODELIM="hello $WHO"
               """)

      assert ["hello ", {:var, "WHO"}] = enclosed
      assert ["hello ", {:var, "WHO"}] = nodelim

      assert "hello world" = Parser.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world" = Parser.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "in double quoted multiline", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(parser, ~S'''
               ENCLOSED="""
               hello ${WHO}
               """
               NODELIM="""
               hello $WHO
               """
               ''')

      assert ["hello ", {:var, "WHO"}, "\n"] == enclosed
      assert ["hello ", {:var, "WHO"}, "\n"] == nodelim

      assert "hello world\n" = Parser.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "hello world\n" = Parser.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "double quoted multiline whole line", %{parser: parser} do
      assert %{"ENCLOSED" => enclosed, "NODELIM" => nodelim} =
               parse_map!(parser, ~S'''
               ENCLOSED="""
               ${WHO}
               """
               NODELIM="""
               $WHO
               """
               ''')

      assert [{:var, "WHO"}, "\n"] == enclosed
      assert [{:var, "WHO"}, "\n"] == nodelim

      assert "world\n" = Parser.interpolate_var(enclosed, fn "WHO" -> "world" end)
      assert "world\n" = Parser.interpolate_var(nodelim, fn "WHO" -> "world" end)
    end

    test "in single quoted, no interpolation", %{parser: parser} do
      assert %{"ENCLOSED" => "hello ${WHO}", "NODELIM" => "hello $WHO"} =
               parse_map!(parser, """
               ENCLOSED='hello ${WHO}'
               NODELIM='hello $WHO'
               """)
    end

    test "in single quoted multiline, no interpolation", %{parser: parser} do
      assert %{"ENCLOSED" => "hello ${WHO}\n", "NODELIM" => "hello $WHO\n"} =
               parse_map!(parser, """
               ENCLOSED='''
               hello ${WHO}
               '''
               NODELIM='''
               hello $WHO
               '''
               """)
    end

    defp build_sentence(map, vars) do
      Parser.interpolate_var(Map.fetch!(map, "SENTENCE"), fn key -> Map.get(vars, key, "") end)
    end

    test "edge case - vars on both ends", %{parser: parser} do
      assert "hello world" =
               "SENTENCE=$GREETING $WHO"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "hello world" =
               ~s(SENTENCE="$GREETING $WHO")
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "var touching comment, still included in the values just like raw files", %{
      parser: parser
    } do
      assert "world#this is a comment" =
               "SENTENCE=$WHO#this is a comment"
               |> parse_map_with!(parser)
               |> build_sentence(%{"WHO" => "world"})

      # If the comment is spaces, it is not included in the value
      assert "world" =
               "SENTENCE=$WHO #this is a comment"
               |> parse_map_with!(parser)
               |> build_sentence(%{"WHO" => "world"})

      # Quotes protect comments from touching
      assert "world" =
               ~s(SENTENCE="$WHO"#this is a comment)
               |> parse_map_with!(parser)
               |> build_sentence(%{"WHO" => "world"})

      # Enclosing does not
      assert "world#this is a comment" =
               "SENTENCE=${WHO}#this is a comment"
               |> parse_map_with!(parser)
               |> build_sentence(%{"WHO" => "world"})
    end

    test "edge case - vars touching", %{parser: parser} do
      assert "helloworld" =
               "SENTENCE=$GREETING$WHO"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "helloworld" =
               ~s(SENTENCE="$GREETING$WHO")
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "edge case - enclosed vars touching", %{parser: parser} do
      assert "helloworld" =
               "SENTENCE=${GREETING}${WHO}"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})

      assert "helloworld" =
               ~s(SENTENCE="${GREETING}${WHO}")
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "edge case - vars and dollar", %{parser: parser} do
      assert "$hello" =
               "SENTENCE=$$GREETING"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello"})

      assert "$hello" =
               ~s(SENTENCE="$$GREETING")
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello"})
    end

    test "edge case - empty enclosure", %{parser: parser} do
      assert "no---space" =
               "SENTENCE=no${}space"
               |> parse_map_with!(parser)
               |> build_sentence(%{"" => "---"})

      assert "no---space" =
               ~s(SENTENCE="no${}space")
               |> parse_map_with!(parser)
               |> build_sentence(%{"" => "---"})
    end

    test "numeric variable name", %{parser: parser} do
      assert "hello $123" =
               "SENTENCE=$GREETING $123"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello"})
    end

    test "other char variable name", %{parser: parser} do
      assert "hello $@test" =
               "SENTENCE=$GREETING $@test"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello"})
    end

    test "double dollar", %{parser: parser} do
      assert "hello $world" =
               "SENTENCE=$GREETING $$WHO"
               |> parse_map_with!(parser)
               |> build_sentence(%{"GREETING" => "hello", "WHO" => "world"})
    end

    test "lowercase is supported", %{parser: parser} do
      assert "hello world" =
               "SENTENCE=$greeting $who"
               |> parse_map_with!(parser)
               |> build_sentence(%{"greeting" => "hello", "who" => "world"})
    end
  end

  describe "parsing error tests" do
    defp valid_parse_error!(e) do
      msg = Exception.message(e)

      refute msg =~ "retrieving Exception.message/1"

      # IO.puts("--------------- ERROR ---------------")
      # IO.puts(msg)
      # IO.puts("-------------------------------------")
      msg
    end

    test "unexpected EOF in triple double quotes", %{parser: parser} do
      env = ~S(KEY=""")

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof after multiline string start"
      assert %ParseError{line: 1, col: 8} = e
    end

    test "unexpected character in triple double quotes", %{parser: parser} do
      env = ~S'''
      KEY=""".invalid
      '''

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected character after multiline string start"
      assert %ParseError{line: 1, col: 8} = e
    end

    test "unexpected EOF in triple single quotes", %{parser: parser} do
      env = """
      KEY='''
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof in multiline single quoted string"
      assert %ParseError{line: 2, col: 1} = e
    end

    test "unexpected character in triple single quotes", %{parser: parser} do
      env = """
      KEY='''.invalid
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected character after multiline string start"
      assert %ParseError{line: 1, col: 8} = e
    end

    test "forbidden newline in double quoted string", %{parser: parser} do
      env = """
      KEY="value
      with newline"
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected newline"
      assert %ParseError{line: 1, col: 11} = e
    end

    test "unfinished double quoted string", %{parser: parser} do
      env = ~S(KEY="unclosed string)

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof"
      assert %ParseError{line: 1, col: 21} = e
    end

    test "forbidden newline in single quoted string", %{parser: parser} do
      env = """
      KEY='value
      with newline'
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected newline"
      assert %ParseError{line: 1, col: 11} = e
    end

    test "unfinished single quoted string", %{parser: parser} do
      env = """
      KEY='unclosed string
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected newline in single quoted string"
      assert %ParseError{line: 1, col: 21} = e
    end

    test "unfinished multi-line double quoted string", %{parser: parser} do
      env = """
      KEY=\"\"\"
      unclosed multiline
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof in multiline double quoted string"
      assert %ParseError{line: 3, col: 1} = e
    end

    test "unfinished multi-line single quoted string", %{parser: parser} do
      env = """








      KEY='''
      unclosed multiline
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof in multiline single quoted string"
      assert %ParseError{line: 11, col: 1} = e
    end

    test "forbidden newline in enclosed variable", %{parser: parser} do
      env = """
      KEY=${
      var}
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected newline in variable braces"
      assert %ParseError{line: 1, col: 7} = e
    end

    test "unclosed variable curly brace", %{parser: parser} do
      env = """
      KEY=${unclosed
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected newline in variable braces"
      assert %ParseError{line: 1, col: 15} = e
    end

    test "left padded braces", %{parser: parser} do
      env = """
      KEY=${ UNSUPPORTED}
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected whitespace in variable braces"
      assert %ParseError{line: 1, col: 7} = e
    end

    test "right padded braces", %{parser: parser} do
      env = """
      KEY=${UNSUPPORTED }
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected whitespace in variable braces"
      assert %ParseError{line: 1, col: 18} = e
    end

    test "unclosed variable curly brace (EOF)", %{parser: parser} do
      env = "KEY=${unclosed"

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected eof in variable braces"
      assert %ParseError{line: 1, col: 15} = e
    end

    test "invalid char", %{parser: parser} do
      env = "KEY=${foo@bar}"

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "invalid variable name"
      assert %ParseError{line: 1, col: 10} = e
    end

    test "catchall clause in value parsing", %{parser: parser} do
      env = """
      KEY="hello" "world"
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected token"
      assert %ParseError{line: 1, col: 13} = e
    end

    test "token after value", %{parser: parser} do
      env = """
      KEY=hello "world"
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected token"
      assert %ParseError{line: 1, col: 11} = e
    end

    test "unexpected line", %{parser: parser} do
      env = """
      FOO=foo
      BAR=bar
      @some_paste hello
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected token"
      assert %ParseError{line: 3, col: 1} = e
    end

    test "unexpected command", %{parser: parser} do
      env = """
      FOO=foo
      BAR=bar
      echo "$PRIVATE_KEY" | openssl pkey -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64
      """

      assert {:error, e} = parse(parser, env)
      msg = valid_parse_error!(e)
      assert msg =~ "unexpected token"
      assert %ParseError{line: 3, col: 6} = e
    end
  end

  describe "malformed input safety" do
    # The parser contract is to always return {:error, %ParseError{}} on bad
    # input. Also, dotenv files typically contain secrets and error messages
    # end up in logs, so the error message must never embed values from the
    # file. Debug output including file contents is a separate, explicit
    # opt-in (:unsafe_display_file_contents_in_errors).

    test "key without assignment", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, "FOO\n")
      valid_parse_error!(e)
      assert %ParseError{line: 1} = e
    end

    test "line starting with a dollar sign", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, "$SECRET_TOKEN=hunter2-value\n")
      valid_parse_error!(e)
      refute e.errmsg =~ "hunter2-value"
    end

    test "line starting with the assign operator", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, "=some-value\n")
      valid_parse_error!(e)
      refute e.errmsg =~ "some-value"
    end

    test "invalid UTF-8 in a raw value", %{parser: parser} do
      # 0xE9 is "é" in latin-1, and an invalid byte sequence in UTF-8
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=", 0xE9, "\n">>)
      valid_parse_error!(e)
    end

    test "invalid UTF-8 in a double quoted value", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=\"", 0xE9, "\"\n">>)
      valid_parse_error!(e)
    end

    test "NUL byte in a value", %{parser: parser} do
      # Environment variable values cannot contain NUL bytes,
      # System.put_env/2 rejects them with a bare ArgumentError. The parser
      # should report those bytes with line/col information instead.
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=a", 0, "b\n">>)
      valid_parse_error!(e)
    end

    test "error messages do not contain values from the file", %{parser: parser} do
      # A missing "=" makes the value appear at an unexpected position, so an
      # easy typo would leak the value into the error message.
      assert {:error, %ParseError{} = e} = parse(parser, "FOO 'my-secret-value'\n")
      e = %{e | debug_content: nil}
      valid_parse_error!(e)
      refute e.errmsg =~ "my-secret-value"

      assert {:error, %ParseError{} = e} = parse(parser, ~s("quoted-secret"=x\n))
      e = %{e | debug_content: nil}
      valid_parse_error!(e)
      refute e.errmsg =~ "quoted-secret"
    end

    test "dollar variable between key and assign operator", %{parser: parser} do
      # The :dollar token has no content element, so it needs a dedicated
      # match where a content-bearing token is expected.
      assert {:error, %ParseError{} = e} = parse(parser, "FOO $X=1\n")
      valid_parse_error!(e)
    end

    test "invalid UTF-8 in a single quoted value", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY='", 0xE9, "'\n">>)
      valid_parse_error!(e)
    end

    test "invalid UTF-8 in a multiline single quoted value", %{parser: parser} do
      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY='''\n", 0xE9, "\n'''\n">>)

      valid_parse_error!(e)
      assert %ParseError{line: 2} = e
    end

    test "invalid UTF-8 in a multiline double quoted value", %{parser: parser} do
      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY=\"\"\"\n", 0xE9, "\n\"\"\"\n">>)

      valid_parse_error!(e)
      assert %ParseError{line: 2} = e
    end

    test "invalid UTF-8 in a comment", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, <<"# hello ", 0xE9, "\n">>)
      valid_parse_error!(e)
    end

    test "invalid UTF-8 in variable braces", %{parser: parser} do
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=${F", 0xE9, "}\n">>)
      valid_parse_error!(e)
    end

    test "NUL byte in quoted values", %{parser: parser} do
      # NUL is a valid UTF-8 codepoint so the quoted-string clauses accept
      # it, but System.put_env/2 rejects values containing NUL bytes.
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=\"a", 0, "b\"\n">>)
      valid_parse_error!(e)

      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY='a", 0, "b'\n">>)
      valid_parse_error!(e)

      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY=\"\"\"\na", 0, "b\n\"\"\"\n">>)

      valid_parse_error!(e)

      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY='''\na", 0, "b\n'''\n">>)

      valid_parse_error!(e)
    end

    test "NUL byte escaped in a double quoted value", %{parser: parser} do
      # The escape clause consumes the byte after the backslash before the
      # generic character clauses can look at it.
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=\"a\\", 0, "b\"\n">>)
      valid_parse_error!(e)
    end

    test "NUL byte escaped in multiline values", %{parser: parser} do
      # The escape clauses of the multiline string functions also consume the
      # byte after the backslash before the generic character clauses.
      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY=\"\"\"\na\\", 0, "b\n\"\"\"\n">>)

      valid_parse_error!(e)

      assert {:error, %ParseError{} = e} =
               parse(parser, <<"SOME_KEY='''\na\\", 0, "b\n'''\n">>)

      valid_parse_error!(e)
    end

    test "NUL byte in a comment glued to a value", %{parser: parser} do
      # A "#" without whitespace before it is part of the value, so the
      # comment content ends up in the variable value.
      assert {:error, %ParseError{} = e} = parse(parser, <<"SOME_KEY=x#a", 0, "b\n">>)
      valid_parse_error!(e)
    end
  end
end
