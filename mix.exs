defmodule MemorySize.MixProject do
  use Mix.Project

  def project do
    [
      app: :memory_size,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
end
