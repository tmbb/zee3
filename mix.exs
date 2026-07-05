defmodule Zee3.MixProject do
  use Mix.Project

  def project do
    [
      app: :zee3,
      version: "0.6.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:zee3],
      description: description(),
      package: package(),
      deps: deps(),
    ]
  end

  def description do
    "Bindings to the Z3 theorem prover."
  end

  defp package do
    [
      name: "zee3",
      files: ~w(lib .formatter.exs mix.exs README*
                LICENSE* CHANGELOG*),
      licenses: ["BSD-3-Clause"],
      links: %{"GitHub" => "https://github.com/tmbb/zee3"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.3"},
      {:libgraph, "~> 0.16", only: [:test]},
      {:expublish, "~> 2.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end
end
