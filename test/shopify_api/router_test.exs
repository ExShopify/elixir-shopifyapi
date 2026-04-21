defmodule Test.ShopifyAPI.RouterTest do
  use ExUnit.Case

  import Plug.Test
  import ShopifyAPI.Factory

  alias ShopifyAPI.Shop
  alias ShopifyAPI.AppServer
  alias ShopifyAPI.AuthTokenServer
  alias ShopifyAPI.ShopServer
  alias ShopifyAPI.JSONSerializer
  alias ShopifyAPI.Router
  alias ShopifyAPI.Security

  alias Plug.{Conn, Parsers}

  @moduletag :capture_log

  def parse(conn, opts \\ []) do
    opts = Keyword.put_new(opts, :parsers, [Plug.Parsers.URLENCODED, Plug.Parsers.MULTIPART])
    Parsers.call(conn, Parsers.init(opts))
  end

  setup_all do
    app = build(:app)
    AppServer.set(app)

    shop = build(:shop)
    ShopServer.set(shop)
    [app: app, shop: shop]
  end

  describe "/install" do
    test "with a valid app it redirects", %{app: app, shop: shop} do
      conn =
        :get
        |> conn("/install?app=#{app.handle}&shop=#{shop.myshopify_domain}")
        |> parse()
        |> Router.call(%{})

      assert conn.status == 302

      {"location", redirect_uri} =
        Enum.find(conn.resp_headers, fn h -> elem(h, 0) == "location" end)

      assert URI.parse(redirect_uri).host == shop.myshopify_domain
    end
  end

  describe "/authorized" do
    @code "testing"
    @token %{access_token: "test-token"}

    setup _contxt do
      bypass = Bypass.open()
      shop_domain = "localhost:#{bypass.port}"
      shop = %Shop{myshopify_domain: shop_domain}
      ShopServer.set(shop)

      {:ok, %{bypass: bypass, shop_domain: shop_domain}}
    end

    test "fails with invalid hmac", %{app: app, bypass: _bypass, shop_domain: shop_domain} do
      conn =
        :get
        |> conn(
          "/authorized/#{app.handle}?shop=#{shop_domain}&code=#{@code}&timestamp=1234&hmac=invalid"
        )
        |> parse()
        |> Router.call(%{})

      assert conn.status == 404
    end

    test "fetches the token", %{app: app, bypass: bypass, shop_domain: shop_domain} do
      Bypass.expect_once(bypass, "POST", "/admin/oauth/access_token", fn conn ->
        {:ok, body} = JSONSerializer.encode(@token)
        Conn.resp(conn, 200, body)
      end)

      conn =
        :get
        |> conn(
          "/authorized/#{app.handle}?" <>
            add_hmac_to_params(
              app,
              "code=#{@code}&shop=#{shop_domain}&state=#{app.nonce}&timestamp=1234"
            )
        )
        |> parse()
        |> Router.call(%{})

      assert conn.status == 302
      {:ok, %{token: auth_token}} = AuthTokenServer.get(shop_domain, app.handle)
      assert auth_token == @token.access_token
    end

    test "fails without a valid nonce", %{app: app, bypass: _bypass, shop_domain: shop_domain} do
      conn =
        :get
        |> conn(
          "/authorized/invalid-app?" <>
            add_hmac_to_params(
              app,
              "code=#{@code}&shop=#{shop_domain}&state=invalid&timestamp=1234"
            )
        )
        |> parse()
        |> Router.call(%{})

      assert conn.status == 404
    end

    test "fails without a valid shop", %{app: app, bypass: _bypass} do
      conn =
        :get
        |> conn(
          "/authorized/#{app.handle}?" <>
            add_hmac_to_params(
              app,
              "code=#{@code}&shop=invalid-shop&state=#{app.nonce}&timestamp=1234"
            )
        )
        |> parse()
        |> Router.call(%{})

      assert conn.status == 404
    end

    def add_hmac_to_params(app, params) do
      params <> "&hmac=" <> Security.base16_sha256_hmac(params, app.client_secret)
    end
  end
end
