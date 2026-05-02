defmodule Zee3.Defzee3.Zee3Def do
  @moduledoc false
  defstruct [:name, :hidden_name, :typed_args, :result_type, :body]

  alias Zee3.Defzee3.TypedArg

  def arg_vars(zee3_call) do
    Enum.map(zee3_call.typed_args, fn typed_arg -> typed_arg.var end)
  end

  def from_ast(call_ast, body_ast) do
    case call_ast do
      {:"::", _m1, [function_call, result_type]} ->
        {f, typed_args_ast} = Macro.decompose_call(function_call)
        f_zee3 = :"_zee3_#{f}"

        typed_args =
          for typed_arg <- typed_args_ast do
            case typed_arg do
              {:"::", _, [{var_name, _, ctx} = var, type]} when is_atom(var_name) and is_atom(ctx) ->
                %TypedArg{
                  var: var,
                  name: to_string(var_name),
                  type: type
                }
            end
          end

        arg_assignments =
          for typed_arg <- typed_args do
            quote do
              unquote(typed_arg.var) = Zee3.Smt2.symbol(unquote(typed_arg.name))
            end
          end

        new_body_ast = {:__block__, [], arg_assignments ++ [body_ast]}

        %__MODULE__{
          name: f,
          hidden_name: f_zee3,
          typed_args: typed_args,
          result_type: result_type,
          body: new_body_ast
        }
    end
  end

  def typed_args_to_smt2(zee3_call) do
    arg_list =
      for typed_arg <- zee3_call.typed_args do
        quote do
          Zee3.Smt2.list([
            Zee3.Smt2.symbol(unquote(typed_arg.name)),
            unquote(typed_arg.type)
          ])
        end
      end

    quote do
      # Don't splice, we want the raw list
      Zee3.Smt2.list(unquote(arg_list))
    end
  end
end
