defmodule Zee3.Program do
  @moduledoc false

  @arity_0_pid_calls [
    :push,
    :pop
  ]

  @pid_calls_with_opts [
    :check_sat,
    :check_sat!,
    :check_sat_and_get_model,
    :check_sat_and_get_model!,
    :query,
    :query!
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

        {pid_call, meta, []} when pid_call in @pid_calls_with_opts ->
          # Delegate to the correct call
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.unquote(pid_call)(unquote(pid))
          end

        {pid_call, meta, [opts]} when pid_call in @pid_calls_with_opts ->
          # Delegate to the correct call
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.unquote(pid_call)(unquote(pid), unquote(opts))
          end

        {:use, meta, [module, [with_alias: module_alias]]} ->
          # If the use macro doesn't have a single `:with_alias` option
          # it is not transformed and is instead interpreted as a real
          # use macro by the Macro expander.
          quote [line: Keyword.get(meta, :line), location: :keep] do
            require unquote(module), as: unquote(module_alias)
            raw_smt2_code = unquote(module_alias).__use_zee3__()
            Zee3.Solver.eval_smt2_code(unquote(pid), raw_smt2_code)
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

        # Declare a datalog relation
        {:declare_rel, meta, [name, args]} when is_list(args) ->
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

            Zee3.Solver.declare_rel(
              unquote(pid),
              name,
              Enum.map(args, &Zee3.Smt2.serialize/1)
            )

            # Return an anonymous function the user can bind
            unquote(anonymous_function_ast)
          end

        {:declare_var, meta, [name, type]} ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            name = unquote(name)
            type = Zee3.Smt2.serialize(unquote(type))
            Zee3.Solver.declare_var(unquote(pid), name, type)
            # Return the name of the variable so we can bind it to something
            Zee3.Smt2.symbol(name)
          end

        {:entity_id, meta, [value]} ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            # Return the entity ID, but use side effects to add the ID to the list
            Zee3.Solver.entity_id(unquote(pid), unquote(value))
          end

        {:eval_smt2_code, meta, [code]} ->
          quote [line: Keyword.get(meta, :line), location: :keep] do
            Zee3.Solver.eval_smt2_code(unquote(pid), unquote(code))
          end

        # 3. Assertions, optimizations and rules
        # This catches asserts anywhere in the tree!
        {action, meta, [expr]} when action in [:assert, :maximize, :minimize, :rule] ->
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
    # leaking outside of the Zee3 program and into the wider Elixir scope.
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
