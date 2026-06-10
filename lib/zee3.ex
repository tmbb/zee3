defmodule Zee3 do
  @moduledoc """
  The main entry point for the `Zee3` functionality.
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
  Stops the stateful solver process.
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
  Declares an relation for the fixpoint datalog engine.
  """
  @spec declare_rel(pid(), binary(), list(binary())) :: :ok
  def declare_rel(solver_pid, name, param_types) do
    Solver.declare_rel(solver_pid, name, param_types)
  end

  @doc """
  Declares a variable which can be used in rules in the datalog engine.
  """
  @spec declare_var(pid(), binary(), binary()) :: :ok
  def declare_var(solver_pid, name, param_types) do
    Solver.declare_var(solver_pid, name, param_types)
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
  @spec pop(pid()) :: :ok
  def pop(pid) do
    Solver.pop(pid)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable.
  """
  @spec check_sat_and_get_model(pid(), keyword()) :: {:ok, any()} | {:error, any()}
  def check_sat_and_get_model(solver_pid, opts \\ []) do
    Solver.check_sat_and_get_model(solver_pid, opts)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable. *Raises on error*.
  """
  @spec check_sat_and_get_model!(pid(), keyword()) :: {:sat, any()} | :unsat | :unknown
  def check_sat_and_get_model!(solver_pid, opts \\ []) do
    Solver.check_sat_and_get_model!(solver_pid, opts)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable.
  """
  @spec check_sat(pid(), keyword()) :: {:ok, :sat | :unsat | :unknown} | {:error, any()}
  def check_sat(solver_pid, opts \\ []) do
    Solver.check_sat(solver_pid, opts)
  end

  @doc """
  Check for satisfiability and get the model in case it is
  actually satisfiable. *Raises on error*.
  """
  @spec check_sat(pid(), keyword()) :: :sat | :unsat | :unknown
  def check_sat!(solver_pid, opts \\ []) do
    Solver.check_sat!(solver_pid, opts)
  end

  @doc """
  Query a datalog relation to return all valid pairs.
  """
  def query(solver_pid, opts \\ []) do
    Solver.check_sat!(solver_pid, opts)
  end

  @doc """
  Query a datalog relation to return all valid pairs. Raises on error.
  """
  def query!(solver_pid, opts \\ []) do
    Solver.check_sat!(solver_pid, opts)
  end

  @doc """
  Runs raw SMT-LIB2 code in the current solver.
  Resturns `{:ok, data}` if there are no errors and
  `{:error, data}` if there is at least an error.
  The payload `data` is the raw output of the solver,
  parsed into a list of `%Smt.XXX` values.
  """
  def eval_smt2_code(solver_pid, raw_smt2_code) do
    Solver.eval_smt2_code(solver_pid, raw_smt2_code)
  end

  @doc """
  Declares a rule for the datalog fixpoint engine.
  """
  def rule(solver_pid, body) do
    Solver.rule(solver_pid, body)
  end

  @doc """
  Return an entity id from a value
  """
  def entity_id(solver_pid, value) do
    Solver.entity_id(solver_pid, value)
  end

  @doc """
  Gets the PID for the current Z3 process.
  This function only works if called inside a function
  that was invokes inside a `Zee3.program/2` block.
  """
  def current_z3_pid! do
    Process.get(:zee3_z3_pid) ||
      raise "Zee3 function called outside of a Zee3.program block!"
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
