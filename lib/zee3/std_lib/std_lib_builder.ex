defmodule Zee3.StdLib.StdLibBuilder do
  @moduledoc false

  defmodule FunctionDefinition do
    @moduledoc false
    defstruct [:function, :arity, :theories, :description]
  end

  @function_blacklist ~w(= => true false)
  @infix_operators ~w(and not < > <= >= + - * /)

  defp rename_problematic("re.++"), do: "re_concat"
  defp rename_problematic("re.*"), do: "re_kleene_star"
  defp rename_problematic("re.+"), do: "re_kleene_plus"
  defp rename_problematic(other), do: other

  # This function is hidden because there is no reason a user
  # would actually call it. This function is just a shorthand
  # to convert the TSV file we've got from asking the Gemini LLM
  # to list all functions in the same place into actual function
  # definitions. There is no reason to expect a user would have
  # a TSV file with function definitions rather than just defining
  # the functions themselves.

  @doc false
  defmacro __build_from_tsv_file__(path) do
    contents = File.read!(path)
    lines = String.split(contents, "\n")

    # All rows including the header
    all_rows =
      Enum.map(lines, fn line ->
        line
        |> String.trim()
        |> String.split("\t")
      end)

    # Remove the header
    rows = Enum.drop(all_rows, 1)

    all_definitions =
      Enum.map(rows, fn row ->
        [function, arity, theory, description] = row

        {arity, ""} = Integer.parse(arity)

        %FunctionDefinition{
          function: function,
          arity: arity,
          theories: [theory],
          description: description
        }
      end)

    grouped_definitions =
      Enum.group_by(all_definitions, fn d ->
        {d.function, d.arity}
      end)

    merged_definitions =
      Enum.map(grouped_definitions, fn {{_, _}, defs} ->
        Enum.reduce(defs, fn def, merged ->
          %{merged | theories: merged.theories ++ [def.theories]}
        end)
      end)

    definitions =
      for definition <- merged_definitions,
          definition.function not in @function_blacklist do
        ast_from_data(definition)
      end

    quote do
      @external_resource unquote(path)
      unquote(definitions)
    end
  end

  defp ast_from_data(definition) do
    arity = definition.arity
    original_function = definition.function

    function =
      original_function
      |> rename_problematic()
      |> String.replace(".", "_")

    function_atom = String.to_atom(function)

    theories_text = Enum.intersperse(definition.theories, ", ")

    docstring = """
      #{definition.description}.

      *Theories*: #{theories_text}.
      """

    case arity do
      0 ->
        quote do
          @doc unquote(docstring)
          def unquote(function_atom)() do
            %Zee3.Smt2.Symbol{value: unquote(original_function)}
          end
        end

      1 ->
        quote do
          # No need to use defzee3, we can prove that everything
          # is converted because we're feeding things through `Zee3.Smt2.call/2`.
          @doc unquote(docstring)
          @spec unquote(function_atom)(Zee3.Smt2.smt2_like()) :: Zee3.Smt2.t()
          def unquote(function_atom)(arg) do
            Zee3.Smt2.call(unquote(original_function), [arg])
          end
        end

      2 ->
        quote do
          # No need to use defzee3, we can prove that everything
          # is converted because we're feeding things through `Zee3.Smt2.call/2`.
          @doc unquote(docstring)
          @spec unquote(function_atom)(
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like()
              ) :: Zee3.Smt2.t()
          def unquote(function_atom)(lhs, rhs) do
            Zee3.Smt2.call(unquote(original_function), [lhs, rhs])
          end
        end

      3 ->
        quote do
          # No need to use defzee3, we can prove that everything
          # is converted because we're feeding things through `Zee3.Smt2.call/2`.
          @doc unquote(docstring)
          @spec unquote(function_atom)(
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like()
              ) :: Zee3.Smt2.t()
          def unquote(function_atom)(a, b, c) do
            Zee3.Smt2.call(unquote(original_function), [a, b, c])
          end
        end

      4 ->
        quote do
          # No need to use defzee3, we can prove that everything
          # is converted because we're feeding things through `Zee3.Smt2.call/2`.
          @doc unquote(docstring)
          @spec unquote(function_atom)(
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like()
              ) :: Zee3.Smt2.t()
          def unquote(function_atom)(a, b, c, d) do
            Zee3.Smt2.call(unquote(original_function), [a, b, c, d])
          end
        end

      -1 ->
        if function in @infix_operators do
          # Whitelist infix operators to keep them binary
          docstring =
            docstring
            |> String.replace(
              " (variadic chain)",
              " (compiles to variadic chain if possible)"
            )
            |> String.replace(
              " (variadic)",
              " (compiles to variadic chain if possible)"
            )

          quote do
            @doc unquote(docstring)
            @spec unquote(function_atom)(
                Zee3.Smt2.smt2_like(),
                Zee3.Smt2.smt2_like()
              ) :: Zee3.Smt2.t()
            def unquote(function_atom)(lhs, rhs) do
              # Convert the arguments manually; no need to overcomplicate
              # the definition by reusing the `zee3_body/2` function.
              lhs = Zee3.Smt2.to_smt2(lhs)
              rhs = Zee3.Smt2.to_smt2(rhs)

              case {lhs, rhs} do
                # Case 1: merge operator chains
                {
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)} |
                      _lhs_args
                    ] = lhs_items
                  },
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)} |
                      rhs_args
                    ]
                  }
                } ->
                  %Zee3.Smt2.List{value: lhs_items ++ rhs_args}

                # Case 2: left hand side is an operator chain; merge the righ hand side
                {
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)} |
                      _lhs_args
                    ] = lhs_items
                  },
                  rhs
                } ->
                  %Zee3.Smt2.List{value: lhs_items ++ [rhs]}

                # Case 3: right hand side is an operator chain; merge the left hand side
                {
                  lhs,
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)} |
                      rhs_args
                    ]
                  },
                } ->
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)},
                      lhs |
                      rhs_args
                    ]
                  }

                # Case 4: no chains to merge
                _other ->
                  %Zee3.Smt2.List{
                    value: [
                      %Zee3.Smt2.Symbol{value: unquote(original_function)},
                      lhs,
                      rhs
                    ]
                  }
              end
            end
          end
        else
          # Make all other variadic functions take a list.
          quote do
            @doc unquote(docstring)
            @spec unquote(function_atom)(list(Zee3.Smt2.smt2_like())) :: Zee3.Smt2.t()
            def unquote(function_atom)(args) do
              # The `Zee3.Smt2.call/2` function will convert our types for us
              Zee3.Smt2.call(unquote(original_function), args)
            end
          end
        end
    end
  end
end
