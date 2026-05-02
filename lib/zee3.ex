defmodule Zee3 do
  @moduledoc """
  Documentation for `Zee3`.
  """

  alias Zee3.Solver
  alias Zee3.Program

  @doc """
  Starts a new stateful solver process.

  When the solver is started, it automatically
  `push`es a new context.
  """
  @spec start_solver() :: GenServer.on_start()
  def start_solver() do
    Solver.start_link()
  end

  @doc """
  Starts the stateful solver process.
  """
  @spec stop_solver(pid()) :: :ok
  def stop_solver(pid) do
    Solver.stop(pid)
  end

  @doc """
  Declares a constant inside a stateful solver.
  """
  @spec declare_const(pid(), binary(), binary()) :: :ok
  def declare_const(solver_pid, name, type_string) do
    Solver.declare_const(solver_pid, name, type_string)
  end

  @doc """
  Declares an uninterpreted function inside a stateful solver.
  """
  @spec declare_fun(pid(), binary(), list(binary()), binary()) :: :ok
  def declare_fun(solver_pid, name, param_types, return_type) do
    Solver.declare_fun(solver_pid, name, param_types, return_type)
  end

  @doc """
  Declares datatypes inside a stateful solver.
  """
  @spec declare_datatypes(pid(), binary(), list(atom())) :: :ok
  def declare_datatypes(solver_pid, smt_declaration, constructor_atoms) do
    Solver.declare_datatypes(solver_pid, smt_declaration, constructor_atoms)
  end

  @doc """
  Asserts a constraint inside a stateful solver.
  """
  @spec assert(pid(), binary()) :: :ok
  def assert(solver_pid, constraint) do
    Solver.assert(solver_pid, constraint)
  end

  @doc """
  Pushes a new context into a stateful solver.
  """
  @spec push(pid()) :: :ok
  def push(pid) do
    Solver.push(pid)
  end

  @doc """
  Pops the last context from a stateful solver.
  """
  @spec push(pid()) :: :ok
  def pop(pid) do
    Solver.pop(pid)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable.
  """
  def check_sat_and_get_model(solver_pid, timeout \\ :infinity) do
    Solver.check_sat_and_get_model(solver_pid, timeout)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable. *Raises on error*.
  """
  def check_sat_and_get_model!(solver_pid, timeout \\ :infinity) do
    Solver.check_sat_and_get_model!(solver_pid, timeout)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable.
  """
  def check_sat(solver_pid, timeout \\ :infinity) do
    Solver.check_sat(solver_pid, timeout)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable. *Raises on error*.
  """
  def check_sat!(solver_pid, timeout \\ :infinity) do
    Solver.check_sat!(solver_pid, timeout)
  end

  @doc """
  Runs code inside the Z3 solver with the given `solver_pid`
  using an optimized elixir DSL.

  This macro doen't assume its contents are special in any way
  and it does not assume we want to push a new context.
  If you want to create or remove a context, you must call `push()`
  and `pop()` inside the body of the macro.
  """
  defmacro program(solver_pid, do: block) do
    Program.do_program(solver_pid, block)
  end
end
