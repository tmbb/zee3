defmodule Zee3.Smt2 do
  alias Zee3.Smt2
  alias Zee3.Smt2.Serializer

  @type t() :: Smt2.Int.t() |
               Smt2.Real.t() |
               Smt2.Symbol.t() |
               Smt2.String.t() |
               Smt2.BitVec.t() |
               Smt2.List.t()

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

  @spec call(binary(), list(smt2_like())) :: t()
  def call(name, args) when is_binary(name) do
    list([symbol(name) | args])
  end

  @spec list(list(smt2_like())) :: t()
  def list(value) when is_list(value),
    do: %Smt2.List{value: Enum.map(value, &to_smt2/1)}

  @spec integer(integer()) :: t()
  def integer(value) when is_integer(value),
    do: %Smt2.Int{value: value}

  @spec symbol(binary()) :: t()
  def symbol(value) when is_binary(value),
    do: %Smt2.Symbol{value: value}

  @spec string(binary()) :: t()
  def string(value) when is_binary(value),
    do: %Smt2.String{value: value}

  @spec bit_vec(bitstring()) :: t()
  def bit_vec(value) when is_bitstring(value),
    do: %Smt2.BitVec{value: value}

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

  def to_smt2(x),
    do: raise("Can't convert #{inspect(x)} into an `Zee3.Smt2` value")

  @spec bit_vec_from_integer(non_neg_integer(), pos_integer()) :: t()
  def bit_vec_from_integer(integer, length) when integer > 0 do
    value = <<integer :: size(length)>>
    %Smt2.BitVec{value: value}
  end

  @spec bit_vec16_from_integer(non_neg_integer()) :: t()
  def bit_vec16_from_integer(integer) when integer > 0 do
    value = <<integer :: size(16)>>
    %Smt2.BitVec{value: value}
  end

  @spec bit_vec32_from_integer(non_neg_integer()) :: t()
  def bit_vec32_from_integer(integer) when integer > 0 do
    value = <<integer :: size(32)>>
    %Smt2.BitVec{value: value}
  end

  @spec bit_vec64_from_integer(non_neg_integer()) :: t()
  def bit_vec64_from_integer(integer) when integer > 0 do
    value = <<integer :: size(64)>>
    %Smt2.BitVec{value: value}
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
