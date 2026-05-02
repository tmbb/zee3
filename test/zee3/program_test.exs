defmodule Zee3.ProgramTest do
  use ExUnit.Case, async: true
  require Zee3
  alias Zee3.Smt2

  setup do
    # Start a fresh Z3 solver for every test
    {:ok, solver} = Zee3.start_solver()

    # Ensure it's shut down when the test exits
    on_exit(fn ->
      if Process.alive?(solver), do: Zee3.stop_solver(solver)
    end)

    %{solver: solver}
  end

  test "simple program" do
    {:ok, pid} = Zee3.start_solver()

    zero = 0

    {:sat, model} =
      Zee3.program pid do
        # Declare integer constants
        # Note: there is nothing special with the `Sort.int()` function call,
        # the `Sort` module is just the `Zee3.StdLib.Sort` module, which the
        # `Zee3.program` macro aliases inside the body so we can refer to it
        # without needing to alias it ourselves.
        a = declare_const("a", Sort.int())
        b = declare_const("b", Sort.int())

        # Declare a function that takes two integers and returns an integer
        f = declare_fun("f", [Sort.int(), Sort.int()], Sort.int())

        # Assert a constraint (note that Zee3 recognizes literal integers correctly)
        assert f.(a, b) == -5
        # Assert a new constraint, using a variable defined outside of the program
        assert f.(a, b) + f.(b, a) == zero
        # Note: the `assert/2` above is a Z3 assertion, not an ExUnit assertion.

        # Check for satisfiability and get the model if satisfiable
        check_sat_and_get_model!()
      end

    # "normal" assert, taken from ExUnit and unrelated to Z3
    assert model["f"].(model["b"], model["a"]) == 5
    # Note that the `model["f"]` is an actual anonymous function
    # which can be called from Elixir like any other function
    # (of course this function only takes "intersting" values
    # in the values we assert in the program)
  end

  test "solves basic integers and booleans", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        x = declare_const("x", Sort.int())
        y = declare_const("y", Sort.int())
        is_valid = declare_const("is_valid", Sort.bool())

        assert x > 10
        assert y == x + 5
        assert is_valid == true

        check_sat_and_get_model!()
      end

    assert model["is_valid"] == true
    assert model["x"] > 10
    assert model["y"] == model["x"] + 5
  end

  test "handles negative numbers correctly", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        neg_val = declare_const("neg_val", Sort.int())
        assert neg_val == -42

        check_sat_and_get_model!()
      end

    assert model["neg_val"] == -42
  end

  test "handle elixir values defined outside the program", %{solver: solver} do
    elixir_value = 1337

    {:sat, model} =
      Zee3.program solver do
        x = declare_const("x", Sort.int())
        # Seamlessly gets the value from outside of the program
        assert x == elixir_value

        check_sat_and_get_model!()
      end

    assert model["x"] == 1337
  end

  test "handle smt2 values defined outside the program", %{solver: solver} do
    # This is an Smt2 value, not a raw integer
    elixir_value = Smt2.integer(1337)

    {:sat, model} =
      Zee3.program solver do
        x = declare_const("x", Sort.int())
        # Seamlessly gets the value from outside of the program
        assert x == elixir_value

        check_sat_and_get_model!()
      end

    assert model["x"] == 1337
  end

  def my_func(a), do: a + 1

  test "handle normal elixir functions", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        x = declare_const("x", Sort.int())
        # Call a function defined in the current module
        # outside of the program
        assert x == my_func(8)

        check_sat_and_get_model!()
      end

    assert model["x"] == 9
  end

  test "declare uninterpreted functions and get interpretations", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        x = declare_const("x", Sort.int())
        y = declare_const("y", Sort.int())
        f = declare_fun("f", [Sort.int(), Sort.int()], Sort.int())

        # Note that we need to call it as an anonymous function
        assert f.(x, y) == -f.(y, x)
        assert f.(x, y) == 1

        check_sat_and_get_model!()
      end

    assert model["f"].(model["y"], model["x"]) == -1
  end

  test "for loops work inside the program", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        # Dynacmially create a number of variables and store them
        # in a list. In this case, we create 10 variables, with
        # names of the form x_i (for i in 1..10).
        xs =
          for i <- 1..10 do
            # Note that there is nothing special about the first
            # argument of `declare_const/2`, which can be anything
            # that returns a string.
            _x_i = declare_const("x_#{i}", Sort.int())
          end

        # Assert that they sum to 10.
        # Where does the `sum/1` function come from?
        # It's just a function that the `Zee3.StdLib` module defines
        # and imports inside the program. You can easily define your
        # own functions and use them inside the program, as long
        # as the functions return the right format, as documented
        # elsewhere
        assert sum(xs) == 10

        # Assert pairwise comparisons between all the variables.
        # Note: there is actually a built in for this, but we really
        # wanted to show that we can use for loops and normal Elixir
        # functions without any issues
        for {x_i, x_i_plus_1} <- Enum.zip(Enum.drop(xs, 1), xs) do
          assert x_i == x_i_plus_1
        end

        check_sat_and_get_model!()
      end

    # Asert that all variables exist and are set to the only
    # value that satisfies the given constraints
    assert model["x_1"] == 1
    assert model["x_2"] == 1
    assert model["x_3"] == 1
    assert model["x_4"] == 1
    assert model["x_5"] == 1
    assert model["x_6"] == 1
    assert model["x_7"] == 1
    assert model["x_8"] == 1
    assert model["x_9"] == 1
    assert model["x_10"] == 1
  end

  test "forgets constraints and variables whe popped", %{solver: solver} do
    # We want to check for the satisfiability of two different
    # constraint systems using the `push()` and `pop()` functions
    # to add and remove new constraints.
    #
    # Because we have two different satisfiability results,
    # we need to return the result of *two different*
    # `check_sat_and_get_model!()`.
    #
    # This is absolutely not a problem, because the `Zee3.program`
    # respects Elixir's semantics around variable assignment and
    # we can simply assign the results to variables, or save them
    # in a map, or whatevet, and simply return the results at the end.
    {result_1, result_2} =
      Zee3.program solver do
        a = declare_const("a", Sort.int())
        assert a > 0
        # Create a new context here
        push()
        temp_b = declare_const("temp_b", Sort.int())
        assert temp_b == a
        assert temp_b < 0

        # This variable is not made available outside the program,
        # we will need to return it as part of the last expression.
        result_1 = check_sat_and_get_model!()

        # Pop the context that defined the `temp_b` variable
        pop()

        # As above, the variable is not made available outside
        # the program
        result_2 = check_sat_and_get_model!()

        # Return the two results
        {result_1, result_2}
      end

    # Refers to the new context
    assert :unsat == result_1
    # Refers to the original context
    assert {:sat, model} = result_2
    assert model["a"] > 0
    refute Map.has_key?(model, "temp_b")
  end

  test "check sat without a model", %{solver: solver} do
    result =
      Zee3.program solver do
        a = declare_const("a", Sort.int())
        b = declare_const("b", Sort.int())
        c = declare_const("c", Sort.int())

        assert a > 0
        assert b > 0
        assert c > 0

        assert a*a + b*b == c*c

        check_sat!()
      end

    assert result == :sat
  end
end
