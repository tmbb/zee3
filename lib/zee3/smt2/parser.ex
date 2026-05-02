defmodule Zee3.Smt2.Parser do
  @moduledoc """
  A NimbleParsec implementation for parsing SMT-LIB2 S-Expressions.

  This is exposed as a public module, although most users will not
  want to parse any S-expressions directly.
  This module is used internally to parse the values returned by
  the solver.
  """
  import NimbleParsec
  alias Zee3.Smt2

  # --- Lexical Rules ---

  ignore_ws = ignore(repeat(ascii_char([?\s, ?\t, ?\n, ?\r])))

  # 1. Strings: SMT-LIB2 strings are in double quotes, with "" acting as an escaped quote
  string_char =
    choice([
      string("\"\"") |> replace(?"),
      utf8_char(not: ?")
    ])

  string_node =
    ignore(string("\""))
    |> repeat(string_char)
    |> ignore(string("\""))
    |> reduce({__MODULE__, :build_string, []})

  # 2. Quoted Symbols: Variables wrapped in | ... |
  quoted_symbol =
    ignore(string("|"))
    |> repeat(utf8_char(not: ?|))
    |> ignore(string("|"))
    |> reduce({__MODULE__, :build_symbol, []})

  # 3. BitVectors: Formatted as #x... (hex) or #b... (binary)
  hex_bv =
    ignore(string("#x"))
    |> times(ascii_char([?0..?9, ?a..?f, ?A..?F]), min: 1)
    |> reduce({__MODULE__, :build_hex_bitvec, []})

  bin_bv =
    ignore(string("#b"))
    |> times(ascii_char([?0..?1]), min: 1)
    |> reduce({__MODULE__, :build_bin_bitvec, []})

  # 4. Standard Symbols & Integers: Any continuous chunk of non-whitespace/non-paren chars
  sym_char = utf8_char(not: ?\s, not: ?\t, not: ?\n, not: ?\r, not: ?(, not: ?))

  sym_or_int =
    times(sym_char, min: 1)
    |> reduce({__MODULE__, :build_sym_or_int, []})

  # 5. Lists: Parentheses containing zero or more S-Expressions
  list_node =
    ignore(string("("))
    |> repeat(ignore_ws |> parsec(:sexpr))
    |> concat(ignore_ws)
    |> ignore(string(")"))
    |> reduce({__MODULE__, :build_list, []})

  # --- Main Combinators ---

  # The core recursive choice. It attempts to match nodes in order of specificity.
  defcombinator(
    :sexpr,
    choice([
      list_node,
      string_node,
      quoted_symbol,
      hex_bv,
      bin_bv,
      sym_or_int
    ])
  )

  # Entry points with padding whitespace removed
  defparsec(:parse_single, ignore_ws |> parsec(:sexpr) |> concat(ignore_ws))
  defparsec(:parse_multiple, repeat(ignore_ws |> parsec(:sexpr)) |> concat(ignore_ws))

  # --- AST Reducers ---

  def build_string(chars), do: %Smt2.String{value: List.to_string(chars)}
  def build_symbol(chars), do: %Smt2.Symbol{value: List.to_string(chars)}
  def build_list(elements), do: %Smt2.List{value: elements}

  # Convert hex characters directly into an Elixir bitstring
  def build_hex_bitvec(chars) do
    # Each hex digit represents exactly 4 bits
    bit_size = length(chars) * 4
    int_value = List.to_string(chars) |> String.to_integer(16)

    %Smt2.BitVec{value: <<int_value::size(bit_size)>>}
  end

  # Convert binary characters directly into an Elixir bitstring
  def build_bin_bitvec(chars) do
    # Each binary digit represents exactly 1 bit
    bit_size = length(chars)
    int_value = List.to_string(chars) |> String.to_integer(2)

    %Smt2.BitVec{value: <<int_value::size(bit_size)>>}
  end

  def build_sym_or_int(chars) do
    str = List.to_string(chars)

    case Integer.parse(str) do
      # Ensure the entire token was consumed as an integer
      {int, ""} -> %Smt2.Int{value: int}
      _ -> %Smt2.Symbol{value: str}
    end
  end

  # --- Public API ---

  @doc """
  Parses exactly one S-Expression from the given binary.
  """
  def parse(binary) do
    case parse_single(binary) do
      {:ok, [node], _rest, _, _, _} ->
        node

      {:error, reason, rest, _, line, col} ->
        raise "Parse error at line #{line}, col #{col}: #{reason}. Remaining: #{rest}"
    end
  end

  @doc """
  Parses multiple S-Expressions from the given binary, skipping any whitespace.
  """
  def parse_many(binary) do
    case parse_multiple(binary) do
      {:ok, nodes, _rest, _, _, _} ->
        nodes

      {:error, reason, rest, _, line, col} ->
        raise "Parse error at line #{line}, col #{col}: #{reason}. Remaining: #{rest}"
    end
  end
end
