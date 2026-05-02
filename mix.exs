defmodule Zee3.MixProject do
  use Mix.Project

  def project do
    [
      app: :zee3,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:zee3],
      deps: deps()
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
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
    ]
  end
end
