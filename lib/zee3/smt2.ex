defmodule Zee3.Smt2 do
  alias Zee3.Smt2
  alias Zee3.Smt2.Serializer

  @typedoc """
  An `Smt2` value, which can be serialized and sent to Z3.
  """
  @type t() :: Smt2.Int.t() |
               Smt2.Real.t() |
               Smt2.Symbol.t() |
               Smt2.String.t() |
               Smt2.BitVec.t() |
               Smt2.List.t()

  @typedoc """
  A value which is either an `Smt2` value or a literal
  that can be unambiguously be converted into an `Smt2`
  value.
  """
  @type smt2_like() :: t() |
                       integer() |
                       boolean() |
                       list() |
                       bitstring()

  defguard is_smt2(e) when
    is_struct(e, Smt2.Int) or
    is_struct(e, Smt2.Real) or
    is_struct(e, Smt2.Symbol) or
    is_struct(e, Smt2.String) or
    is_struct(e, Smt2.BitVec) or
    is_struct(e, Smt2.List)

  @doc """
  An `Smt2` function call. If some of the arguments
  of the function call are literals, they are
  converted into `Smt2` values.
  """
  @spec call(binary(), list(smt2_like())) :: t()
  def call(name, args) when is_binary(name) do
    list([symbol(name) | args])
  end

  @doc """
  An `Smt2` list. If some of the arguments
  of the list literals, they are
  converted into `Smt2` values.
  """
  @spec list(list(smt2_like())) :: t()
  def list(value) when is_list(value),
    do: %Smt2.List{value: Enum.map(value, &to_smt2/1)}

  @doc """
  An `Smt2` integer.
  """
  @spec integer(integer()) :: t()
  def integer(value) when is_integer(value),
    do: %Smt2.Int{value: value}

  @doc """
  An `Smt2` symbol.
  """
  @spec symbol(binary()) :: t()
  def symbol(value) when is_binary(value),
    do: %Smt2.Symbol{value: value}

  @doc """
  An `Smt2` string.
  """
  @spec string(binary()) :: t()
  def string(value) when is_binary(value),
    do: %Smt2.String{value: value}

  @doc """
  An `Smt2` bit vector.
  """
  @spec bit_vec(bitstring()) :: t()
  def bit_vec(value) when is_bitstring(value),
    do: %Smt2.BitVec{value: value}

  @doc """
  Convert a literal into a `Smt2` value.
  If the value is already an `Smt2` value it is unchanged.
  """
  @spec to_smt2(smt2_like()) :: t()
  def to_smt2(bool) when is_boolean(bool) do
    symbol(to_string(bool))
  end

  def to_smt2(x) when is_integer(x),
    do: integer(x)

  def to_smt2(x) when is_bitstring(x),
    do: bit_vec(x)

  def to_smt2(x) when is_list(x),
    do: list(x)

  def to_smt2(x) when is_struct(x, Smt2.List) do
    %Smt2.List{
      value: Enum.map(x.value, &to_smt2/1)
    }
  end

  def to_smt2(x) when is_smt2(x), do: x

  def to_smt2(x) do
    raise "Can't convert #{inspect(x)} into an `Zee3.Smt2` value"
  end

  @doc """
  Encode an integer as a bit vector with a given length.
  """
  @spec bit_vec_from_integer(non_neg_integer(), pos_integer()) :: t()
  def bit_vec_from_integer(integer, length) when integer > 0 do
    value = <<integer :: size(length)>>
    %Smt2.BitVec{value: value}
  end

  @doc """
  Encode an integer as a bit vector with 16 bits.
  """
  @spec bit_vec16_from_integer(non_neg_integer()) :: t()
  def bit_vec16_from_integer(integer) when integer > 0 do
    value = <<integer :: size(16)>>
    %Smt2.BitVec{value: value}
  end

  @doc """
  Encode an integer as a bit vector with 32 bits.
  """
  @spec bit_vec32_from_integer(non_neg_integer()) :: t()
  def bit_vec32_from_integer(integer) when integer > 0 do
    value = <<integer :: size(32)>>
    %Smt2.BitVec{value: value}
  end

  @doc """
  Encode an integer as a bit vector with 64 bits.
  """
  @spec bit_vec64_from_integer(non_neg_integer()) :: t()
  def bit_vec64_from_integer(integer) when integer > 0 do
    value = <<integer :: size(64)>>
    %Smt2.BitVec{value: value}
  end

  @doc """
  Create a `Smt2` value from a formula in Elixir code.

  The code inside this macro call is converted the following way:

  * The macro calls `use Zee3.StdLib` before creating the AST,
    which means elixir functions will be interpreted as if they were
    in a `Zee3.program/2` macro body.
  * Elixir variables (`a`, `b`, ...) are converted into symbols

  ## Examples

      iex(1)> require Zee3.Smt2, as: Smt2
      Zee3.Smt2

      iex(2)> Smt2.from_ex(a)
      #Zee3.Smt2.Symbol<a>

      iex(3)> Smt2.from_ex(a + b)
      #Zee3.Smt2.List<(+ a b)>

      iex(4)> Smt2.from_ex(x or y or z)
      #Zee3.Smt2.List<(or x y z)>

      iex(5)> Smt2.from_ex(x <- a and b and c)
      #Zee3.Smt2.List<(=> (and a b c) x)>
  """
  defmacro from_ex(ast) do
    from_ex_ast(ast)
  end

  def from_ex_ast(ast) do
    mutated_ast =
      Macro.postwalk(ast, fn ast_node ->
        case ast_node do
          {var, _meta, ctx} when is_atom(ctx) ->
            quote do
              Zee3.Smt2.symbol(unquote(to_string(var)))
            end

          other ->
            other
        end
      end)

    quote do
      (
        fn ->
          use Zee3.StdLib
          unquote(mutated_ast)
        end
      ).()
    end
  end

  def serialize(x) do
    x |> to_smt2() |> Serializer.serialize()
  end

  def serialize_multiple(nodes) do
    nodes
    |> Enum.map(&serialize/1)
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end
end
