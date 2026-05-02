defmodule Zee3.Interpreter do
  @moduledoc """
  Translates Z3 S-Expression ASTs into native Elixir data types,
  and compiles Z3 lambdas into executable Elixir anonymous functions.

  This interpreter is only expected to run S-expressions returned by Z3.
  It will probably not grow in scope in order to run general Z3 code.
  """
  alias Zee3.Smt2
  require Zee3.Interpreter.DynamicArityBuilder, as: DynamicArityBuilder

  @doc """
  Main entry point. Translates a top-level AST node from Z3 into an Elixir value.
  """
  def to_elixir(ast, constructors \\ MapSet.new())

  def to_elixir(%Smt2.List{value: [%Smt2.Symbol{value: "lambda"} | _]} = ast, constructors) do
    env = %{__constructors__: constructors}
    build_function(ast, env)
  end

  def to_elixir(ast, constructors) do
    env = %{__constructors__: constructors}
    eval(ast, env)
  end

  # Compiles a lambda AST into an Elixir anonymous function
  defp build_function(
         %Smt2.List{value: [%Smt2.Symbol{value: "lambda"}, %Smt2.List{value: params}, body]},
         env
       ) do
    # Extract parameter names from the binding list: ((x!1 Int) (y!2 Bool)) -> ["x!1", "y!2"]
    param_names =
      Enum.map(params, fn %Smt2.List{value: [%Smt2.Symbol{value: name}, _type]} -> name end)

    # Return a function with multiple arities
    build_interpreted_function(length(param_names), fn args ->
      # Bind incoming arguments to their Z3 variable names
      local_env = Enum.zip(param_names, args) |> Map.new()
      # Merge local scope with our global operators
      env = Map.merge(env, local_env)

      eval(body, env)
    end)
  end

  # --- The Core Evaluator ---

  # Special Form: If-Then-Else (Must short-circuit)
  defp eval(
         %Smt2.List{value: [%Smt2.Symbol{value: "ite"}, condition, true_branch, false_branch]},
         env
       ) do
    if eval(condition, env) do
      eval(true_branch, env)
    else
      eval(false_branch, env)
    end
  end

  # Handle Function/Operator Application
  defp eval(%Smt2.List{value: [%Smt2.Symbol{value: op_name} | arg_nodes]}, env) do
    if MapSet.member?(env.__constructors__, op_name) do
      # 1. Datatype Constructors (what we just built)
      evaled_args = Enum.map(arg_nodes, &eval(&1, env))
      List.to_tuple([String.to_atom(op_name) | evaled_args])
    else
      # 2. Standard Operators and Custom Lambdas
      evaled_args = Enum.map(arg_nodes, &eval(&1, env))

      cond do
        # If it's a custom function compiled into our environment (like a Z3 lambda)
        Map.has_key?(env, op_name) ->
          func = Map.fetch!(env, op_name)
          func.(evaled_args)

        # Otherwise, fall back to our hardcoded global operators
        true ->
          apply_op(op_name, evaled_args)
      end
    end
  end

  # --- The "Global Environment" via Pattern Matching ---

  # Symbol Lookup
  defp eval(%Smt2.Symbol{value: name}, env) do
    cond do
      Map.has_key?(env, name) ->
        Map.fetch!(env, name)

      MapSet.member?(env.__constructors__, name) ->
        # It's a valid, whitelisted zero-arity constructor. Safely atomize it.
        String.to_atom(name)

      true ->
        parse_special_symbol(name)
    end
  end

  # Literals
  defp eval(%Smt2.Int{value: i}, _env), do: i
  defp eval(%Smt2.String{value: s}, _env), do: s
  defp eval(%Smt2.BitVec{value: bv}, _env), do: bv

  defp parse_special_symbol("true"), do: true
  defp parse_special_symbol("false"), do: false
  defp parse_special_symbol(name), do: raise("Unbound variable or unknown operator: #{name}")

  # Booleans
  defp apply_op("not", [a]), do: not a
  defp apply_op("and", args), do: Enum.all?(args, &(&1 == true))
  defp apply_op("or", args), do: Enum.any?(args, &(&1 == true))

  # Equality / Inequality
  defp apply_op("=", [a, b]), do: a == b
  defp apply_op("distinct", [a, b]), do: a != b

  # Math
  defp apply_op("+", args), do: Enum.sum(args)
  defp apply_op("-", [a]), do: -a
  defp apply_op("-", [a, b]), do: a - b
  defp apply_op("*", args), do: Enum.reduce(args, 1, &*/2)
  defp apply_op("/", [a, b]), do: a / b
  defp apply_op("div", [a, b]), do: div(a, b)
  defp apply_op("mod", [a, b]), do: Integer.mod(a, b)

  # Comparisons
  defp apply_op(">", [a, b]), do: a > b
  defp apply_op("<", [a, b]), do: a < b
  defp apply_op(">=", [a, b]), do: a >= b
  defp apply_op("<=", [a, b]), do: a <= b

  # Catch-all for unimplemented operators
  defp apply_op(op, args) do
    raise "Interpreter error: Unknown operator '#{op}' with args #{inspect(args)}"
  end

  DynamicArityBuilder.define_dynamic_arity_builder(
    :defp,
    :build_interpreted_function,
    128
  )
end
