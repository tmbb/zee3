defmodule Zee3.Smt2.BitVec do
  @moduledoc """
  Module to represent Z3 bit vector literals.
  """
  defstruct [:value]

  @type t() :: %__MODULE__{}
end
