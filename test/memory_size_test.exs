defmodule MemorySizeTest do
  use ExUnit.Case

  def test_value_list_exact_match(values) do
    Enum.each(
      values,
      fn value -> assert MemorySize.term(value) == :erts_debug.flat_size(value) end
    )
  end

  describe "term/2" do
    test "consistent with erts_debug for simple values" do
      test_value_list_exact_match([
        0,
        0.1,
        -1000,
        822_219_052_402_606_132,
        21_154_681_615_024_128,
        nil,
        'string',
        self(),
        make_ref(),
        :atom,
        &Kernel.tuple_size/1
      ])
    end

    test "consistent with erts_debug for small lists" do
      test_value_list_exact_match([[], [1, 2, 3], ['a', 'bc', :hello]])
    end

    test "Samples a big list" do
      # 'a' uses 2 words, nil uses 0. The list itself uses 4 words on top of that regardless of which sample we use.
      # So if we pick the 'a', we'll think each element uses 2 words so estimate 8; if we pick the nil, we'll think
      # each element uses 0 words so estimate 4
      Enum.each(1..100, fn _ -> assert MemorySize.term([nil, 'a'], 1) in [4.0, 8.0] end)
    end

    test "sampling a listaverages out to a correct value" do
      computed_sum =
        Enum.reduce(1..10000, 0, fn _, acc -> acc + MemorySize.term([nil, 'a'], 1) end)

      assert_in_delta computed_sum, 10000 * :erts_debug.flat_size([nil, 'a']), 1000
    end

    test "consistent with erts_debug for small maps/structs" do
      test_value_list_exact_match([
        %{},
        %{foo: 1},
        %{822_219_052_402_606_132 => 822_219_052_402_606_133},
        DateTime.now("Etc/UTC")
      ])
    end

    test "Close to consistent for maps above 32 elements, with and without sampling" do
      test_map =
        1..100
        |> Enum.map(&{&1, &1})
        |> Map.new()

      actual_size = :erts_debug.flat_size(test_map)

      assert_in_delta MemorySize.term(test_map, 100), actual_size, actual_size * 0.1

      # Every key and value uses the same amount of space, so they should be identical
      assert MemorySize.term(test_map, 100) == MemorySize.term(test_map, 10)
    end

    test "consistent with erts_debug for tuples" do
      test_value_list_exact_match([{}, {:hello}, {:foo, %{}, :bar}])
    end

    test "consistent with erts_debug for a complicated structure" do
      value = %{
        foo: [1, 'foobar1234567890', :hello, nil],
        bar: %{},
        baz: %{
          foo: nil,
          bar: self(),
          a: 0.123
        }
      }

      assert MemorySize.term(value) == :erts_debug.flat_size(value)
    end

    test "Returns at least what :erts_debug and the amount of space needed for the bytes themselves for binaries" do
      # Binaries are weird; see the comment in MemorySize for more context.
      cases = [
        "",
        "hello",
        "1234567890123456789012345678901234567890123456789012345678901234567890"
      ]

      Enum.each(
        cases,
        fn binary ->
          assert MemorySize.term(binary) >= :erts_debug.flat_size(binary)
          assert MemorySize.term(binary) >= byte_size(binary) / 8
        end
      )
    end
  end
end
