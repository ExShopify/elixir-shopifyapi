defmodule ShopifyAPI.AuthToken do
  @derive {Jason.Encoder,
           only: [:code, :app_handle, :myshopify_domain, :token, :timestamp, :plus]}
  defstruct code: "",
            app_handle: "",
            myshopify_domain: "",
            token: "",
            timestamp: 0,
            plus: false

  @typedoc """
      Type that represents a Shopify Auth Token with

        - app_handle corresponding to %ShopifyAPI.App{handle: app_handle}
        - myshopify_domain corresponding to %ShopifyAPI.Shop{myshopify_domain: myshopify_domain}
  """
  @type t :: %__MODULE__{
          code: String.t(),
          app_handle: String.t(),
          myshopify_domain: String.t(),
          token: String.t(),
          timestamp: 0,
          plus: boolean()
        }
  @type ok_t :: {:ok, t()}

  alias ShopifyAPI.App

  @spec create_key(t()) :: String.t()
  def create_key(%__MODULE__{myshopify_domain: myshopify_domain, app_handle: app_handle}),
    do: create_key(myshopify_domain, app_handle)

  @spec create_key(String.t(), String.t()) :: String.t()
  def create_key(myshopify_domain, app_handle), do: "#{myshopify_domain}:#{app_handle}"

  @spec new(App.t(), String.t(), String.t(), String.t()) :: t()
  def new(%App{} = app, myshopify_domain, auth_code, token) do
    %__MODULE__{
      app_handle: app.handle,
      myshopify_domain: myshopify_domain,
      code: auth_code,
      token: token
    }
  end

  @spec from_auth_request(App.t(), String.t(), String.t(), map()) :: t()
  def from_auth_request(%App{} = app, myshopify_domain, code \\ "", attrs),
    do: new(app, myshopify_domain, code, attrs["access_token"])
end

defimpl ShopifyAPI.Scope, for: ShopifyAPI.AuthToken do
  def shop(auth_token) do
    case ShopifyAPI.ShopServer.get(auth_token.myshopify_domain) do
      {:ok, shop} ->
        shop

      _ ->
        raise "Failed to find Shop for Scope out of AuthToken #{auth_token.myshopify_domain} in ShopServer"
    end
  end

  def app(auth_token) do
    case ShopifyAPI.AppServer.get(auth_token.app_handle) do
      {:ok, app} ->
        app

      _ ->
        raise "Failed to find App for Scope out of AuthToken #{auth_token.app_handle} in AppServer"
    end
  end

  def auth_token(auth_token), do: auth_token

  def user_token(_auth_token), do: nil
end
