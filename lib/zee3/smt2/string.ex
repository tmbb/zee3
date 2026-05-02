defmodule Zee3.Smt2.String do
  @moduledoc """
  Module to represent Z3 string literals.
  """
  defstruct [:value]

  @type t() :: %__MODULE__{}
end
