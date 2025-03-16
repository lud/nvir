defmodule Nvir.CastTest do
  alias Nvir.Cast
  use ExUnit.Case, async: true

  defdelegate cast(value, type), to: Cast

  def atom_exists?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    _ in ArgumentError -> false
  end

  setup do
    Cast.ignore_warnings()
    :ok
  end

  describe "atom" do
    test "create the atom if it does not exist" do
      string = inspect(make_ref())
      refute atom_exists?(string)
      assert {:ok, _} = cast(string, :atom)
      assert atom_exists?(string)
    end

    test "empty string to nil" do
      assert {:ok, :""} = cast("", :atom)
      assert {:ok, nil} = cast("", :atom?)
      assert {:ok, :some} = cast("some", :atom?)
    end

    test "bang no nil" do
      assert {:ok, :bang} = cast("bang", :atom!)
      assert {:error, :empty} = cast("", :atom!)
    end
  end

  describe "existing atom" do
    test "error for non existing atoms" do
      string = inspect(make_ref())
      refute atom_exists?(string)
      assert {:error, :bad_cast} = cast(string, :existing_atom)
      refute atom_exists?(string)

      assert {:ok, :""} = cast("", :existing_atom)
      assert {:ok, :some} = cast("some", :existing_atom)
    end

    test "empty string to nil" do
      assert {:ok, :some} = cast("some", :existing_atom?)
      assert {:ok, nil} = cast("", :existing_atom?)
    end

    test "empty string rejection" do
      assert {:ok, :some} = cast("some", :existing_atom!)
      assert {:error, :empty} = cast("", :existing_atom!)
    end
  end

  describe "boolean" do
    test "falsy values" do
      assert {:ok, false} == cast("", :boolean)
      assert {:ok, false} == cast("false", :boolean)
      assert {:ok, false} == cast("FALSE", :boolean)
      assert {:ok, false} == cast("FaLsE", :boolean)
      assert {:ok, false} == cast("0", :boolean)
    end

    test "truthy values" do
      assert {:ok, true} == cast("anything else", :boolean)
    end

    test "strict casting" do
      # case insensitive booleans
      assert {:ok, false} == cast("false", :boolean!)
      assert {:ok, false} == cast("FALSE", :boolean!)
      assert {:ok, false} == cast("FaLsE", :boolean!)

      assert {:ok, true} == cast("true", :boolean!)
      assert {:ok, true} == cast("TRUE", :boolean!)
      assert {:ok, true} == cast("tRuE", :boolean!)

      # zero or one
      assert {:ok, false} == cast("0", :boolean!)
      assert {:ok, true} == cast("1", :boolean!)

      # other values are not valid booleans
      assert {:error, :bad_cast} == cast("anything else", :boolean!)
      assert {:error, :bad_cast} == cast("off", :boolean!)
      assert {:error, :bad_cast} == cast("on", :boolean!)
      assert {:error, :bad_cast} == cast("", :boolean!)
    end

    test "legacy" do
      # not documented
      assert {:ok, false} == cast("", :boolean?)
      assert {:ok, false} == cast("false", :boolean?)
      assert {:ok, false} == cast("FALSE", :boolean?)
      assert {:ok, false} == cast("FaLsE", :boolean?)
      assert {:ok, false} == cast("0", :boolean?)
      assert {:ok, true} == cast("anything else", :boolean?)
    end
  end

  describe "floats" do
    test "legacy" do
      # :float behaves the same as :float!
      assert {:error, :empty} = cast("", :float)
    end

    test "float conversion" do
      assert {:ok, 1.23} = cast("1.23", :float!)
      assert {:ok, 1.0} = cast("1", :float!)
      assert {:ok, -1.23} = cast("-1.23", :float!)
      assert {:ok, +0.0} = cast("0", :float!)
      assert {:ok, +0.0} = cast("0.0", :float!)
      assert {:ok, -0.0} = cast("-0.0", :float!)
      assert {:error, :bad_cast} = cast("1.2.3", :float!)
      assert {:error, :empty} = cast("", :float!)
    end

    test "empty string to nil" do
      assert {:ok, 45.6} = cast("45.6", :float?)
      assert {:ok, nil} = cast("", :float?)
    end
  end

  describe "integers" do
    test "legacy" do
      # :integer behaves the same as :integer!
      assert {:error, :empty} = cast("", :integer)
    end

    test "integer conversion" do
      assert {:ok, 1} = cast("1", :integer!)
      assert {:ok, -1} = cast("-1", :integer!)
      assert {:ok, 0} = cast("0", :integer!)
      assert {:ok, -0} = cast("-0", :integer!)
      assert {:error, :bad_cast} = cast("1.2", :integer!)
      assert {:error, :empty} = cast("", :integer!)
    end

    test "empty string to nil" do
      assert {:ok, 45} = cast("45", :integer?)
      assert {:ok, nil} = cast("", :integer?)
    end
  end

  describe "string" do
    test "any string" do
      assert {:ok, ""} = cast("", :string)
      assert {:ok, "hello"} = cast("hello", :string)
    end

    test "empty string to nil" do
      assert {:ok, nil} = cast("", :string?)
      assert {:ok, "hello"} = cast("hello", :string?)
    end

    test "reject empty string" do
      assert {:error, :empty} = cast("", :string!)
      assert {:ok, "hello"} = cast("hello", :string!)
    end
  end

  describe "callback validator" do
    test "returns ok" do
      assert {:ok, 123} = cast("...", fn _ -> {:ok, 123} end)
    end

    test "returns error message" do
      assert {:error, "nope!"} = cast("...", fn _ -> {:error, "nope!"} end)
    end

    test "returns result from other cast" do
      assert {:error, :bad_cast} = cast("...", fn _ -> {:error, :bad_cast} end)
      assert {:error, :empty} = cast("...", fn _ -> {:error, :empty} end)
    end

    test "returns invalid error" do
      assert_raise RuntimeError, ~r/invalid return value/, fn ->
        cast("...", fn _ -> {:error, :something_else} end)
      end
    end
  end

  describe "unknown caster" do
    test "unknown caster" do
      assert_raise ArgumentError, ~r/unknown cast type.*some_unknown_caster/, fn ->
        cast("...", :some_unknown_caster)
      end
    end
  end
end
