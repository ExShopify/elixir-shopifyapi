defmodule ShopifyAPI.JWTSessionToken do
  @doc """
  Handles validation, data fetching, and exchange for Shopify Session Tokens.

  [Shopify documentation](https://shopify.dev/docs/apps/build/authentication-authorization/session-tokens/set-up-session-tokens)
  """
  require Logger

  @spec verify(String.t(), String.t()) ::
          {valid? :: boolean(), jwt :: JOSE.JWT.t(), jws :: JOSE.JWS.t()}
  def verify(token, client_secret) do
    jwk = JOSE.JWK.from_oct(client_secret)
    JOSE.JWT.verify_strict(jwk, ["HS256"], token)
  end

  @spec app(JOSE.JWT.t() | String.t()) :: {:ok, ShopifyAPI.App.t()} | {:error, any()}
  def app(%JOSE.JWT{fields: %{"aud" => client_id}}) do
    case ShopifyAPI.AppServer.get_by_client_id(client_id) do
      {:ok, _} = resp -> resp
      _ -> {:error, "Audience claim is not a valid App clientId."}
    end
  end

  def app(token) when is_binary(token), do: token |> JOSE.JWT.peek_payload() |> app()

  @doc """
  Extracts the shop name from the "dest" claim in the JWT. The "dest" claim may contain either a
  full URL (e.g., "https://example.myshopify.com") or just the shop name (e.g., "example.myshopify.com").
  """
  @spec myshopify_domain(JOSE.JWT.t()) :: {:ok, String.t()} | {:error, any()}
  def myshopify_domain(%JOSE.JWT{fields: %{"dest" => shop_url}}) do
    myshopify_domain =
      shop_url
      |> String.trim_leading("https://")
      |> String.trim_leading("http://")
      |> String.split("/")
      |> List.first()

    {:ok, myshopify_domain}
  end

  def myshopify_domain(_), do: {:error, "Invalid user token or shop name not found"}

  @spec user_id(JOSE.JWT.t()) :: {:ok, integer()} | {:error, any()}
  def user_id(%JOSE.JWT{fields: %{"sub" => user_id}}),
    do: {:ok, String.to_integer(user_id)}

  def user_id(_),
    do: {:error, "Invalid user token or no id"}

  @spec get_offline_token(JOSE.JWT.t(), String.t()) ::
          {:ok, ShopifyAPI.AuthToken.t()}
          | {:error, :invalid_session_token}
          | {:error, :failed_fetching_online_token}
  def get_offline_token(%JOSE.JWT{} = jwt, token) do
    with {:ok, myshopify_domain} <- myshopify_domain(jwt),
         {:ok, app} <- app(jwt) do
      case ShopifyAPI.AuthTokenServer.get(myshopify_domain, app.handle) do
        {:ok, _} = resp ->
          resp

        {:error, _} ->
          Logger.warning("No token found, exchanging for new")
          request_offline_token(app, myshopify_domain, token)
      end
    else
      error ->
        Logger.warning("failed getting required informatio from the JWT #{inspect(error)}")
        {:error, :invalid_session_token}
    end
  end

  @spec get_user_token(JOSE.JWT.t(), String.t()) ::
          {:ok, ShopifyAPI.UserToken.t()}
          | {:error, :invalid_session_token}
          | {:error, :failed_fetching_online_token}
  def get_user_token(%JOSE.JWT{} = jwt, token) do
    with {:ok, myshopify_domain} <- myshopify_domain(jwt),
         {:ok, app} <- app(jwt),
         {:ok, user_id} <- user_id(jwt) do
      case ShopifyAPI.UserTokenServer.get_valid(myshopify_domain, app.handle, user_id) do
        {:ok, _} = resp ->
          resp

        {:error, :invalid_user_token} ->
          Logger.debug("Expired or no user token found, exchanging for new")
          request_online_token(app, myshopify_domain, token)
      end
    else
      error ->
        Logger.warning("failed getting required informatio from the JWT #{inspect(error)}")
        {:error, :invalid_session_token}
    end
  end

  defp request_offline_token(app, myshopify_domain, token) do
    case ShopifyAPI.AuthRequest.request_offline_access_token(app, myshopify_domain, token) do
      {:ok, token} ->
        fire_post_login_hook(token)
        {:ok, token}

      error ->
        error
    end
  end

  defp request_online_token(app, myshopify_domain, token) do
    case ShopifyAPI.AuthRequest.request_online_access_token(app, myshopify_domain, token) do
      {:ok, token} ->
        fire_post_login_hook(token)
        {:ok, token}

      error ->
        error
    end
  end

  defp fire_post_login_hook(user_token),
    do: Task.async(fn -> ShopifyAPI.Shop.post_login(user_token) end)
end
