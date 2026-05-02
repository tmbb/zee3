defmodule Zee3.Smt2.Int do
  @moduledoc """
  Module to represent Z3 integer literals.
  """
  defstruct [:value]

  @type t() :: %__MODULE__{}
end
