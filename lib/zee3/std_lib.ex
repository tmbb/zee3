defmodule Zee3.StdLib do
  @moduledoc """
  Defines the functions and macros which are available
  inside the body of the `Zee3.program/2` macro.

  The functions of this module are all pure in the sense
  that they don't mutate the state of the solver.
  All the functions (but not necessarily the macros) return
  a `Zee3.Smt2` term which will be handled correctly by
  the stateful special forms inside the program.
  The result of these functions can always be serialized
  into syntactically correct SMT-LIB2 code, which can be
  sent directly to the Z3 solver using the low-level API.
  """
  require Zee3.StdLib.StdLibBuilder, as: StdLibBuilder
  alias Zee3.Smt2
  import Zee3.Smt2, only: [is_smt2: 1]

  StdLibBuilder.__build_from_tsv_file__("lib/zee3/reference/functions.tsv")

  # Functions we can't generate programmatically from
  # the TSV file above

  @doc """
  Check that two terms are equal.
  """
  @spec Smt2.smt2_like() == Smt2.smt2_like() :: Smt2.t()
  def a == b do
    Smt2.call("=", [a, b])
  end

  @doc """
  Check that two terms are distinct.
  """
  @spec Smt2.smt2_like() != Smt2.smt2_like() :: Smt2.t()
  def a != b do
    Smt2.call("distinct", [a, b])
  end

  @doc """
  Sum the arguments.
  """
  @spec sum(list(Smt2.smt2_like())) :: Smt2.t()
  def sum(args) do
    Smt2.call("+", args)
  end

  @doc """
  Multiply the arguments.
  """
  @spec product(list(Smt2.smt2_like())) :: Smt2.t()
  def product([_x1, _x2 | _args] = args) do
    Smt2.call("*", args)
  end

  @doc """
  Check if all the arguments are equal.
  """
  @spec all_equal(list(Smt2.smt2_like())) :: Smt2.t()
  def all_equal([_x1, _x2 | _args] = args) do
    Smt2.call("=", args)
  end

  @doc """
  Check that all the arguments are distinct.

  Just like the `!=` operator compiles into the
  Z3 binary `(distinct x1 x2)` operator, this
  function compiles to the variadic `(distinct ...)`
  operator
  """
  @spec all_distinct(list(Smt2.smt2_like())) :: Smt2.t()
  def all_distinct([_x1, _x2 | _args] = args) do
    Smt2.call("distinct", args)
  end

  @doc """
  Checks that all arguments are true.

  Just like the `and` operator compiles into the
  Z3 binary `(and x1 x2)` operator, this
  function compiles to the variadic `(and ...)`
  operator
  """
  @spec all(list(Smt2.smt2_like())) :: Smt2.t()
  def all([_x1 | _args] = args) do
    Smt2.call("and", args)
  end

  @doc """
  Checks that at least one of the arguments is true.

  Just like the `or` operator compiles into the
  Z3 binary `(or x1 x2)` operator, this
  function compiles to the variadic `(or ...)`
  operator
  """
  @spec any(list(Smt2.smt2_like())) :: Smt2.t()
  def any([_x1 | _args] = args) do
    Smt2.call("or", args)
  end

  @doc """
  Implication (left to right).
  """
  @spec implies(Smt2.smt2_like(), Smt2.smt2_like()) :: Smt2.t()
  def implies(lhs, rhs) do
    Smt2.call("=>", [lhs, rhs])
  end

  @doc """
  Implication (right to left).
  """
  @spec (Smt2.smt2_like() <- Smt2.smt2_like()) :: Smt2.t()
  def implied_by <- condition do
    Smt2.call("=>", [condition, implied_by])
  end

  @doc """
  A reimplementation of the `Kernel.if/2` macro that
  raises an error if one tries to pick a branch based
  on a `Zee3.Smt2` value.

  If you're trying to pick a branch based on a `Zee3.Smt2`
  value, you're probably making a mistake because all
  `Zee3.Smt2` terms are considered `true` by the normal
  `Kernel.if/2` macro.

  If you want to pick a branch based on a condition inside
  `Z3`, you want to use the `ite/3` function instead.

  This macro is automatically imported inside the body
  of the `Zee3.program do ... end` macro.
  Apart from raising an error on `Zee3.Smt2` terms,
  it behaves exactly as the `Kernel.if/2` macro.
  """
  defmacro if(condition, branches) do
    quote [generated: true] do
      condition = unquote(condition)

      case condition do
        c when is_smt2(c) ->
          raise "Can't use `if` on an Zee3.Smt2 value." <>
            " You are probabbly making a mistake." <>
            " You either want the `ite(x, y, z)` functions or" <>
            " you want to pick a branch base on a 'raw' elixir term."

        _other ->
          Kernel.if(unquote(condition), unquote(branches))
      end
    end
  end

  defmacro __using__(_opts \\ []) do
    quote do
      import Kernel,
        except: [
          -: 1,
          not: 1,
          +: 2,
          -: 2,
          *: 2,
          /: 2,
          and: 2,
          or: 2,
          <: 2,
          <=: 2,
          ==: 2,
          !=: 2,
          >=: 2,
          >: 2,
          div: 2,
          mod: 2,
          abs: 1,
          elixir: 1,
          # We implement "safer" versions of these macros
          # which error out if the user confuses them with
          # Z3 functions
          if: 2
        ]

      import Zee3.StdLib
      alias Zee3.StdLib.Sort
    end
  end

  @doc """
  Compiles the code given as an argument using the `Kernel`
  operations and functions and not the `zee3.StdLib` versions.

  The code inside is run as if it is "normal elixir code",
  by the BEAM and not as if it were Z3 code run inside the
  Z3 solver.
  """
  defmacro elixir(formula) do
    quote do
      (
        fn ->
          # Hide the Zee3.StdLib imports
          import Zee3.StdLib, only: []
          import Kernel
          unquote(formula)
        end
      ).()
    end
  end
end
