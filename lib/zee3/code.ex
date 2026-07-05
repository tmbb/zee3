defmodule Zee3.Code do
  alias Zee3.Smt2

  @derive {Inspect, only: []}

  defstruct contents: []

  def new(contents \\ []) do
    %__MODULE__{contents: List.wrap(contents)}
  end

  def append(code, contents) do
    %{code | contents: [code.contents, contents]}
  end

  def to_iodata(code, _opts \\ []) do
    code.contents
    |> List.flatten()
    |> Enum.map(&Smt2.serialize/1)
    |> Enum.intersperse("\n")
  end

  def to_string(code, opts \\ []) do
    code
    |> to_iodata(opts)
    |> IO.iodata_to_binary()
  end
end
