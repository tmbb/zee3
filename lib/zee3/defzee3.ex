defmodule Zee3.Defzee3 do
  alias Zee3.Defzee3.Zee3Def

  @doc """
  Defines an elixir function which seamlessly converts
  all arguments into `t:Zee3.Smt2.t/0` types.

  This function is mostly useful if you want to combine
  custom functions rather than building the return value
  of the function manually with the `Zee3.Smt2` functions.

  If you are not using other functions and are instead building
  the result out of `Zee3.Smt2` values, you won't need this
  function because the `Zee3.Smt2.call/2` function will escape
  the arguments correctly.

  ## Example

      defzee f(x, y) do
        x*x*y + (1 - x)*y*y
      end
  """
  defmacro defzee3(call, do: body) do
    zee3_def = Zee3Def.from_ast(call, body)
    arg_vars = Zee3Def.arg_vars(zee3_def)
    arg_count = length(arg_vars)
    # qualified_name = "#{inspect(__CALLER__.module)}.#{zee3_def.name}"
    typed_args_smt2 = Zee3Def.typed_args_to_smt2(zee3_def)

    quote do
      def unquote(zee3_def.name)(unquote_splicing(arg_vars)) do
        Zee3.Smt2.call(
          "#{@__zee3_function_prefix__}.#{unquote(zee3_def.name)}",
          # We want the actual list of arguments (i.e. not a spliced list)
          unquote(arg_vars)
        )
      end

      def unquote(zee3_def.hidden_name)() do
        # This "result" is the result of expanding the function body,
        # in Smt2 format according to the body of the original function.
        # Variables will evaluate to symbols.
        result = unquote(zee3_def.body)

        Zee3.Smt2.call(
          "define-fun",
          [
            Zee3.Smt2.symbol(
              "#{@__zee3_function_prefix__}.#{unquote(zee3_def.name)}"
            ),
            unquote(typed_args_smt2),
            unquote(zee3_def.result_type),
            result
          ]
        )
      end

      Module.put_attribute(
        __MODULE__,
        :__zee3_defs__,
        {
          {unquote(zee3_def.name), unquote(arg_count)},
          unquote(zee3_def.hidden_name)
        }
      )
    end
  end

  defmacro __using__(opts \\ []) do
    caller_module = __CALLER__.module
    function_prefix = Keyword.get(opts, :prefix, inspect(caller_module))

    quote do
      import Zee3.Defzee3, only: [defzee3: 2]

      @__zee3_function_prefix__ unquote(function_prefix)

      Module.register_attribute(
        unquote(caller_module),
        :__zee3_defs__,
        accumulate: true
      )

      @before_compile Zee3.Defzee3

      defmacro __use_zee3__() do
        # Function defined by the @before_compile hook
        smt2_terms =
          for {{_fun, _arity}, hidden_fun} <- __zee3_defs__() do
            apply(__MODULE__, hidden_fun, [])
          end

        serialized = Enum.map(smt2_terms, fn term ->
          [Zee3.Smt2.serialize(term), "\n"] end
        )

        quote do
          unquote(serialized)
        end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __zee3_defs__() do
        @__zee3_defs__
      end
    end
  end
end
