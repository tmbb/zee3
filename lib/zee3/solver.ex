defmodule Zee3.Solver do
  @moduledoc """
  API to send commands to the solver.

  The `Zee3.program/2` macro can do anything the funcions
  in this module can do, but sometimes, when we're using
  the solver interactively and performing complex algorithms
  outside the solver, using this lower level functions is clearer.
  """

  use GenServer

  alias Zee3.Smt2
  alias Zee3.Solver.Scope

  defstruct port: nil,
            caller: nil,
            buffer: "",
            next_entity_id: 0,
            entity_to_id: %{},
            id_to_entity: %{},
            scopes: [Scope.empty()]

  # --- Client API ---

  @doc """
  Start a Zee3 solver process.
  """
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Declare an uninterpreted constant.
  """
  def declare_const(pid, name, type) do
    GenServer.call(pid, {:declare_const, name, type})
  end

  @doc """
  Declare an uninterpreted sort.
  """
  def declare_sort(pid, name) when is_binary(name) do
    GenServer.call(pid, {:declare_sort, name})
  end

  @doc """
  Declare an uninterpreted function.
  """
  def declare_fun(pid, name, param_types, return_type) do
    GenServer.call(pid, {:declare_fun, name, param_types, return_type})
  end

  @doc """
  Declare a datalog relation.
  """
  def declare_rel(pid, name, param_types) do
    GenServer.call(pid, {:declare_rel, name, param_types})
  end


  @doc """
  Declare a variable for use in datalog rules.
  """
  def declare_var(pid, name, type) do
    GenServer.call(pid, {:declare_var, name, type})
  end

  @doc """
  Define a new datalog rule.
  """
  def rule(pid, body) do
    GenServer.call(pid, {:rule, body})
  end

  def query(pid, name, opts \\ []) do
    timeout = timeout_from_opts(opts)
    GenServer.call(pid, {:query, name}, timeout)
  end

  def query!(pid, name, opts \\ []) do
    case query(pid, name, opts) do
      {:ok, result} ->
        result

      # TODO: add error branch
    end
  end

  def assert(pid, constraint) do
    serialized_constraint = Smt2.serialize(constraint)
    GenServer.cast(pid, {:send, "(assert #{serialized_constraint})"})
  end

  def entity_id(pid, value) do
    GenServer.call(pid, {:entity_id, value})
  end

  @doc """
  Pushes a new scope onto the solver stack.
  """
  def push(pid) do
    GenServer.call(pid, :push)
  end

  @doc """
  Pops the current scope from the solver stack, discarding all assertions
  and variables declared since the last `push`.
  """
  def pop(pid) do
    GenServer.call(pid, :pop)
  end

  @doc """
  Check the Z3 program for satisfiability and returns the model.
  """
  def check_sat_and_get_model(pid, opts \\ []) do
    timeout = timeout_from_opts(opts)
    GenServer.call(pid, :check_sat_and_get_model, timeout)
  end

  @doc """
  Check the Z3 program for satisfiability and returns the model.
  Raises on error.
  """
  def check_sat_and_get_model!(pid, opts \\ []) do
    case check_sat_and_get_model(pid, opts) do
      {:ok, result} ->
        result

      # TODO: add the error branch
    end
  end

  @doc """
  Check the Z3 program for satisfiability.
  """
  def check_sat(pid, opts \\ []) do
    timeout = timeout_from_opts(opts)
    GenServer.call(pid, :check_sat, timeout)
  end

  @doc """
  Check the Z3 program for satisfiability. Raises on error.
  """
  def check_sat!(pid, opts \\ []) do
    case check_sat(pid, opts) do
      {:ok, result} ->
        result

      # TODO: add the error branch
    end
  end

  @doc """
  Check the Z3 program for satisfiability assuming a number
  of assumptions.
  """
  def check_sat_assuming(pid, assumptions, opts \\ []) do
    timeout = timeout_from_opts(opts)
    GenServer.call(pid, {:check_sat_assuming, assumptions}, timeout)
  end

  @doc """
  Check the Z3 program for satisfiability assuming a number
  of assumptions.
  """
  def check_sat_assuming!(pid, assumptions, opts \\ []) do
    case check_sat_assuming(pid, assumptions, opts) do
      {:ok, result} ->
        result

      # TODO: add the error branch
    end
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_) do
    executable = find_z3_executable()

    unless executable do
      raise "Could not find the Z3 executable." <>
        "Ensure it is downloaded or in your system PATH."
    end

    port =
      Port.open({:spawn_executable, System.find_executable(executable)}, [
        :binary,
        :use_stdio,
        args: ["-in", "-smt2"]
      ])

    {:ok, %__MODULE__{port: port}}
  end

  defp find_z3_executable do
    # 1. Check user config in config.exs
    config_path = Application.get_env(:zee3, :z3_executable)

    # 2. Check the automatically downloaded binary in priv/bin
    executable_name =
      if match?({:win32, _}, :os.type()) do
        "z3.exe"
      else
        "z3"
      end

    priv_path =
      case :code.priv_dir(:zee3) do
        {:error, :bad_name} -> Path.join("priv", "bin")
        dir -> Path.join([dir, "bin", executable_name])
      end

    cond do
      is_binary(config_path) and File.exists?(config_path) ->
        config_path

      File.exists?(priv_path) ->
        priv_path

      system_path = System.find_executable(executable_name) ->
        system_path

      true ->
        nil
    end
  end

  @doc """
  Declares a datatype in Z3 and registers its constructors
  with the Elixir atom registry.
  """
  def declare_datatypes(pid, smt_declaration, constructor_atoms)
      when is_list(constructor_atoms) do
    GenServer.call(pid, {:declare_datatypes, smt_declaration, constructor_atoms})
  end

  @doc """
  Send raw SMT-LIB2 text (given as `t:iodata/0`) to the solver.
  Constants and functions defined inside this text aren't available
  in the model.

  If you need these values to be available, use the `declare-const/2`
  and `declare-fun/3` functions explicitly.
  """
  def eval_smt2_code(pid, input) do
    GenServer.call(pid, {:eval_smt2_code, input})
  end

  @impl true
  def handle_call({:declare_datatypes, smt_declaration, constructor_atoms}, _from, state) do
    Port.command(state.port, smt_declaration <> "\n")

    # Convert Elixir atoms to strings for the internal registry
    constructor_strings = Enum.map(constructor_atoms, &to_string/1)

    [current_scope | older_scopes] = state.scopes

    updated_scope = %{
      current_scope
      | constructors:
          MapSet.union(
            current_scope.constructors,
            MapSet.new(constructor_strings)
          )
    }

    {:reply, :ok, %{state | scopes: [updated_scope | older_scopes]}}
  end

  @impl true
  def handle_call({:entity_id, value}, _from, state) do
    case Map.fetch(state.entity_to_id, value) do
      :error ->
        current_bit_vec_id = raw_bit_vec32_from_integer(state.next_entity_id)
        next_id = state.next_entity_id + 1
        # Add the new entity_id to the list of mapped entity_to_id
        new_entity_to_id = Map.put(state.entity_to_id, value, current_bit_vec_id)
        new_id_to_entity = Map.put(state.id_to_entity, current_bit_vec_id, value)
        # Update the state with the new entity_id
        new_state = %{
          state |
          next_entity_id: next_id,
          entity_to_id: new_entity_to_id,
          id_to_entity: new_id_to_entity
        }

        {:reply, Smt2.bit_vec(current_bit_vec_id), new_state}

      {:ok, entity_id} ->
        {:reply, Smt2.bit_vec(entity_id), state}
    end
  end

  @impl true
  def handle_call({:declare_const, name, type}, _from, state) do
    smt2_code =
      Smt2.call("declare-const", [Smt2.symbol(name), type])
      |> Smt2.serialize()

    Port.command(state.port, smt2_code)

    # Prepend the new variable to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, :ok, %{state | scopes: new_scopes}}
  end

  def handle_call({:declare_sort, name}, _from, state) do
    smt2_code =
      Smt2.call("declare-fun", [Smt2.symbol(name)])
      |> Smt2.serialize()

    Port.command(state.port, smt2_code)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:declare_fun, name, params, ret_type}, _from, state) do
    smt2_code =
      Smt2.call("declare-fun", [Smt2.symbol(name), Smt2.list(params), ret_type])
      |> Smt2.serialize()

    Port.command(state.port, smt2_code)

    # Prepend the new function to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, :ok, %{state | scopes: new_scopes}}
  end

  @impl true
  def handle_call({:declare_rel, name, params}, _from, state) do
    smt2_code =
      Smt2.call("declare-rel", [Smt2.symbol(name), Smt2.list(params)])
      |> Smt2.serialize()

    Port.command(state.port, smt2_code)

    # Prepend the new function to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, :ok, %{state | scopes: new_scopes}}
  end

  @impl true
  def handle_call({:declare_var, name, type}, _from, state) do
    smt2_code =
      Smt2.call("declare-var", [Smt2.symbol(name), type])
      |> Smt2.serialize()

    Port.command(state.port, smt2_code)

    # Prepend the new function to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, Smt2.symbol(name), %{state | scopes: new_scopes}}
  end

  @impl true
  def handle_call({:rule, body}, _from, state) do
    smt2_code = Smt2.call("rule", [body]) |> Smt2.serialize()
    Port.command(state.port, [smt2_code, "\n"])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:push, _from, state) do
    Port.command(state.port, "(push)\n")

    # Push a new, empty scope onto the top of the stack
    {:reply, :ok, %{state | scopes: [Scope.empty() | state.scopes]}}
  end

  @impl true
  def handle_call(:pop, _from, state) do
    case state.scopes do
      # Prevent popping if we are at the global root scope
      [_global_scope] ->
        {:reply, {:error, :cannot_pop_global_scope}, state}

      # Drop the head scope, revert to the older scopes
      [_dropped_scope | older_scopes] ->
        Port.command(state.port, "(pop)\n")
        {:reply, :ok, %{state | scopes: older_scopes}}
    end
  end

  @impl true
  def handle_call({:eval_smt2_code, smt2_code}, from, state) do
    payload = """
    (echo "#{start_marker("eval_smt2_code")}")
    #{smt2_code}
    (echo "#{end_marker()}")
    """

    Port.command(state.port, payload)

    {:noreply,
     %{
       state
       | caller: from,
         buffer: ""
     }}
  end

  @impl true
  def handle_call(:check_sat_and_get_model, from, state) do
    # Flatten the stack for both variables and constructors
    _active_variables = Enum.flat_map(state.scopes, & &1.vars)

    _active_constructors =
      state.scopes
      |> Enum.map(& &1.constructors)
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    payload = """
    (echo "#{start_marker("check_sat_and_get_model")}")
    (check-sat)
    (get-model)
    (echo "#{end_marker()}")
    """

    Port.command(state.port, payload)

    {:noreply,
     %{
       state
       | caller: from,
         buffer: ""
     }}
  end

  @impl true
  def handle_call({:query, name}, from, state) do
    payload = """
      (echo "#{start_marker("query")}")
      (query #{name} :print-answer true)
      (echo "#{end_marker()}")
      """

    Port.command(state.port, payload)

    {:noreply,
     %{
       state
       | caller: from,
         buffer: ""
     }}
  end

  @impl true
  def handle_call(:check_sat, from, state) do
    # Flatten the stack for both variables and constructors
    _active_variables = Enum.flat_map(state.scopes, & &1.vars)

    _active_constructors =
      state.scopes
      |> Enum.map(& &1.constructors)
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    payload = """
    (echo "#{start_marker("check_sat")}")
    (check-sat)
    (echo "#{end_marker()}")
    """

    Port.command(state.port, payload)

    {:noreply,
     %{
       state
       | caller: from,
         buffer: ""
     }}
  end

  @impl true
  def handle_call({:check_sat_assuming, assumptions}, from, state) do
    terms =
      assumptions
      |> Enum.map(&Smt2.serialize/1)
      |> Enum.intersperse(" ")

    payload = """
    (echo "#{start_marker("check_sat_assuming")}")
    (check-sat-assuming (#{terms}))
    (echo "#{end_marker()}")
    """

    Port.command(state.port, payload)

    {:noreply,
     %{
       state
       | caller: from,
         buffer: ""
     }}
  end

  @impl true
  def handle_cast({:send, command}, state) do
    Port.command(state.port, command <> "\n")
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:data, data}}, %{caller: caller} = state) when not is_nil(caller) do
    new_buffer = state.buffer <> data

    if String.contains?(new_buffer, "#{end_marker()}\n") do
      # Get the S-expressions from the output
      ast_nodes = Smt2.Parser.parse_many(new_buffer)
      # Get the response tag so we can route the response
      # to the right response builder
      [%Smt2.Symbol{value: marker} | rest_nodes] = ast_nodes
      tag = tag_from_start_marker(marker)
      # Drop the last node, which is just a dummy
      useful_nodes = Enum.drop(rest_nodes, -1)
      # Build the response according to the tag
      response = build_response(tag, useful_nodes, state)

      GenServer.reply(caller, response)

      {:noreply, %{state | caller: nil, buffer: ""}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    if state.caller do
      GenServer.reply(state.caller, {:error, {:z3_crashed, status}})
    end

    {:stop, :normal, state}
  end

  # --- Internal Output Builder ---

  defp build_response("eval_smt2_code", useful_nodes, _state) do
    has_errors? =
      Enum.any?(useful_nodes, fn smt2_node ->
        case smt2_node do
          %Smt2.List{value: [%Smt2.Symbol{value: "error"} | _args]} ->
            true

          _other ->
            false
        end
      end)

    if has_errors? do
      {:error, useful_nodes}
    else
      {:ok, useful_nodes}
    end
  end

  defp build_response("query", useful_nodes, state) do
    errors =
      Enum.filter(useful_nodes, fn smt2_node ->
        case smt2_node do
          %Smt2.List{value: [%Smt2.Symbol{value: "error"} | _args]} ->
            true

          _other ->
            false
        end
      end)

    if errors != [] do
      serialized =
        errors
        |> Enum.map(&Smt2.serialize/1)
        |> Enum.intersperse("\n")

      raise "Zee3 error:\n\n#{serialized}"
    end

    [%Smt2.Symbol{value: satisfiability} | nodes] = useful_nodes

    case {satisfiability, nodes} do
      {"unsat", _} ->
        {:ok, :unsat}

      {"unknown", _} ->
        {:ok, :unknown}

      {"sat", rest} ->
        solutions =
          case rest do
            # Multiple solutions, linked by a multi-arity disjunction
            [%Smt2.List{value: [%Smt2.Symbol{value: "or"} | args]}] ->
              args

            # Single solution - no disjunction!
            [other] ->
              [other]
          end

        tuples = datalog_get_tuples(state, solutions)

        {:ok, {:sat, tuples}}
    end
  end

  defp build_response("check_sat_and_get_model", useful_nodes, state) do
    [%Smt2.Symbol{value: satisfiability} | nodes] = useful_nodes

    case {satisfiability, nodes} do
      {"unsat", _} ->
        {:ok, :unsat}

      {"unknown", _} ->
        {:ok, :unknown}

      {"sat", [%Smt2.List{value: declarations} | _]} ->
        # We must pass the currently active variables to zip correctly
        active_variables = Scope.vars_from_scopes(state.scopes)
        active_constructors = Scope.constructors_from_scopes(state.scopes)

        # 1. Convert all declarations into an Elixir map
        model_map =
          Enum.reduce(declarations, %{}, fn decl, acc ->
            extract_declaration(decl, active_constructors, acc)
          end)

        # 2. Filter the map to only include variables from our currently active scopes
        final_model = Map.take(model_map, active_variables)

        {:ok, {:sat, final_model}}
    end
  end

  defp build_response("check_sat", useful_nodes, _state) do
    [%Smt2.Symbol{value: satisfiability} | _nodes] = useful_nodes

    case satisfiability do
      "unsat" ->
        {:ok, :unsat}

      "unknown" ->
        {:ok, :unknown}

      "sat" ->
        {:ok, :sat}
    end
  end

  defp build_response("check_sat_assuming", useful_nodes, _state) do
    [%Smt2.Symbol{value: satisfiability} | _nodes] = useful_nodes

    case satisfiability do
      "unsat" ->
        {:ok, :unsat}

      "unknown" ->
        {:ok, :unknown}

      "sat" ->
        {:ok, :sat}
    end
  end

  # --- Declaration Extractors ---

  # Match Constants: (define-fun name () Type Body)
  defp extract_declaration(
         %Smt2.List{
           value: [
             %Smt2.Symbol{value: "define-fun"},
             %Smt2.Symbol{value: name},
             # Empty parameters = constant
             %Smt2.List{value: []},
             _return_type,
             body
           ]
         },
         constructors,
         acc
       ) do
    Map.put(acc, name, Zee3.Interpreter.to_elixir(body, constructors))
  end

  # Match Functions: (define-fun name ((arg Type) ...) Type Body)
  defp extract_declaration(
         %Smt2.List{
           value: [
             %Smt2.Symbol{value: "define-fun"},
             %Smt2.Symbol{value: name},
             # Has parameters = function
             %Smt2.List{} = params,
             _return_type,
             body
           ]
         },
         constructors,
         acc
       ) do
    # We dynamically rewrite the `define-fun` into a `lambda` AST
    # so our Lisp-1 Interpreter can compile it exactly as it did before!
    lambda_ast = %Smt2.List{
      value: [
        %Smt2.Symbol{value: "lambda"},
        params,
        body
      ]
    }

    Map.put(acc, name, Zee3.Interpreter.to_elixir(lambda_ast, constructors))
  end

  # Ignore other internal Z3 macro declarations
  defp extract_declaration(_other, _constructors, acc), do: acc

  defp start_marker(name), do: "!!!ZEE3-RESPONSE-START-#{name}"
  defp end_marker(), do: "!!!ZEE3-RESPONSE-END"

  # This function is the inverse of `start_marker(name)`
  defp tag_from_start_marker("!!!ZEE3-RESPONSE-START-" <> name), do: name

  def raw_bit_vec32_from_integer(integer) do
    <<integer::32>>
  end

  # ==================================================
  # Datalog utilities
  # ==================================================

  def datalog_get_tuples(state, solutions) do
    # Get the tuples for all the solutions.
    # At this point, we can assume there is at least one solution,
    # because we have checked for satisfiability before

    rel_args =
      for solution <- solutions do
        args = parse_solution_into_rel_args(solution)
        for arg <- args do
          Map.fetch!(state.id_to_entity, arg)
        end
      end

    # Turn the list of list into a list of tuples,
    # which is usually easier to work with.
    Enum.map(rel_args, &List.to_tuple/1)
  end

  def parse_solution_into_rel_args(solution) do
    # Although this doesn't seem to be documented anywhere,
    # the Z3 datalog engine returns solutions in a somwhat
    # standardized format, in the form of logical expressions.
    #
    # If there are multiple solutions, it will return a disjunction
    # of conjunctions, although both the disjunction and the conjunctions
    # may be omitted if they aren't needed.
    # The disjunction is omitted if there is only a single solution,
    # and the conjunctions are omited if the relation has arity 1.
    case solution do
      # If there are more thatn one solution, the solutions will
      # be grouped with a multi-arity conjunctions.
      # We must then deconstruct the conjunction.
      %Smt2.List{value: [%Smt2.Symbol{value: "and"} | assignments]} ->
        for {assignment, index} <- Enum.with_index(assignments, 0) do
          # Deconstruct the assignment
          %Smt2.List{value: [%Smt2.Symbol{value: "="}, arg, value]} = assignment
          # Ensure the format is what we expect
          %Smt2.List{value: [%Smt2.Symbol{value: ":var"}, %Smt2.Int{value: ^index}]} = arg
          # Get the raw bits for the entity
          %Smt2.BitVec{value: bits} = value

          bits
        end

      # If there is only one solution, it is not grouped by a
      # conjunction; instead it has a single equality.
      %Smt2.List{value: [%Smt2.Symbol{value: "="}, arg, value]} ->
        # Ensure the format is what we expect
        %Smt2.List{value: [%Smt2.Symbol{value: ":var"}, %Smt2.Int{value: 0}]} = arg
        # Get the raw bits for the entity
        %Smt2.BitVec{value: bits} = value
        [bits]
    end
  end

  defp timeout_from_opts(opts) do
    Keyword.get(opts, :timeout, :infinity)
  end
end
