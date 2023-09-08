defmodule MemorySize do
  @moduledoc """
  This module provides two utilities for understanding what is using the memory in a complex data
  structure. summary/2 provides information about what fields are using data in a struct tree,
  while term/2 aims to be a fast, approximate replacement for :erts_debug.flat_size.
  """

  @default_sample_size 100

  @doc """
  Returns a list of tuples of the form {size, unit, path} summarizing the memory
  usage of the passed in value (if it's a struct, one tuple per recursive field
  will be returned. i.e. if state.guild.sessions is using 100 words, then one of
  the returned tuples would be {100, :word, [:guild, :sessions]}.

  Options available:
  - max_depth: maximum nesting level for returned tuples (0 means "just the top level", default is unlimited)
  - min_size: a threshold for dropping fields from the result that use less than some threshold
      amount of memory (default is to show all)
  - precision: How many digits should we keep after the decimal point (default is 2)
  - sample_size: control how many elements of large maps/lists will be sampled (default is 100)
  - sort_by_size: if true, will sort the results by size descending (otherwise will be sorted hierarchically)
  - unit: one of :word, :byte, :kilobyte, :megabyte, :gigabyte for scaling the results (default is word).
      Kilo means 1024 (in order to be consistent with `:recon_alloc.set_unit`)
  """
  def summary(value, options \\ []) do
    sample_size = Keyword.get(options, :sample_size, @default_sample_size)
    min_size = Keyword.get(options, :min_size, -1)
    max_depth = Keyword.get(options, :max_depth, :infinity)
    precision = Keyword.get(options, :precision, 2)
    unit = Keyword.get(options, :unit, :word)

    unit_scale = scale(unit)

    sort_mapper =
      if Keyword.get(options, :sort_by_size, false) do
        fn {size, _, path} -> {-size, path} end
      else
        fn {_, _, path} -> path end
      end

    do_size_summary(value, sample_size, [])
    |> Enum.map(fn {size, reverse_path} ->
      {Float.round(size / unit_scale, precision), unit, Enum.reverse(reverse_path)}
    end)
    |> Enum.filter(fn {size, _, _} -> size >= min_size end)
    |> Enum.filter(fn {_, _, path} -> length(path) <= max_depth end)
    |> Enum.sort_by(sort_mapper)
  end

  @doc """
  This estimates the size of an Erlang term. It intends to take a reasonable amount of time
  to complete, as opposed to :erts_debug.flat_size and :erts_debug.size. it does this by
  sampling large maps and lists. Note that it follows the convention of :erts_debug.size and
  does not include the 1 word for the term itself. This means that some of the calculations
  here will seem to be off from https://www.erlang.org/doc/efficiency_guide/advanced.html
  which includes this 1 word in the estimates it provides.
  """
  def term(value, sample_size \\ @default_sample_size)

  def term(value, sample_size) when is_list(value) do
    # A list takes 2 words (head and tail) per entry + the heap space needed for the contents
    2 * length(value) + raw_list_size(value, sample_size)
  end

  def term(value, sample_size) when is_map(value) do
    map_overhead(value) + raw_map_size(value, sample_size)
  end

  def term(value, sample_size) when is_tuple(value) do
    # A tuple takes 1 word for the count + a word for each entry
    list = Tuple.to_list(value)
    1 + length(list) + raw_list_size(list, sample_size)
  end

  def term(value, _sample_size) when is_bitstring(value) do
    # This is probably wrong. I don't know what the right answer is. :erts_debug.size seems
    # to always say 6 words regardless of size (except empty string is 2 words). It's definitely
    # going to need 1 word for each 8 bytes when you get down to it though.
    max(:erts_debug.size(value), byte_size(value) / 8 + 1)
  end

  def term(value, _sample_size) do
    :erts_debug.size(value)
  end

  # Calculates the sum of the heap space needed for the values of list. This does not include
  # the space needed for the list itself.
  defp raw_list_size([], _sample_size) do
    0
  end

  defp raw_list_size(list, sample_size) do
    value_sample = Enum.take_random(list, sample_size)
    value_sample_size = Enum.reduce(value_sample, 0, &(term(&1, sample_size) + &2))

    # scale the sampled values to the entire list
    value_sample_size * length(list) / length(value_sample)
  end

  defp raw_map_size(map, _sample_size) when map_size(map) == 0 do
    0
  end

  defp raw_map_size(%{__struct__: _} = map, sample_size) do
    # The "raw" size of the struct key and value are both 0 (they're both atoms so use 0 words
    # extra above the term itself)
    raw_map_size(Map.from_struct(map), sample_size)
  end

  defp raw_map_size(map, sample_size) do
    value_sample_size =
      Enum.take_random(map, sample_size)
      |> Enum.reduce(0, fn
        nil, acc -> acc
        {key, value}, acc -> term(key, sample_size) + term(value, sample_size) + acc
      end)

    map_size = map_size(map)
    value_sample_length = min(map_size, sample_size)

    value_sample_size * map_size / value_sample_length
  end

  defp map_overhead(map) do
    # according to the efficiency guide, it's 4 words of overhead up to 32 elements, then
    # beyond that it's somewhere between 1.6 - 1.8 words of overhead per element, plus a
    # word each for the key and value itself, so we use 3.7 as an estimate of that overhead.
    # For <= 32 elements, there are 4 words of overhead + the same word each for the key and
    # value.
    if map_size(map) > 32 do
      3.7 * map_size(map)
    else
      4 + 2 * map_size(map)
    end
  end

  defp do_size_summary(%MapSet{} = value, sample_size, path) do
    # Yeah it's seriously 10 words of overhead (4 for the struct map overhead, 2 each for the
    # key-value pairs in the struct (:__struct__, :map, and :version)
    [{term(value.map, sample_size) + 10, path}]
  end

  defp do_size_summary(value, sample_size, path) when is_struct(value) do
    {fields_sum, fields_summary} =
      Enum.reduce(Map.from_struct(value), {0, []}, fn {key, field_value},
                                                      {acc_sum, acc_summary} ->
        # The child's overall sum entry is the head of its size summary
        [{field_sum, _} | _] =
          field_summary = do_size_summary(field_value, sample_size, [key | path])

        {acc_sum + field_sum, field_summary ++ acc_summary}
      end)

    [{fields_sum + map_overhead(value), path} | fields_summary]
  end

  defp do_size_summary(value, sample_size, path) do
    [{term(value, sample_size), path}]
  end

  defp scale(:word), do: 1
  defp scale(:byte), do: 1 / 8
  defp scale(:kilobyte), do: 1024 / 8
  defp scale(:megabyte), do: 1024 * 1024 / 8
  defp scale(:gigabyte), do: 1024 * 1024 * 1024 / 8
end
