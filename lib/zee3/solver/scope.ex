defmodule Zee3.Solver.Scope do
  @moduledoc false

  # This structure supports variable and constructed names
  # added to the Z3 solver. Each scope corresponds to a single
  # `(push)` context, and it can be removed by `(pop)`.

  defstruct vars: [],
            constructors: MapSet.new()

  @doc """
  Create an empty scope.
  """
  def empty() do
    %__MODULE__{}
  end

  @doc """
  Create a scope from a list of variables
  """
  def from_vars(variables) do
    %__MODULE__{vars: variables}
  end

  @doc """
  Put a new variable in the scope.
  """
  def put_var(scope, variable) do
    %{scope | vars: [variable | scope.vars]}
  end

  def vars_from_scopes(scopes) when is_list(scopes) do
    Enum.flat_map(scopes, fn scope -> scope.vars end)
  end

  def constructors_from_scopes(scopes) when is_list(scopes) do
    scopes
    |> Enum.map(fn scope -> scope.constructors end)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end
end
