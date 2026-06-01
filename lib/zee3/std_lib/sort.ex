defmodule Zee3.StdLib.Sort do
  @moduledoc """
  Standard SMT-LIB2 Sorts (Types) for the Zee3 DSL.

  All functions return an AST node representing an S-Expression.
  """
  alias Zee3.Smt2
  import Zee3.Smt2

  # --- Base Sorts (Symbols) ---

  @spec bool() :: Smt2.t()
  def bool(), do: Smt2.symbol("Bool")

  @spec int() :: Smt2.t()
  def int(), do: Smt2.symbol("Int")

  @spec real() :: Smt2.t()
  def real(), do: Smt2.symbol("Real")

  @spec string() :: Smt2.t()
  def string(), do: Smt2.symbol("String")

  @spec reg_lan() :: Smt2.t()
  def reg_lan(), do: Smt2.symbol("RegLan")

  @spec rounding_mode() :: Smt2.t()
  def rounding_mode(), do: Smt2.symbol("RoundingMode")

  # --- Floating Point Aliases (Symbols) ---

  @spec float16() :: Smt2.t()
  def float16(), do: Smt2.symbol("Float16")

  @spec float32() :: Smt2.t()
  def float32(), do: Smt2.symbol("Float32")

  @spec float64() :: Smt2.t()
  def float64(), do: Smt2.symbol("Float64")

  @spec float128() :: Smt2.t()
  def float128(), do: Smt2.symbol("Float128")

  # --- Parameterized Sorts (Identifiers) ---

  @doc """
  Creates a BitVector sort of a specific size.
  Generates SMT: (_ BitVec size)
  """
  @spec bit_vec(integer() | Smt2.t()) :: Smt2.t()

  def bit_vec(size) when is_integer(size) and size > 0 do
    Smt2.call("_", [Smt2.symbol("BitVec"), size])
  end

  def bit_vec(size) when is_integer(size) and size <= 0 do
    raise "The size of a BitVec must be positive. Got invalid value #{size}."
  end

  def bit_vec(size) when not is_smt2(size) do
    raise "The size of a BitVec must be a positive integer. Got `#{size}` instead."
  end

  @doc """
  Creates a custom FloatingPoint sort.
  eb: exponent bits, sb: significand bits.
  Generates SMT: (_ FloatingPoint eb sb)
  """
  @spec floating_point(integer() | Smt2.t(), integer() | Smt2.t()) :: Smt2.t()
  def floating_point(eb, sb) when
        is_integer(eb) and
        eb > 0 and
        is_integer(sb)
        and sb > 0 do

    Smt2.call("_", [Smt2.symbol("FloatingPoint"), to_smt2(eb), to_smt2(sb)])
  end

  def floating_point(eb, sb) when not (is_smt2(eb) and is_smt2(sb)) do
    raise "Invalid arguments: #{inspect(eb)} and #{inspect(sb)}"
  end

  # --- Application Sorts (App) ---

  @doc """
  Creates an Array sort mapping a domain to a range.
  Generates SMT: (Array domain_sort range_sort)
  """
  @spec floating_point(Smt2.t(), Smt2.t()) :: Smt2.t()
  def array(domain_sort, range_sort) do
    Smt2.call("Array", [domain_sort, range_sort])
  end

  # ------- Custom ----------

  @doc """
  A special sort which serves as an alias for a BitVec of length 32.

  This is meant to be used as the type of entity IDs for the datalog
  engine, which needs a finite sort, and defaulting to a BitVec
  of this size seems like a safe option.
  """
  @spec entity_id() :: Smt2.t()
  def entity_id(), do: Smt2.call("_", [Smt2.symbol("BitVec"), Smt2.integer(32)])
end
