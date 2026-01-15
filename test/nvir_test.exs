defmodule NvirTest do
  alias Nvir.Cast
  alias Nvir.Test.PseudoSecretManager
  use ExUnit.Case, async: false

  doctest Nvir

  setup do
    before_keys = Enum.sort(Map.keys(System.get_env()))

    on_exit(fn ->
      after_keys = Enum.sort(Map.keys(System.get_env()))

      if before_keys != after_keys do
        added = after_keys -- before_keys
        deleted = before_keys -- after_keys

        flunk("""
        Environment was tampered during test.

        ADDED
        #{inspect(added)}

        DELETED
        #{inspect(deleted)}

        """)
      end
    end)
  end

  defp match_env(env) when is_atom(env) do
    Nvir.dotenv_enable_sources(Nvir.dotenv_new(), env, true)
  end

  defp match_env(envs) when is_list(envs) do
    conf = Map.new(envs, fn env when is_atom(env) -> {env, true} end)
    Nvir.dotenv_enable_sources(Nvir.dotenv_new(), conf)
  end

  describe "dotenv loaders" do
    test "empty loader" do
      assert %Nvir{enabled_sources: %{}} == Nvir.dotenv_new()
    end

    test "default loader should have test environment enabled" do
      # Because we are in a test here
      assert %{test: true} = Nvir.dotenv_loader().enabled_sources
    end

    test "default loader should not have any before_env_set transformer" do
      assert nil == Nvir.dotenv_loader().before_env_set
    end

    test "the configuration is validated" do
      # Not a boolean value
      assert_raise ArgumentError, fn ->
        Nvir.dotenv_configure(Nvir.dotenv_loader(),
          enabled_sources: %{docs: :not_a_boolean}
        )
      end

      # Not an atom key
      assert_raise ArgumentError, fn ->
        Nvir.dotenv_configure(Nvir.dotenv_loader(),
          enabled_sources: %{"docs" => true}
        )
      end
    end

    test "cannot change the :overwrite tag" do
      assert_raise ArgumentError, fn ->
        Nvir.dotenv_enable_sources(Nvir.dotenv_loader(), :overwrite, true)
      end

      assert_raise ArgumentError, fn ->
        Nvir.dotenv_enable_sources(Nvir.dotenv_loader(), :overwrite, false)
      end
    end
  end

  describe "collection of sources" do
    test "empty sources" do
      assert {[], []} = Nvir.collect_sources(match_env(:abc), [])
    end

    test "file source" do
      assert {["some.env"], []} = Nvir.collect_sources(match_env(:abc), "some.env")
    end

    test "file list source" do
      assert {["1.env", "2.env"], []} = Nvir.collect_sources(match_env(:abc), ["1.env", "2.env"])
    end

    test "collect from env only" do
      assert {["1", "2", "3", "4"], []} =
               Nvir.collect_sources(match_env(:abc),
                 abc: ["1"],
                 abc: "2",
                 other: ["0", "0", "0"],
                 abc: ["3", abc: "4", other: "0"],
                 other: [abc: "0"]
               )
    end

    test "collect basic overwrites" do
      assert {[], ["101"]} = Nvir.collect_sources(match_env(:abc), overwrite: "101")
      assert {[], ["101"]} = Nvir.collect_sources(match_env(:abc), overwrite: ["101"])

      assert {[], ["101", "102"]} =
               Nvir.collect_sources(match_env(:abc), overwrite: ["101", "102"])

      assert {[], ["101", "102"]} =
               Nvir.collect_sources(match_env(:abc),
                 overwrite: [overwrite: [[overwrite: [["101", overwrite: "102"]]]]]
               )
    end

    test "overwrites and normal" do
      assert {["1"], ["101"]} =
               Nvir.collect_sources(match_env(:abc), overwrite: ["101"], abc: "1")

      assert {["1"], ["101", "102"]} =
               Nvir.collect_sources(match_env(:abc),
                 overwrite: ["101"],
                 abc: "1",
                 overwrite: "102"
               )
    end

    test "overwrites with env" do
      # We enable the :overwrite tag. This is invalid, but we must ensure that
      # the overwrite are removed from the regular sources even if the tag can be
      # matched.

      assert {["1", "2"], ["1001", "1002", "1003", "1004", "1005"]} =
               Nvir.collect_sources(
                 %Nvir{enabled_sources: %{overwrite: true, abc: true, xyz: true}},
                 [
                   "1",
                   overwrite: ["1001", abc: ["1002"]],
                   abc: ["2", overwrite: ["1003", other: "-1"]],
                   other: [overwrite: "-2", abc: "-3"],
                   abc: [overwrite: [abc: "1004", other: "-4"]],
                   xyz: [overwrite: [abc: "1005", other: "-5"]]
                 ]
               )
    end

    test "odd cases" do
      # nested tuples
      assert {["1"], _} = Nvir.collect_sources(match_env(:abc), {:abc, {:abc, {:abc, "1"}}})

      # lists without tags
      assert {["1", "2"], _} = Nvir.collect_sources(match_env(:abc), [[[[["1"]]]], [[[[["2"]]]]]])
    end
  end

  # Ensures that the key is not defined in the environment, and schedules it's
  # cleanup after the test
  defp delete_key(key) do
    clear_key(key)
    on_exit(fn -> clear_key(key) end)
    key
  end

  # Creates the key, ensures that it is deleted at the end of the test
  #
  # Returns the key
  defp put_key(key, value) do
    System.put_env(key, value)
    assert {:ok, ^value} = System.fetch_env(key)
    on_exit(fn -> clear_key(key) end)
    key
  end

  defp clear_key(key) do
    :ok = System.delete_env(key)
    assert :error = System.fetch_env(key)
  end

  defp create_file(contents) do
    # use a different directory for all files to better test relative/absolute
    # paths.
    dir = Briefly.create!(type: :directory)
    filename = "nvir-test.env"
    path = Path.join(dir, filename)
    File.write!(path, contents)
    path
  end

  describe "calling dotenv" do
    test "creates the env vars if they do not exist" do
      _ = delete_key("SOME_VAR1")
      _ = delete_key("SOME_VAR2")
      put_key("EXISTING", "yes!")

      # Some keys are not defined
      assert :error = System.fetch_env("SOME_VAR1")
      assert :error = System.fetch_env("SOME_VAR2")
      assert {:ok, "yes!"} = System.fetch_env("EXISTING")

      file =
        create_file("""
        SOME_VAR1="some val 1"
        SOME_VAR2="some val 2"
        EXISTING="nooope!"
        """)

      # Call doteNvir. It returns the vars that were added only.
      assert %{"SOME_VAR1" => _, "SOME_VAR2" => _} = Nvir.dotenv!(file)

      # ...they are now defined
      assert "some val 1" = System.fetch_env!("SOME_VAR1")
      assert "some val 2" = System.fetch_env!("SOME_VAR2")
      assert "yes!" = System.fetch_env!("EXISTING")
    end

    test "creates the env vars for the given env" do
      # Some keys are not defined
      delete_key("SOME_VAR1")
      delete_key("SOME_VAR2")
      put_key("EXISTING", "yes!")

      dev_file =
        create_file("""
        SOME_VAR1="var1 in dev"
        SOME_VAR2="var2 in dev"
        EXISTING="nope in dev"
        """)

      test_file =
        create_file("""
        SOME_VAR1="var1 in test"
        SOME_VAR2="var2 in test"
        EXISTING="nope in test"
        """)

      # Call doteNvir. It returns the vars that were added only.
      assert %{"SOME_VAR1" => "var1 in test", "SOME_VAR2" => "var2 in test"} =
               Nvir.dotenv!(dev: dev_file, test: test_file)

      # ...they are now defined
      assert "var1 in test" = System.fetch_env!("SOME_VAR1")
      assert "var2 in test" = System.fetch_env!("SOME_VAR2")

      # No overwrite though
      assert "yes!" = System.fetch_env!("EXISTING")
    end

    test "the files overwrite themselves" do
      # One key will not exist
      _ = delete_key("REDEFINED")
      _ = delete_key("ONLY_1")
      _ = delete_key("ONLY_2")

      # One key will exist
      put_key("EXISTING", "already set")

      file1 =
        create_file("""
        REDEFINED="in file 1"
        ONLY_1=in file 1
        EXISTING=not used
        """)

      file2 =
        create_file("""
        REDEFINED="in file 2"
        ONLY_2=in file 2
        EXISTING=not used
        """)

      # Call doteNvir. It returns the vars that were added only.
      assert %{"REDEFINED" => "in file 2", "ONLY_1" => "in file 1", "ONLY_2" => "in file 2"} =
               Nvir.dotenv!([file1, file2])

      assert "in file 2" = System.fetch_env!("REDEFINED")
      assert "in file 1" = System.fetch_env!("ONLY_1")
      assert "in file 2" = System.fetch_env!("ONLY_2")
      assert "already set" = System.fetch_env!("EXISTING")
    end

    test "it is possible to overwrite system env" do
      # One key will not exist
      _ = delete_key("REDEFINED")
      _ = delete_key("ONLY_1")
      _ = delete_key("ONLY_2")

      # Existing keys
      put_key("EXISTING", "already set")
      put_key("OVERRIDABLE", "already set")
      put_key("OVERRIDABLE_REDEF", "already set")
      put_key("OVERRIDABLE_ONLY_1", "already set")
      put_key("OVERRIDABLE_ONLY_2", "already set")

      dev_file_1 =
        create_file("""
        REDEFINED=in dev file 1
        ONLY_1=in dev file 1
        EXISTING=in dev file 1
        OVERRIDABLE=in dev file 1
        OVERRIDABLE_REDEF=in dev file 1
        OVERRIDABLE_ONLY_1=in dev file 1
        ONLY_DEV=should not be seen
        """)

      dev_file_2 =
        create_file("""
        REDEFINED=in dev file 2
        ONLY_2=in dev file 2
        EXISTING=in dev file 2
        OVERRIDABLE=in dev file 2
        OVERRIDABLE_REDEF=in dev file 2
        OVERRIDABLE_ONLY_2=in dev file 2
        ONLY_DEV=should not be seen
        """)

      test_file_1 =
        create_file("""
        REDEFINED=in test file 1
        ONLY_1=in test file 1
        EXISTING=in test file 1
        OVERRIDABLE=in test file 1
        OVERRIDABLE_REDEF=in test file 1
        OVERRIDABLE_ONLY_1=in test file 1
        """)

      test_file_2 =
        create_file("""
        REDEFINED=in test file 2
        ONLY_2=in test file 2
        EXISTING=in test file 2
        OVERRIDABLE=in test file 2
        OVERRIDABLE_REDEF=in test file 2
        OVERRIDABLE_ONLY_2=in test file 2
        """)

      dev_ovr_1 =
        create_file("""
        OVERRIDABLE=in dev file 1
        OVERRIDABLE_REDEF=in dev file 1
        OVERRIDABLE_ONLY_1=in dev file 1
        ONLY_DEV=should not be seen
        """)

      dev_ovr_2 =
        create_file("""
        OVERRIDABLE=in dev file 2
        OVERRIDABLE_REDEF=in dev file 2
        OVERRIDABLE_ONLY_2=in dev file 2
        ONLY_DEV=should not be seen
        """)

      test_ovr_1 =
        create_file("""
        OVERRIDABLE=in test file 1
        OVERRIDABLE_REDEF=in test file 1
        OVERRIDABLE_ONLY_1=in test file 1
        """)

      test_ovr_2 =
        create_file("""
        # not redefining this one:
        # OVERRIDABLE=in test file 2

        OVERRIDABLE_REDEF=in test file 2
        OVERRIDABLE_ONLY_2=in test file 2
        """)

      changes =
        Nvir.dotenv!(
          dev: [dev_file_1, dev_file_2],
          test: [test_file_1, test_file_2],
          overwrite: [test: [test_ovr_1, test_ovr_2], dev: [dev_ovr_1, dev_ovr_2]]
        )

      assert "in test file 2" = System.fetch_env!("REDEFINED")
      assert "in test file 1" = System.fetch_env!("ONLY_1")
      assert "in test file 2" = System.fetch_env!("ONLY_2")
      assert "already set" = System.fetch_env!("EXISTING")
      assert "in test file 1" = System.fetch_env!("OVERRIDABLE")
      assert "in test file 2" = System.fetch_env!("OVERRIDABLE_REDEF")
      assert "in test file 1" = System.fetch_env!("OVERRIDABLE_ONLY_1")
      assert "in test file 2" = System.fetch_env!("OVERRIDABLE_ONLY_2")
      assert :error = System.fetch_env("ONLY_DEV")

      assert %{
               "ONLY_1" => "in test file 1",
               "ONLY_2" => "in test file 2",
               "OVERRIDABLE" => "in test file 1",
               "OVERRIDABLE_ONLY_1" => "in test file 1",
               "OVERRIDABLE_ONLY_2" => "in test file 2",
               "OVERRIDABLE_REDEF" => "in test file 2",
               "REDEFINED" => "in test file 2"
             } == changes
    end

    test "non existing files" do
      delete_key("ADDED")

      real_file =
        create_file("""
        ADDED=in real file
        """)

      assert %{"ADDED" => _} =
               Nvir.dotenv!(["f1", test: "f2", test: ["f3"]] ++ [[overwrite: "f4"], real_file])

      assert "in real file" = System.fetch_env!("ADDED")
    end

    test "parse error" do
      file =
        create_file(~S'''
        A="""
        ''')

      assert_raise Nvir.LoadError, fn -> Nvir.dotenv!(file) end
    end
  end

  describe "before_env_set hook" do
    test "variables should be transformed before being set" do
      delete_key("CHANGED_KEY")
      delete_key("COMMON_SWAPPED")
      delete_key("COMMON")
      delete_key("HOOKED")
      delete_key("NOT_HOOKED")
      delete_key("OVERWRITE_HOOKED")
      delete_key("OVERWRITE_NOT_HOOKED")
      delete_key("SWAPPED_KEY")

      regular_file =
        create_file("""
        HOOKED=hello world
        NOT_HOOKED=hello moon
        COMMON=in regular
        """)

      overwrite_file =
        create_file("""
        OVERWRITE_HOOKED=hello mars
        OVERWRITE_NOT_HOOKED=hello saturn
        COMMON=in overwrite
        """)

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set: fn
            {"HOOKED" = k, v} ->
              {k, String.upcase(v)}

            {"OVERWRITE_HOOKED", v} ->
              {"SWAPPED_KEY", v}

            {"COMMON", "in regular"} ->
              {"COMMON", "no-interpol-$COMMON"}

            {"COMMON", "in overwrite"} ->
              {"COMMON_SWAPPED", "nasty"}

            pair ->
              pair
          end
        )
        |> Nvir.dotenv!([regular_file, overwrite: overwrite_file])

      assert "HELLO WORLD" = System.fetch_env!("HOOKED")
      assert "hello moon" = System.fetch_env!("NOT_HOOKED")
      assert "hello mars" = System.fetch_env!("SWAPPED_KEY")
      assert "hello saturn" = System.fetch_env!("OVERWRITE_NOT_HOOKED")
      assert "no-interpol-$COMMON" = System.fetch_env!("COMMON")
      assert "nasty" = System.fetch_env!("COMMON_SWAPPED")
      assert :error = System.fetch_env("OVERWRITE_HOOKED")

      assert %{
               "SWAPPED_KEY" => "hello mars",
               "COMMON_SWAPPED" => "nasty",
               "COMMON" => "no-interpol-$COMMON",
               "HOOKED" => "HELLO WORLD",
               "NOT_HOOKED" => "hello moon",
               "OVERWRITE_NOT_HOOKED" => "hello saturn"
             } == changes
    end

    def before_env_set_hook({k, v}, :arg2, :arg3) do
      {k, String.upcase(v)}
    end

    test "variables transformer supports MFA" do
      delete_key("MFA_REGULAR")
      delete_key("MFA_OVERWRITE")

      regular_file =
        create_file("""
        MFA_REGULAR=hello world
        """)

      overwrite_file =
        create_file("""
        MFA_OVERWRITE=hello mars
        """)

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set: {__MODULE__, :before_env_set_hook, [:arg2, :arg3]}
        )
        |> Nvir.dotenv!([regular_file, overwrite: overwrite_file])

      # The hook function just calls String.upcase
      assert "HELLO WORLD" = System.fetch_env!("MFA_REGULAR")
      assert "HELLO MARS" = System.fetch_env!("MFA_OVERWRITE")

      assert %{
               "MFA_REGULAR" => "HELLO WORLD",
               "MFA_OVERWRITE" => "HELLO MARS"
             } == changes
    end

    test "the hook can return values that implement the String.Chars protocol" do
      delete_key("MEDIAN_VALUE")
      delete_key("some_atom_key")
      delete_key("USER_HOMEPAGE")

      test_file =
        create_file("""
        STRINGKEY=stringval
        MEDIAN_VALUE=will be a number
        USERNAME=alice
        """)

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set: fn
            {"STRINGKEY", _} ->
              {:some_atom_key, [~c"hello", ?=, ~c"world"]}

            {"MEDIAN_VALUE" = k, _} ->
              {k, 45.67}

            {"USERNAME", v} ->
              {"USER_HOMEPAGE", %{URI.parse("http://homepage.com/") | path: "/#{v}"}}
          end
        )
        |> Nvir.dotenv!(test_file)

      assert "hello=world" = System.fetch_env!("some_atom_key")
      assert "45.67" = System.fetch_env!("MEDIAN_VALUE")
      assert "http://homepage.com/alice" = System.fetch_env!("USER_HOMEPAGE")

      assert %{
               "MEDIAN_VALUE" => "45.67",
               "some_atom_key" => "hello=world",
               "USER_HOMEPAGE" => "http://homepage.com/alice"
             } == changes
    end
  end

  describe "before_env_set_all hook" do
    def before_env_set_all_hook(vars, :arg2, :arg3) do
      Map.new(vars, fn {k, v} -> {k, String.upcase(v)} end)
    end

    test "variables should be transformed before being set (using before_env_set_all)" do
      delete_key("HOOKED")
      delete_key("NOT_HOOKED")
      delete_key("COMMON")
      delete_key("COMMON_SWAPPED")
      delete_key("SWAPPED_KEY")
      delete_key("OVERWRITE_HOOKED")
      delete_key("OVERWRITE_NOT_HOOKED")
      delete_key("STRINGKEY")
      delete_key("MEDIAN_VALUE")
      delete_key("USERNAME")
      delete_key("USER_HOMEPAGE")
      delete_key("WILL_BE_SKIPPED")
      delete_key("some_atom_key")

      regular_file =
        create_file("""
        HOOKED=hello world
        NOT_HOOKED=hello moon
        COMMON=in regular
        STRINGKEY=stringval
        MEDIAN_VALUE=will be a number
        USERNAME=alice
        WILL_BE_SKIPPED=hello
        """)

      overwrite_file =
        create_file("""
        OVERWRITE_HOOKED=hello mars
        OVERWRITE_NOT_HOOKED=hello saturn
        COMMON=in overwrite
        """)

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set_all: fn vars ->
            # vars is a map of all variables that are about to be set.
            # "COMMON" is "in overwrite" because it's the last one processed.
            vars
            |> Map.new(fn
              {"HOOKED", v} ->
                {"HOOKED", String.upcase(v)}

              {"OVERWRITE_HOOKED", v} ->
                {"SWAPPED_KEY", v}

              {"COMMON", "in overwrite"} ->
                {"COMMON_SWAPPED", "nasty"}

              {"STRINGKEY", _} ->
                {:some_atom_key, [~c"hello", ?=, ~c"world"]}

              {"MEDIAN_VALUE", _} ->
                {"MEDIAN_VALUE", 45.67}

              {"USERNAME", v} ->
                {"USER_HOMEPAGE", %{URI.parse("http://homepage.com/") | path: "/#{v}"}}

              {k, v} ->
                {k, v}
            end)
            |> Map.delete("WILL_BE_SKIPPED")
          end
        )
        |> Nvir.dotenv!([regular_file, overwrite: overwrite_file])

      assert "HELLO WORLD" = System.fetch_env!("HOOKED")
      assert "hello moon" = System.fetch_env!("NOT_HOOKED")
      assert "hello mars" = System.fetch_env!("SWAPPED_KEY")
      assert "hello saturn" = System.fetch_env!("OVERWRITE_NOT_HOOKED")
      assert "nasty" = System.fetch_env!("COMMON_SWAPPED")
      assert :error = System.fetch_env("COMMON")
      assert :error = System.fetch_env("OVERWRITE_HOOKED")

      assert "hello=world" = System.fetch_env!("some_atom_key")
      assert "45.67" = System.fetch_env!("MEDIAN_VALUE")
      assert "http://homepage.com/alice" = System.fetch_env!("USER_HOMEPAGE")

      assert %{
               "SWAPPED_KEY" => "hello mars",
               "COMMON_SWAPPED" => "nasty",
               "HOOKED" => "HELLO WORLD",
               "NOT_HOOKED" => "hello moon",
               "OVERWRITE_NOT_HOOKED" => "hello saturn",
               "MEDIAN_VALUE" => "45.67",
               "some_atom_key" => "hello=world",
               "USER_HOMEPAGE" => "http://homepage.com/alice"
             } == changes
    end

    test "before_env_set_all hook can return a stream" do
      delete_key("REGULAR")
      delete_key("OVERWRITE")

      regular_file = create_file("REGULAR=val1")
      overwrite_file = create_file("OVERWRITE=val2")

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set_all: fn vars ->
            Stream.map(vars, fn {k, v} -> {String.to_atom(k), String.upcase(v)} end)
          end
        )
        |> Nvir.dotenv!([regular_file, overwrite: [overwrite: overwrite_file]])

      assert "VAL1" = System.fetch_env!("REGULAR")
      assert "VAL2" = System.fetch_env!("OVERWRITE")
      assert %{"REGULAR" => "VAL1", "OVERWRITE" => "VAL2"} == changes
    end

    test "before_env_set_all hook supports MFA" do
      delete_key("MFA_REGULAR")
      delete_key("MFA_OVERWRITE")

      regular_file = create_file("MFA_REGULAR=hello world")
      overwrite_file = create_file("MFA_OVERWRITE=hello mars")

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set_all: {__MODULE__, :before_env_set_all_hook, [:arg2, :arg3]}
        )
        |> Nvir.dotenv!([regular_file, overwrite: overwrite_file])

      assert "HELLO WORLD" = System.fetch_env!("MFA_REGULAR")
      assert "HELLO MARS" = System.fetch_env!("MFA_OVERWRITE")

      assert %{
               "MFA_REGULAR" => "HELLO WORLD",
               "MFA_OVERWRITE" => "HELLO MARS"
             } == changes
    end

    test "before_env_set_all hook must return enumerable" do
      delete_key("REGULAR")
      delete_key("OVERWRITE")

      regular_file = create_file("REGULAR=val1")
      overwrite_file = create_file("OVERWRITE=val2")

      assert_raise RuntimeError,
                   "invalid :before_env_set_all hook return value (not an enumerable): :some_atom",
                   fn ->
                     Nvir.dotenv_loader()
                     |> Nvir.dotenv_configure(before_env_set_all: fn _ -> :some_atom end)
                     |> Nvir.dotenv!([regular_file, overwrite: [overwrite: overwrite_file]])
                   end
    end

    test "before_env_set_all hook must return pairs in enumerable" do
      delete_key("REGULAR")
      delete_key("OVERWRITE")

      regular_file = create_file("REGULAR=val1")
      overwrite_file = create_file("OVERWRITE=val2")

      assert_raise RuntimeError,
                   "invalid pair in :before_env_set_all hook return value: :hello",
                   fn ->
                     Nvir.dotenv_loader()
                     |> Nvir.dotenv_configure(before_env_set_all: fn _ -> [:hello] end)
                     |> Nvir.dotenv!([regular_file, overwrite: [overwrite: overwrite_file]])
                   end
    end

    test "before_env_set_all hook must return stringable pairs" do
      delete_key("REGULAR")
      delete_key("OVERWRITE")

      regular_file = create_file("REGULAR=val1")
      overwrite_file = create_file("OVERWRITE=val2")

      assert_raise RuntimeError,
                   "invalid :before_env_set_all hook return value (could not convert to string): {:a, :tuple}",
                   fn ->
                     Nvir.dotenv_loader()
                     |> Nvir.dotenv_configure(
                       before_env_set_all: fn _ -> [{"someval", {:a, :tuple}}] end
                     )
                     |> Nvir.dotenv!([regular_file, overwrite: [overwrite: overwrite_file]])
                   end
    end

    test "resolves secret:// URIs with JSON fragment syntax" do
      delete_key("DATABASE_URL")
      delete_key("DATABASE_USER")
      delete_key("DATABASE_PASS")
      delete_key("API_KEY")
      delete_key("PLAIN_VALUE")

      file =
        create_file("""
        DATABASE_URL=secret:///db/prod/credentials#url
        DATABASE_USER=secret:///db/prod/credentials#username
        DATABASE_PASS=secret:///db/prod/credentials#password
        API_KEY=secret:///api/keys#prod
        PLAIN_VALUE=just_a_string
        """)

      PseudoSecretManager.mock(%{
        "/db/prod/credentials" => %{
          "url" => "postgres://prod.example.com:5432/mydb",
          "username" => "prod_user",
          "password" => "super_secret_pass"
        },
        "/api/keys" => %{
          "prod" => "pk_live_abc123",
          "debug" => "pk_test_xyz789"
        }
      })

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(before_env_set_all: {PseudoSecretManager, :resolve_all, []})
        |> Nvir.dotenv!(file)

      assert "postgres://prod.example.com:5432/mydb" = System.fetch_env!("DATABASE_URL")
      assert "prod_user" = System.fetch_env!("DATABASE_USER")
      assert "super_secret_pass" = System.fetch_env!("DATABASE_PASS")
      assert "pk_live_abc123" = System.fetch_env!("API_KEY")
      assert "just_a_string" = System.fetch_env!("PLAIN_VALUE")

      assert %{
               "DATABASE_URL" => "postgres://prod.example.com:5432/mydb",
               "DATABASE_USER" => "prod_user",
               "DATABASE_PASS" => "super_secret_pass",
               "API_KEY" => "pk_live_abc123",
               "PLAIN_VALUE" => "just_a_string"
             } == changes
    end

    test "caches decoded JSON blobs efficiently" do
      delete_key("DATABASE_URL")
      delete_key("DATABASE_USER")
      delete_key("DATABASE_PASS")
      delete_key("API_KEY")
      delete_key("API_DEBUG_KEY")
      delete_key("CACHE_TEST")
      delete_key("CACHE_TEST_2")

      file =
        create_file("""
        DATABASE_URL=secret:///db/prod/credentials#url
        DATABASE_USER=secret:///db/prod/credentials#username
        DATABASE_PASS=secret:///db/prod/credentials#password
        API_KEY=secret:///api/keys#prod
        API_DEBUG_KEY=secret:///api/keys#debug
        CACHE_TEST=secret:///cache/test#value
        CACHE_TEST_2=secret:///cache/test#value
        """)

      PseudoSecretManager.mock(%{
        "/db/prod/credentials" => %{
          "url" => "postgres://prod.example.com:5432/mydb",
          "username" => "prod_user",
          "password" => "super_secret_pass"
        },
        "/api/keys" => %{
          "prod" => "pk_live_abc123",
          "debug" => "pk_test_xyz789"
        },
        "/cache/test" => %{"value" => "cached_value_123"}
      })

      _changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set_all: fn vars ->
            {resolved, stats} = PseudoSecretManager.resolve_all_with_stats(vars)
            send(self(), {:stats, stats})
            resolved
          end
        )
        |> Nvir.dotenv!(file)

      assert_received {:stats, stats}

      # Should fetch 3 unique secrets
      assert stats.fetches == 3
      # Should have 4 cache hits (7 total vars - 3 fetches)
      assert stats.hits == 4
      # Should have 3 unique secrets cached
      assert map_size(stats.cache) == 3

      assert "postgres://prod.example.com:5432/mydb" = System.fetch_env!("DATABASE_URL")
      assert "prod_user" = System.fetch_env!("DATABASE_USER")
      assert "super_secret_pass" = System.fetch_env!("DATABASE_PASS")
      assert "pk_live_abc123" = System.fetch_env!("API_KEY")
      assert "pk_test_xyz789" = System.fetch_env!("API_DEBUG_KEY")
      assert "cached_value_123" = System.fetch_env!("CACHE_TEST")
      assert "cached_value_123" = System.fetch_env!("CACHE_TEST_2")
    end

    test "resolves secret without fragment as full JSON" do
      delete_key("FULL_SECRET")

      file = create_file("FULL_SECRET=secret:///api/keys")

      PseudoSecretManager.mock(%{
        "/api/keys" => %{
          "prod" => "pk_live_abc123",
          "debug" => "pk_test_xyz789"
        }
      })

      Nvir.dotenv_loader()
      |> Nvir.dotenv_configure(before_env_set_all: {PseudoSecretManager, :resolve_all, []})
      |> Nvir.dotenv!(file)

      json = System.fetch_env!("FULL_SECRET")
      decoded = JSON.decode!(json)

      assert %{"prod" => "pk_live_abc123", "debug" => "pk_test_xyz789"} == decoded
    end

    test "works with overwrite sources" do
      delete_key("PROD_DB_URL")
      delete_key("PROD_DB_USER")
      delete_key("API_KEY")

      regular_file =
        create_file("""
        PROD_DB_URL=secret:///db/prod/credentials#url
        PROD_DB_USER=secret:///db/prod/credentials#username
        """)

      overwrite_file =
        create_file("""
        API_KEY=secret:///api/keys#debug
        """)

      PseudoSecretManager.mock(%{
        "/db/prod/credentials" => %{
          "url" => "postgres://prod.example.com:5432/mydb",
          "username" => "prod_user",
          "password" => "super_secret_pass"
        },
        "/api/keys" => %{
          "prod" => "pk_live_abc123",
          "debug" => "pk_test_xyz789"
        }
      })

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(before_env_set_all: {PseudoSecretManager, :resolve_all, []})
        |> Nvir.dotenv!([regular_file, overwrite: overwrite_file])

      assert "postgres://prod.example.com:5432/mydb" = System.fetch_env!("PROD_DB_URL")
      assert "prod_user" = System.fetch_env!("PROD_DB_USER")
      assert "pk_test_xyz789" = System.fetch_env!("API_KEY")

      assert %{
               "PROD_DB_URL" => "postgres://prod.example.com:5432/mydb",
               "PROD_DB_USER" => "prod_user",
               "API_KEY" => "pk_test_xyz789"
             } == changes
    end

    test "verifies hook execution order" do
      delete_key("PREFIXED_URL")
      delete_key("DB_URL")
      delete_key("PLAIN")

      file =
        create_file("""
        DB_URL=secret:///db/prod/credentials#url
        PLAIN=value
        """)

      PseudoSecretManager.mock(%{
        "/db/prod/credentials" => %{
          "url" => "postgres://prod.example.com:5432/mydb",
          "username" => "prod_user",
          "password" => "super_secret_pass"
        }
      })

      changes =
        Nvir.dotenv_loader()
        |> Nvir.dotenv_configure(
          before_env_set_all: {PseudoSecretManager, :resolve_all, []},
          before_env_set: fn
            {"DB_URL", v} -> {"PREFIXED_URL", v}
            other -> other
          end
        )
        |> Nvir.dotenv!(file)

      # If before_env_set_all ran first, PseudoSecretManager would see DB_URL and raise.
      # Since it doesn't raise, before_env_set must have run first and renamed it to PREFIXED_URL.
      assert "postgres://prod.example.com:5432/mydb" = System.fetch_env!("PREFIXED_URL")
      assert "value" = System.fetch_env!("PLAIN")
      assert :error = System.fetch_env("DB_URL")

      assert %{
               "PREFIXED_URL" => "postgres://prod.example.com:5432/mydb",
               "PLAIN" => "value"
             } == changes
    end
  end

  describe "variable interpolation" do
    test "use interpolation of existing variables" do
      put_key("WHO", "world")
      delete_key("HELLO")

      file =
        create_file("""
        HELLO=hello $WHO
        """)

      assert %{"HELLO" => _} = Nvir.dotenv!(file)

      assert "hello world" = System.fetch_env!("HELLO")
    end

    test "use interpolation of variable in the same file" do
      delete_key("WHO")
      delete_key("HELLO")

      file =
        create_file("""
        WHO=world
        HELLO=hello $WHO
        """)

      assert %{"HELLO" => _, "WHO" => _} = Nvir.dotenv!(file)

      assert "hello world" = System.fetch_env!("HELLO")
    end

    test "do not use interpolation of variable in the same file if preexisting" do
      # This stands true for the regular group, not overwrites
      put_key("WHO", "moon")
      delete_key("HELLO")

      file =
        create_file("""
        WHO=world
        HELLO=hello $WHO
        """)

      assert %{"HELLO" => "hello moon"} == Nvir.dotenv!(file)

      assert "hello moon" = System.fetch_env!("HELLO")
    end

    test "use interpolation from the last file if not preexisting" do
      delete_key("WHO")
      delete_key("HELLO")

      # The last file should take precedence over the first one when we are
      # merging variables

      file_1 =
        create_file("""
        WHO=world
        """)

      file_2 =
        create_file("""
        WHO=moon
        HELLO=hello $WHO
        """)

      assert %{"HELLO" => "hello moon", "WHO" => "moon"} == Nvir.dotenv!([file_1, file_2])

      assert "hello moon" = System.fetch_env!("HELLO")
    end

    test "use interpolation from the last file if not preexisting - 3 levels" do
      delete_key("WHO")
      delete_key("HELLO")

      # The last file should take precedence over the first one when we are
      # merging variables

      file_1 =
        create_file("""
        WHO=world
        """)

      file_2 =
        create_file("""
        WHO=mars
        HELLO=hello $WHO
        """)

      file_3 =
        create_file("""
        WHO=moon
        HELLO=hello $WHO
        """)

      assert %{"HELLO" => "hello moon", "WHO" => "moon"} == Nvir.dotenv!([file_1, file_2, file_3])

      assert "hello moon" = System.fetch_env!("HELLO")
    end

    test "use interpolation from the last file if not preexisting - 3 levels, define on 2" do
      delete_key("WHO")
      delete_key("HELLO")

      # This time, HELLO is not overridden in the 3d file. So it cannot use the
      # last vaue for WHO.

      file_1 =
        create_file("""
        WHO=world
        """)

      file_2 =
        create_file("""
        WHO=mars
        HELLO=hello $WHO
        """)

      file_3 =
        create_file("""
        WHO=moon
        """)

      assert %{"HELLO" => "hello mars", "WHO" => "moon"} == Nvir.dotenv!([file_1, file_2, file_3])

      assert "hello mars" = System.fetch_env!("HELLO")
      assert "moon" = System.fetch_env!("WHO")
    end

    test "interpolate with same variable" do
      delete_key("XPATH")

      file =
        create_file("""
        XPATH=b
        XPATH=$XPATH:c
        XPATH=a:$XPATH
        """)

      assert %{"XPATH" => "a:b:c"} == Nvir.dotenv!(file)

      assert "a:b:c" = System.fetch_env!("XPATH")
    end

    test "with overwrites" do
      put_key("WHO", "earth")
      put_key("HELLO", "greetings!")
      delete_key("NEW_KEY")

      # This time, HELLO is not overridden in the 3d file. So it cannot use the
      # last vaue for WHO.

      file_1 =
        create_file("""
        WHO=world
        """)

      file_2 =
        create_file("""
        WHO=mars
        HELLO=hello $WHO
        NEW_KEY=defined!
        """)

      file_3 =
        create_file("""
        WHO=moon
        """)

      assert %{"HELLO" => "hello mars", "WHO" => "moon", "NEW_KEY" => "defined!"} ==
               Nvir.dotenv!(overwrite: [file_1, file_2, file_3])

      assert "hello mars" = System.fetch_env!("HELLO")
      assert "moon" = System.fetch_env!("WHO")
      assert "defined!" = System.fetch_env!("NEW_KEY")
    end
  end

  defp valid_error!(e) do
    msg = Exception.message(e)
    refute msg =~ "retrieving Exception.message/1"
    e
  end

  describe "get env var without default" do
    test "valid" do
      put_key("SOME_INT", "1234")
      assert 1234 = Nvir.env!("SOME_INT", :integer!)
    end

    test "defaults to string" do
      put_key("SOME_INT", "1234")
      put_key("SOME_STR", "")
      assert "1234" = Nvir.env!("SOME_INT")
      assert "" = Nvir.env!("SOME_STR")
    end

    test "invalid" do
      put_key("SOME_INT", "not an int")

      valid_error!(
        assert_raise Nvir.CastError, ~r/does not satisfy/, fn ->
          assert 1234 = Nvir.env!("SOME_INT", :integer!)
        end
      )
    end

    test "empty rejected" do
      put_key("SOME_INT", "")

      valid_error!(
        assert_raise Nvir.CastError, ~r/empty value/, fn ->
          assert 1234 = Nvir.env!("SOME_INT", :integer!)
        end
      )

      # legacy :integer has the same behaviour as :integer!
      Cast.ignore_warnings()

      valid_error!(
        assert_raise Nvir.CastError, ~r/empty value/, fn ->
          assert 1234 = Nvir.env!("SOME_INT", :integer)
        end
      )
    end

    test "empty nil" do
      put_key("SOME_INT", "")
      assert nil == Nvir.env!("SOME_INT", :integer?)
    end

    test "missing" do
      delete_key("SOME_INT")

      err =
        valid_error!(
          assert_raise System.EnvError, fn ->
            Nvir.env!("SOME_INT", :integer)
          end
        )

      assert "could not fetch environment variable \"SOME_INT\" because it is not set" ==
               Exception.message(err)
    end

    test "with custom cast" do
      put_key("SOME_INT", "hello")

      assert "badint" = Nvir.env!("SOME_INT", fn "hello" -> {:ok, "badint"} end)

      valid_error!(
        assert_raise Nvir.CastError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> {:error, "nope!"} end)
        end
      )

      valid_error!(
        assert_raise RuntimeError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> :bad_return_value end)
        end
      )
    end

    test "invalid cast cast" do
      put_key("SOME_INT", "1234")

      valid_error!(
        assert_raise ArgumentError, ~r/unknown cast/, fn ->
          Nvir.env!("SOME_INT", :bad_caster)
        end
      )
    end
  end

  describe "get env var with default" do
    test "valid" do
      put_key("SOME_INT", "1234")
      assert 1234 = Nvir.env!("SOME_INT", :integer!, 9999)
    end

    test "invalid" do
      put_key("SOME_INT", "not an int")

      # The key exists, so we will try to cast it and not fallback on the
      # default if the cast fails.

      valid_error!(
        assert_raise Nvir.CastError, ~r/does not satisfy/, fn ->
          assert 1234 = Nvir.env!("SOME_INT", :integer!, 9999)
        end
      )
    end

    test "empty bang" do
      put_key("SOME_INT", "")

      # Key is set so we try to cast

      valid_error!(
        assert_raise Nvir.CastError, ~r/empty value/, fn ->
          assert 1234 = Nvir.env!("SOME_INT", :integer!, 9999)
        end
      )
    end

    test "empty nil" do
      put_key("SOME_INT", "")

      # Not using default as the key is set.

      assert nil == Nvir.env!("SOME_INT", :integer?, 9999)
    end

    test "missing" do
      delete_key("SOME_INT")

      # Using the default here
      assert 9999 = Nvir.env!("SOME_INT", :integer, 9999)

      # Not validating the default
      assert "not an int" = Nvir.env!("SOME_INT", :integer, "not an int")
    end

    test "with custom cast" do
      put_key("SOME_INT", "hello")
      delete_key("NON_EXISTING")

      assert "badint" = Nvir.env!("SOME_INT", fn "hello" -> {:ok, "badint"} end, 9999)

      valid_error!(
        assert_raise Nvir.CastError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> {:error, "nope!"} end, 9999)
        end
      )

      valid_error!(
        assert_raise RuntimeError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> :bad_return_value end, 9999)
        end
      )

      valid_error!(
        assert_raise RuntimeError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> {:error, :not_a_string} end, 9999)
        end
      )

      # bad function will not be called if we use the default
      assert 9999 = Nvir.env!("NON_EXISTING", fn "hello" -> :bad_return_value end, 9999)
    end

    test "custom cast returning cast error" do
      put_key("SOME_INT", "hello")

      valid_error!(
        assert_raise Nvir.CastError, fn ->
          Nvir.env!("SOME_INT", fn "hello" -> Cast.cast("hello", :integer!) end, 9999)
        end
      )
    end

    test "custom cast returning unknown reason" do
      put_key("SOME_INT", "hello")

      assert_raise RuntimeError, ~r/invalid return value from custom validator/, fn ->
        Nvir.env!("SOME_INT", fn "hello" -> {:error, :something_strange} end)
      end
    end

    test "invalid cast cast" do
      put_key("SOME_INT", "1234")
      delete_key("NON_EXISTING")

      valid_error!(
        assert_raise ArgumentError, ~r/unknown cast/, fn ->
          Nvir.env!("SOME_INT", :bad_caster, 9999)
        end
      )

      # bad caster will not be checked if we use the default
      assert 9999 = Nvir.env!("NON_EXISTING", :bad_caster, 9999)
    end

    test "lazy default" do
      delete_key("LAZY_DEFAULT")

      # Default is a function
      assert "lazy" = Nvir.env!("LAZY_DEFAULT", :string, fn -> "lazy" end)

      # Function is not called if env var exists
      put_key("LAZY_DEFAULT", "exists")

      assert "exists" =
               Nvir.env!("LAZY_DEFAULT", :string, fn ->
                 raise "Should not be called"
               end)
    end
  end

  describe "custom parser" do
    test "configuring and using a custom parser" do
      defmodule CustomParser do
        @behaviour Nvir.Parser

        @impl true
        def parse_file(_) do
          {:ok, [{"CUSTOM_PARSER_VAR", "stubbed"}]}
        end
      end

      _ = delete_key("CUSTOM_PARSER_VAR")
      assert :error = System.fetch_env("CUSTOM_PARSER_VAR")

      file =
        create_file("""
        This file is not valid but
        the parser will return
        stubbed content
        """)

      assert %{"CUSTOM_PARSER_VAR" => _} =
               Nvir.dotenv_new()
               |> Nvir.dotenv_configure(parser: CustomParser)
               |> Nvir.dotenv!(file)

      assert "stubbed" = System.fetch_env!("CUSTOM_PARSER_VAR")
    end

    test "custom parser errors can produce a message" do
      defmodule BadCustomParser do
        @behaviour Nvir.Parser

        @impl true
        def parse_file(_) do
          {:error, :a_raw_reason}
        end
      end

      file = create_file("")

      err =
        catch_error(
          Nvir.dotenv_new()
          |> Nvir.dotenv_configure(parser: BadCustomParser)
          |> Nvir.dotenv!(file)
        )

      assert Exception.message(err) =~ ":a_raw_reason"
    end
  end

  describe "custom file location" do
    test "using the :cd option" do
      _ = delete_key("USING_CWD")

      dir = Briefly.create!(directory: true)
      filename = "some.env"

      File.write(Path.join(dir, filename), """
      USING_CWD=nope
      """)

      assert %{"USING_CWD" => "nope"} =
               Nvir.dotenv_loader()
               |> Nvir.dotenv_configure(cd: dir)
               |> Nvir.dotenv!(filename)

      # ...they are now defined
      assert "nope" = System.fetch_env!("USING_CWD")
    end

    test "using the :cd option with chardata" do
      _ = delete_key("USING_CHARDATA")

      dir = Briefly.create!(directory: true)
      dir = [dir, "/", "nvir", ?-, ~c"test", "-with", ~c"char-", [?d, ?a, ?t, ?a]]
      File.mkdir_p!(dir)

      filename = "some.env"

      File.write(Path.join(dir, filename), """
      USING_CHARDATA=yes
      """)

      assert %{"USING_CHARDATA" => "yes"} =
               Nvir.dotenv_loader()
               |> Nvir.dotenv_configure(cd: dir)
               |> Nvir.dotenv!(filename)

      # ...they are now defined
      assert "yes" = System.fetch_env!("USING_CHARDATA")
    end

    test "using :cd with absolute paths" do
      _ = delete_key("USING_CWD")
      _ = delete_key("USING_ABS")

      # use an absolute filename
      abs_filename =
        create_file("""
        USING_ABS=yes
        """)

      # also use a relative file for this test
      dir = Briefly.create!(directory: true)
      rel_filename = "rel.env"

      File.write(Path.join(dir, rel_filename), """
      USING_CWD=nope
      """)

      # both files are not in the same directory
      refute Path.dirname(abs_filename) == dir

      assert %{"USING_CWD" => "nope", "USING_ABS" => "yes"} =
               Nvir.dotenv_loader()
               |> Nvir.dotenv_configure(cd: dir)
               |> Nvir.dotenv!([rel_filename, abs_filename])

      # ...they are now defined
      assert "nope" = System.fetch_env!("USING_CWD")
    end
  end
end
