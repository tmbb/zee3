defmodule Zee3.Smt2.List do
  @moduledoc """
  Module to represent Z3 list literals.
  """
  defstruct [:value]

  @type t() :: %__MODULE__{}
end
