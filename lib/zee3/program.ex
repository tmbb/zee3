defmodule Zee3.Program do
  @moduledoc false

  @arity_0_pid_calls [
    :push,
    :pop
  ]

  @timeout_pid_calls [
    :check_sat,
    :check_sat_and_get_model,
    :check_sat!,
    :check_sat_and_get_model!
  ]

  @doc false
  def do_program(pid, block) do
    # Macro.postwalk traverses the AST from the bottom up.
    transformed_block =
      Macro.postwalk(block, fn
        # 1. State Management
        {pid_call, meta, []} when pid_call in @arity_0_pid_calls ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.unquote(pid_call)(unquote(pid))
          end

        {pid_call, meta, []} when pid_call in @timeout_pid_calls ->
          # Delegate to the correct call
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.unquote(pid_call)(unquote(pid))
          end

        {pid_call, meta, [timeout]} when pid_call in @timeout_pid_calls ->
          # Delegate to the correct call
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.unquote(pid_call)(unquote(pid), unquote(timeout))
          end


        # 2. Declarations - declaring a variable which is not a normal variable
        {:declare_const, meta, [name, type]} ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            name = unquote(name)
            Zee3.Solver.declare_const(
              unquote(pid),
              name,
              Zee3.Smt2.serialize(unquote(type))
            )

            # Return the SMT Symbol so the user can bind it
            %Zee3.Smt2.Symbol{value: name}
          end

        # (Do the exact same name extraction for functions)
        {:declare_fun, meta, [name, args, ret_type]} when is_list(args) ->
          anonymous_function_args =
            for {_, index} <- Enum.with_index(args) do
              Macro.var(:"x_#{index}", __MODULE__)
            end

          # Build the literal AST of an anonymous function
          anonymous_function_ast =
            {:fn, meta,
              [
                {:->, [],
                  [
                    anonymous_function_args,
                    quote do
                      Zee3.Smt2.call(
                        # Add the new function name
                        unquote(name),
                        # Add the argument list
                        unquote(anonymous_function_args)
                      )
                    end
                  ]
                }
              ]
            }

          # Notice the layers of indirection here:
          # we generate a new anonynous function, which, when called,
          # will return an S-expression which represents the act of
          # calling the uninterpreted function we have just created.
          # Before changing anything in this branch, re-read the
          # previous sentence until you understand exactly what
          # is happening.

          quote [line: Keyword.get(meta, :line), location: :keep] do
            name = unquote(name)
            args = unquote(args)
            ret_type = unquote(ret_type)

            Zee3.Solver.declare_fun(
              unquote(pid),
              name,
              Enum.map(args, &Zee3.Smt2.serialize/1),
              Zee3.Smt2.serialize(ret_type)
            )

            # Return an anonymous function the user can bind
            unquote(anonymous_function_ast)
          end

        # 3. Assertions & Optimizations
        # This catches asserts anywhere in the tree!
        {action, meta, [expr]} when action in [:assert, :maximize, :minimize] ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            ast = unquote(expr)
            serialized = Zee3.Smt2.serialize(ast)
            apply(Zee3.Solver, unquote(action), [unquote(pid), serialized])
          end

        # 4. Fallback: Leave all other Elixir code (for, if, assignments) completely untouched!
        other ->
          other
      end)

    # Package everything inside an anonymous function which is called
    # immediately in order to prevent variable names and imports from
    # leaking outside of the program
    quote do
      (
        fn ->
          # Make the default Zee3 functions available and hide
          # the Kernel functions with the same name
          use Zee3.StdLib
          unquote(transformed_block)
        end
      ).()
    end
  end
end
