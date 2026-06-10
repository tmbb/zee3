defmodule Zee3.FiniteSetTest do
  use ExUnit.Case, async: true
  require Zee3
  alias Zee3.StdLib.FiniteSet

  setup do
    # Start a fresh Z3 solver for every test
    {:ok, solver} = Zee3.start_solver()

    # Ensure it's shut down when the test exits
    on_exit(fn ->
      if Process.alive?(solver), do: Zee3.stop_solver(solver)
    end)

    %{solver: solver}
  end

  test "declare a set of integers", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s = FiniteSet.declare("s", Sort.int(), max_size: 10)
        assert FiniteSet.contains(s, 1)
        assert FiniteSet.contains(s, 2)
        assert FiniteSet.contains(s, 3)

        assert s.cardinality == 3

        check_sat_and_get_model!()
      end

    {:ok, s} = FiniteSet.extract_from_model(model, "s")

    assert MapSet.equal?(s, MapSet.new([1, 2, 3]))
  end

  test "a set can't contain duplicates", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s = FiniteSet.declare("s", Sort.int(), max_size: 10)
        # Asserting that a set contains an element doesn't
        # in any sense add an element to a data structure.
        # This asserts a mathematical fact, with absolutely
        # no side effects.
        assert FiniteSet.contains(s, 1)
        assert FiniteSet.contains(s, 1)
        assert FiniteSet.contains(s, 1)

        assert s.cardinality == 1

        check_sat_and_get_model!()
      end

    {:ok, s} = FiniteSet.extract_from_model(model, "s")

    assert MapSet.equal?(s, MapSet.new([1]))
  end

  test "sets can be disjoint (satisfiable disjunction)", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s1 = FiniteSet.declare("s1", Sort.int(), max_size: 10)
        s2 = FiniteSet.declare("s2", Sort.int(), max_size: 10)

        assert FiniteSet.contains(s1, 1)
        assert FiniteSet.contains(s1, 2)
        assert FiniteSet.contains(s1, 3)
        assert s1.cardinality == 3

        assert FiniteSet.contains(s2, 4)
        assert FiniteSet.contains(s2, 5)
        assert s2.cardinality == 2

        assert FiniteSet.disjoint(s1, s2)

        check_sat_and_get_model!()
      end

    s1 = FiniteSet.extract_from_model!(model, "s1")
    s2 = FiniteSet.extract_from_model!(model, "s2")

    assert MapSet.equal?(s1, MapSet.new([1, 2, 3]))
    assert MapSet.equal?(s2, MapSet.new([4, 5]))
  end

  test "sets can be disjoint (unsatisfiable disjunction)", %{solver: solver} do
    :unsat =
      Zee3.program solver do
        s1 = FiniteSet.declare("s1", Sort.int(), max_size: 10)
        s2 = FiniteSet.declare("s2", Sort.int(), max_size: 10)

        assert FiniteSet.contains(s1, 1)
        assert FiniteSet.contains(s1, 2)
        assert FiniteSet.contains(s1, 3)
        assert s1.cardinality == 3

        assert FiniteSet.contains(s2, 1)
        assert FiniteSet.contains(s2, 5)
        assert s2.cardinality == 2

        assert FiniteSet.disjoint(s1, s2)

        check_sat_and_get_model!()
      end
  end

  test "declare a set of bit vectors", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s = FiniteSet.declare("s", Sort.bit_vec(8), max_size: 10)
        assert FiniteSet.contains(s, "a")
        assert FiniteSet.contains(s, "b")
        assert FiniteSet.contains(s, "c")
        assert FiniteSet.contains(s, "d")

        assert s.cardinality == 4

        check_sat_and_get_model!()
      end

    {:ok, s} = FiniteSet.extract_from_model(model, "s")

    assert MapSet.equal?(s, MapSet.new(["a", "b", "c", "d"]))
  end

  test "subset relation between integer sets", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s1 = FiniteSet.declare("s1", Sort.int(), max_size: 10)
        s2 = FiniteSet.declare("s2", Sort.int(), max_size: 10)

        assert FiniteSet.contains(s1, 1)
        assert FiniteSet.contains(s1, 2)
        assert FiniteSet.contains(s1, 3)
        assert FiniteSet.contains(s1, 4)
        assert s1.cardinality == 4

        assert FiniteSet.subset_of(s2, s1)
        assert s2.cardinality == 2

        assert not FiniteSet.contains(s2, 3)
        assert not FiniteSet.contains(s2, 2)

        check_sat_and_get_model!()
      end

    s1 = FiniteSet.extract_from_model!(model, "s1")
    s2 = FiniteSet.extract_from_model!(model, "s2")

    assert MapSet.equal?(s1, MapSet.new([1, 2, 3, 4]))
    assert MapSet.equal?(s2, MapSet.new([1, 4]))
  end

  test "superset relation between integer sets", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s1 = FiniteSet.declare("s1", Sort.int(), max_size: 10)
        s2 = FiniteSet.declare("s2", Sort.int(), max_size: 10)

        assert FiniteSet.contains(s1, 11)
        assert FiniteSet.contains(s1, 12)
        assert FiniteSet.contains(s1, 13)
        assert FiniteSet.contains(s1, 14)
        assert FiniteSet.contains(s1, 15)
        assert FiniteSet.contains(s1, 16)
        assert s1.cardinality == 6

        assert not FiniteSet.contains(s2, 11)
        assert not FiniteSet.contains(s2, 12)
        assert s2.cardinality == 4

        assert FiniteSet.superset_of(s1, s2)

        check_sat_and_get_model!()
      end

    s1 = FiniteSet.extract_from_model!(model, "s1")
    s2 = FiniteSet.extract_from_model!(model, "s2")

    assert MapSet.equal?(s1, MapSet.new([11, 12, 13, 14, 15, 16]))
    assert MapSet.equal?(s2, MapSet.new([13, 14, 15, 16]))
  end

  test "equality between sets", %{solver: solver} do
    {:sat, model} =
      Zee3.program solver do
        s1 = FiniteSet.declare("s1", Sort.int(), max_size: 10)
        s2 = FiniteSet.declare("s2", Sort.int(), max_size: 10)

        assert FiniteSet.contains(s1, 11)
        assert FiniteSet.contains(s1, 12)
        assert FiniteSet.contains(s1, 13)
        assert FiniteSet.contains(s1, 14)
        assert FiniteSet.contains(s1, 15)
        assert FiniteSet.contains(s1, 16)
        assert s1.cardinality == 6

        assert FiniteSet.equal(s1, s2)

        check_sat_and_get_model!()
      end

    s1 = FiniteSet.extract_from_model!(model, "s1")
    s2 = FiniteSet.extract_from_model!(model, "s2")

    assert MapSet.equal?(s1, s2)
    assert MapSet.equal?(s1, MapSet.new([11, 12, 13, 14, 15, 16]))
    assert MapSet.equal?(s2, MapSet.new([11, 12, 13, 14, 15, 16]))
  end
end
