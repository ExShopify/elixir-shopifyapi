defmodule ShopifyAPI.AppServer do
  @moduledoc """
  Write-through cache for App structs.
  """

  use GenServer

  alias ShopifyAPI.App
  alias ShopifyAPI.Config

  @table __MODULE__
  @name __MODULE__
  @single_app_install Application.compile_env(:shopify_api, :app_server, :single_app) ==
                        :single_app || true

  if @single_app_install do
    @spec set(App.t()) :: :ok
    def set(%App{} = app) do
      # Put the app in as both the default app and under its handle for easy retrieval.
      ets_set(:app, app)
      ets_set(app.handle, app)
    end

    @spec get(String.t()) :: {:ok, App.t()} | :error
    @spec get(atom()) :: {:ok, App.t()} | :error
    def get(_handle \\ :app)
    def get(:app), do: ets_get(:app)
    def get(handle), do: ets_get(handle)

    def mode, do: :single_app
  else
    @spec set(App.t()) :: :ok
    def set(%App{handle: handle} = app), do: ets_set(handle, app)

    @spec get(String.t()) :: {:ok, App.t()} | :error
    @spec get(atom()) :: {:ok, App.t()} | :error
    def get(handle), do: ets_get(handle)

    def mode, do: :multi_app
  end

  def all, do: @table |> :ets.tab2list() |> Map.new()

  @spec count() :: integer()
  def count, do: :ets.info(@table, :size)

  defp ets_set(handle, %App{} = app) when is_atom(handle) or is_binary(handle) do
    :ets.insert(@table, {handle, app})
    do_persist(app)
    :ok
  end

  def ets_get(handle) when is_atom(handle) or is_binary(handle) do
    case :ets.lookup(@table, handle) do
      [{^handle, app}] -> {:ok, app}
      [] -> :error
    end
  end

  @doc """
  Retrieves an App by its client_id, if more then one App has the same client_id, one of them will be
  returned but it is not guaranteed which one.
  """
  @spec get_by_client_id(String.t()) :: {:ok, App.t()} | :error
  def get_by_client_id(client_id) when is_binary(client_id) do
    case :ets.match_object(@table, {:_, %{client_id: client_id}}) do
      [{_, app}] -> {:ok, app}
      [{_, app} | _] -> {:ok, app}
      [] -> :error
    end
  end

  ## GenServer Callbacks

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)

  @impl GenServer
  def init(:ok) do
    create_table!()
    for %App{} = app <- do_initialize(), do: set(app)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:app, app}, state), do: {:noreply, Map.put(state, :app, app)}

  @impl GenServer
  def handle_call(:app, _from, %{app: app} = state), do: {:reply, {:ok, app}, state}
  def handle_call(:app, _from, state), do: {:reply, :error, state}

  defp create_table! do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])
  end

  # Calls a configured initializer to obtain a list of Apps.
  defp do_initialize do
    case Config.lookup(__MODULE__, :initializer) do
      {module, function, args} -> apply(module, function, args)
      {module, function} -> apply(module, function, [])
      _ -> []
    end
  end

  # Attempts to persist a App if a persistence callback is configured
  defp do_persist(%App{handle: handle} = app) do
    case Config.lookup(__MODULE__, :persistence) do
      {module, function, args} -> apply(module, function, [handle, app | args])
      {module, function} -> apply(module, function, [handle, app])
      _ -> nil
    end
  end
end
