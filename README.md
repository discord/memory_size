# MemorySize

This is a simple library for getting approximate memory usage of an Erlang/Elixir
term. It trades accuracy for speed by sampling very large lists and maps.

## Documentation

This library contains internal documentation.
Documentation is available on [HexDocs](https://hexdocs.pm/memory_size), 
or you can generate the documentation from source:

```bash
$ mix deps.get
$ mix docs
```

## Running the Tests

Tests can be run by running `mix test` in the root directory of the library.

## License

`MemorySize` is released under [the MIT License](LICENSE).
Check [LICENSE](LICENSE) file for more information.
