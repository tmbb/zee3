defmodule Zee3.Smt2.Serializer do
  @moduledoc false

  # The `serialize/1` function is made available
  # through the `Zee3.Smt2` module, making it unnecessary
  # to use this module.

  alias Zee3.Smt2

  @doc """
  Recursively serializes an Smt2 struct into a valid S-Expression string.
  """
  def serialize(%Smt2.List{value: nodes}) do
    "(#{Enum.map_join(nodes, " ", &serialize/1)})"
  end

  def serialize(%Smt2.Symbol{value: value}) do
    # Wrap symbols containing whitespace or parentheses in SMT-LIB2 pipes
    if String.contains?(value, [" ", "\t", "\n", "\r", "(", ")", "|"]) do
      "|#{value}|"
    else
      value
    end
  end

  def serialize(%Smt2.String{value: value}) do
    # SMT-LIB2 escapes double quotes by doubling them
    escaped = String.replace(value, "\"", "\"\"")
    "\"#{escaped}\""
  end

  def serialize(%Smt2.Int{value: value}) do
    to_string(value)
  end

  def serialize(%Smt2.BitVec{value: bitstring}) do
    if is_binary(bitstring) do
      # If it's a clean multiple of 8 bits, hex is much more compact and readable
      "#x" <> Base.encode16(bitstring, case: :lower)
    else
      # If it's an arbitrary bit-length, fall back to binary formatting
      bits = for <<bit::1 <- bitstring>>, do: to_string(bit)
      "#b" <> Enum.join(bits)
    end
  end
end

# Implement the Inspect protocol across all AST types simultaneously
defimpl Inspect,
  for: [
    Zee3.Smt2.List,
    Zee3.Smt2.Symbol,
    Zee3.Smt2.String,
    Zee3.Smt2.Int,
    Zee3.Smt2.BitVec
  ] do
  alias Zee3.Smt2

  def inspect(node, _opts) do
    # Extract the module name (e.g., "Smt2.List") from the struct
    type_name =
      node.__struct__
      |> Module.split()
      |> Enum.join(".")

    # Format as: #Smt2.Type<serialized_string>
    "##{type_name}<#{Smt2.Serializer.serialize(node)}>"
  end
end
