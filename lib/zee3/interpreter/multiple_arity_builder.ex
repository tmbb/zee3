defmodule Zee3.Interpreter.DynamicArityBuilder do
  @moduledoc false

  defmacro define_dynamic_arity_builder(kind, name, max_arity) when is_integer(max_arity) do
    max_nr_of_digits = ceil(:math.log10(max_arity))

    for i <- 1..max_arity do
      arg_list =
        for j <- 1..i do
          var_suffix = String.pad_leading(to_string(j), max_nr_of_digits, "0")
          Macro.var(:"x_#{var_suffix}", __MODULE__)
        end

      case kind do
        :defp ->
          quote do
            defp unquote(name)(_arity = unquote(i), f) do
              fn unquote_splicing(arg_list) ->
                f.(unquote(arg_list))
              end
            end
          end

        :def ->
          quote do
            def unquote(name)(_arity = unquote(i), f) do
              fn unquote_splicing(arg_list) ->
                f.(unquote(arg_list))
              end
            end
          end
      end
    end
  end
end
