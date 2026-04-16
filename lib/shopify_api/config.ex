defmodule ShopifyAPI.Config do
  @single_app_install Application.compile_env(:shopify_api, :app_server, :single_app) ==
                        :single_app || true

  @moduledoc false
  def lookup(key), do: Application.get_env(:shopify_api, key)
  def lookup(key, subkey), do: Application.get_env(:shopify_api, key)[subkey]

  if @single_app_install do
    @spec app_handle() :: String.t() | nil
    @spec app_handle(Plug.Conn.t(), keyword()) :: String.t() | nil
    def app_handle do
      case app() do
        %ShopifyAPI.App{handle: handle} -> handle
        nil -> nil
      end
    end

    def app_handle(_conn, opts \\ [])
    def app_handle(_conn, []), do: app_handle()
    def app_handle(_conn, opts), do: Keyword.get(opts, :app_handle) || app_handle()

    @spec app() :: ShopifyAPI.App.t() | nil
    def app do
      case ShopifyAPI.AppServer.get() do
        {:ok, app} -> app
        :error -> nil
      end
    end
  else
    @spec app_handle() :: String.t() | nil
    @spec app_handle(Plug.Conn.t(), keyword()) :: String.t() | nil
    def app_handle, do: lookup(:app_handle)

    def app_handle(%Plug.Conn{path_info: path_info}, opts \\ []) do
      Keyword.get(opts, :app_handle) || app_handle() || List.last(path_info)
    end

    @spec app() :: ShopifyAPI.App.t() | nil
    def app do
      with app_handle when is_binary(app_handle) <- app_handle() do
        ShopifyAPI.AppServer.get(app_handle)
      end
    end
  end
end
