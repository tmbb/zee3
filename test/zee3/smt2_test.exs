defmodule Zee3.Smt2Test do
  use ExUnit.Case, async: true
  require Zee3.Smt2, as: Smt2

  test "Smt2 symbol from elixir identifier" do
    assert Smt2.from_ex(a) == Smt2.symbol("a")
    assert Smt2.from_ex(b) == Smt2.symbol("b")
    assert Smt2.from_ex(word) == Smt2.symbol("word")
    assert Smt2.from_ex(word_with_dashes) == Smt2.symbol("word_with_dashes")
  end

  test "Smt2 function calls from elixir call" do
    assert Smt2.from_ex(x + y) ==
      Smt2.call("+", [
        Smt2.symbol("x"),
        Smt2.symbol("y")
      ])

    assert Smt2.from_ex(x <- a and b and c) ==
      Smt2.call("=>", [
        Smt2.call("and", [
          Smt2.symbol("a"),
          Smt2.symbol("b"),
          Smt2.symbol("c")
        ]),
        Smt2.symbol("x")
      ])
  end
end
