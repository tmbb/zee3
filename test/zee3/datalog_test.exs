defmodule Zee3.DatalogTest do
  use ExUnit.Case, async: true
  require Zee3

  # Test the functionality which is specific to the Datalog example

  setup do
    # Start a fresh Z3 solver for every test
    {:ok, solver} = Zee3.start_solver()

    # Ensure it's shut down when the test exits
    on_exit(fn ->
      if Process.alive?(solver), do: Zee3.stop_solver(solver)
    end)

    %{solver: solver}
  end

  describe "transitive closure of graphs" do
    # The following examples all return the the transitive closure
    # of a directed graph, which is the lsit of all pairs of vertices
    # that are conneced by a path.

    @doc """
    Generates a random directed graph using the Erdős–Rényi G(n, p) model.

    ## Parameters
      * `n` - The number of vertices (nodes) in the graph.
      * `p` - The probability (0.0 to 1.0) of a directed edge existing between any two nodes.
      * `opts` - Optional keyword list. Supports `[self_loops: true]`.

    ## Examples

        iex> RandomGraph.erdos_renyi(100, 0.05)
        #Graph<type: directed, vertices: 100, edges: ~500>
    """
    def erdos_renyi(n, p, opts \\ []) when n > 0 and p >= 0.0 and p <= 1.0 do
      allow_self_loops = Keyword.get(opts, :self_loops, false)

      # 1. Initialize an empty graph and ensure all vertices exist.
      # Note: Graph.new() creates a directed graph by default in libgraph.
      graph = Graph.add_vertices(Graph.new(), Enum.to_list(1..n))

      # 2. Iterate through all possible ordered pairs of vertices.
      # :rand.uniform() generates a float X where 0.0 < X <= 1.0
      edges =
        for u <- 1..n,
            v <- 1..n,
            allow_self_loops or u != v,
            :rand.uniform() <= p do
          {u, v}
        end

      # 3. Bulk insert the generated edges back into the graph.
      Graph.add_edges(graph, edges)
    end

    test "simplest program", %{solver: pid} do
      {:ok, {:sat, solutions}} =
        Zee3.program pid do
          # Make sure the relations between entities declare entities
          # with the right sort from the standard library.
          edge = declare_rel("edge", [Sort.entity_id(), Sort.entity_id()])
          path = declare_rel("path", [Sort.entity_id(), Sort.entity_id()])
          # Declare variables, which, again, will use the correct sort.
          a = declare_var("a", Sort.entity_id())
          b = declare_var("b", Sort.entity_id())
          c = declare_var("c", Sort.entity_id())

          # Transitive closure definition
          rule(path.(a, b) <- edge.(a, b))
          rule(path.(a, c) <- path.(a, b) and path.(b, c))

          rule(edge.(entity_id(1), entity_id(2)))
          rule(edge.(entity_id(1), entity_id(3)))
          rule(edge.(entity_id(2), entity_id(4)))

          query("path")
        end

      # Z3 may return the tuples in any order so we sort them
      assert Enum.sort(solutions) == [{1, 2}, {1, 3}, {1, 4}, {2, 4}]
    end

    test "simple program with string entities", %{solver: pid} do
      {:ok, {:sat, solutions}} =
        Zee3.program pid do
          # Make sure the relations between entities declare entities
          # with the right sort from the standard library.
          edge = declare_rel("edge", [Sort.entity_id(), Sort.entity_id()])
          path = declare_rel("path", [Sort.entity_id(), Sort.entity_id()])
          # Declare variables, which, again, will use the correct sort.
          a = declare_var("a", Sort.entity_id())
          b = declare_var("b", Sort.entity_id())
          c = declare_var("c", Sort.entity_id())

          # Transitive closure definition
          rule(path.(a, b) <- edge.(a, b))
          rule(path.(a, c) <- path.(a, b) and path.(b, c))

          rule(edge.(entity_id("alice"), entity_id("bob")))
          rule(edge.(entity_id("alice"), entity_id("charlie")))
          rule(edge.(entity_id("bob"), entity_id("dan")))

          query("path")
        end

      # Z3 may return the tuples in any order so we sort them
      assert Enum.sort(solutions) == [
        {"alice", "bob"},
        {"alice", "charlie"},
        {"alice", "dan"},
        {"bob", "dan"}
      ]
    end

    test "moderately sized inputs (large graph, weakly connected)", %{solver: pid} do
      # Weakly connected graph
      g = erdos_renyi(300, 0.01)

      {:ok, {:sat, solutions}} =
        Zee3.program pid do
          # Make sure the relations between entities declare entities
          # with the right sort from the standard library.
          edge = declare_rel("edge", [Sort.entity_id(), Sort.entity_id()])
          path = declare_rel("path", [Sort.entity_id(), Sort.entity_id()])
          # Declare variables, which, again, will use the correct sort.
          a = declare_var("a", Sort.entity_id())
          b = declare_var("b", Sort.entity_id())
          c = declare_var("c", Sort.entity_id())

          # Transitive closure definition
          rule(path.(a, b) <- edge.(a, b))
          rule(path.(a, c) <- path.(a, b) and path.(b, c))

          for e <- Graph.edges(g) do
            rule(edge.(entity_id(e.v1), entity_id(e.v2)))
          end

          query("path")
        end


      # Use an independent implementation (i.g. libgraph) to check that
      # the vertices are actually part of the transitive closure.
      # NOTE: this only proves that we found a subset of the transitive
      # closure, not that we found all edges in the transitive closure,
      # but it's enough for now.
      reachability =
        Enum.group_by(
          solutions,
          fn {v1, _v2} -> v1 end,
          fn {_v1, v2} -> v2 end
        )

      for {v1, zee3_reachable_from_v1} <- reachability do
        # We have defined reachability as not including the vertex itself
        libgraph_reachable_from_v1 = Graph.reachable_neighbors(g, [v1])
        assert Enum.sort(zee3_reachable_from_v1) == Enum.sort(libgraph_reachable_from_v1)
      end
    end
  end
end
