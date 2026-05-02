defmodule Zee3.Solver do
  @moduledoc false
  use GenServer

  alias Zee3.Smt2
  alias Zee3.Solver.Scope

  defstruct port: nil,
            caller: nil,
            buffer: "",
            scopes: [Scope.empty()]

  # --- Client API ---

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [])
  end

  def declare_const(pid, name, type_string) when is_binary(type_string) do
    GenServer.call(pid, {:declare_const, name, type_string})
  end

  def declare_fun(pid, name, param_types, return_type) do
    GenServer.call(pid, {:declare_fun, name, param_types, return_type})
  end

  def assert(pid, constraint) do
    GenServer.cast(pid, {:send, "(assert #{constraint})"})
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

  def check_sat_and_get_model(pid, timeout \\ :infinity) do
    GenServer.call(pid, :check_sat_and_get_model, timeout)
  end

  def check_sat_and_get_model!(pid, timeout \\ :infinity) do
    case check_sat_and_get_model(pid, timeout) do
      {:ok, result} ->
        result

      # TODO: add the error branch
    end
  end

  def check_sat(pid, timeout \\ :infinity) do
    GenServer.call(pid, :check_sat, timeout)
  end

  def check_sat!(pid, timeout \\ :infinity) do
    case check_sat(pid, timeout) do
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
  def send_raw(pid, input) do
    GenServer.call(pid, {:send_raw, input})
  end

  @impl true
  def handle_call({:send_raw, input}, _from, state) do
    # Send the raw text and don't mutate the text
    Port.command(state.port, [input, "\n"])
    {:reply, :ok, state}
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
  def handle_call({:declare_const, name, type}, _from, state) do
    Port.command(state.port, "(declare-const #{name} #{type})\n")

    # Prepend the new variable to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, :ok, %{state | scopes: new_scopes}}
  end

  @impl true
  def handle_call({:declare_fun, name, params, ret_type}, _from, state) do
    joined_params = Enum.join(params, " ")
    Port.command(state.port, "(declare-fun #{name} (#{joined_params}) #{ret_type})\n")

    # Prepend the new function to the current (head) scope
    [current_scope | older_scopes] = state.scopes
    new_scopes = [Scope.put_var(current_scope, name) | older_scopes]

    {:reply, :ok, %{state | scopes: new_scopes}}
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
end
