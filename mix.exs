defmodule MemorySize.MixProject do
  use Mix.Project

  def project do
    [
      app: :memory_size,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: [
        main: "MemorySize"
      ]
    ]
  end

  def application, do: []

  def deps do
    [
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  def package do
    [
      name: :memory_size,
      description: "A small library for estimating the memory usage of huge process states.",
      files: ["lib", ".formatter.exs", "README.md", "LICENSE", "mix.exs"],
      maintainers: ["Discord Realtime Infrastructure"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/discord/memory_size"
      }
    ]
  end
end
