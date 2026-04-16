defmodule ShopifyAPI.Bulk.TelemetryTest do
  use ExUnit.Case
  import ShopifyAPI.Factory
  alias ShopifyAPI.Bulk.Telemetry

  @module "module"
  @bulk_op_id "gid//test"

  setup do
    [auth_token: build(:auth_token)]
  end

  describe "Telemetry send/4" do
    test "when bulk op is succesful", %{auth_token: token} do
      assert :ok == Telemetry.send(@module, token, {:success, :test})
    end

    test "when bulk op errors", %{auth_token: token} do
      assert :ok == Telemetry.send(@module, token, {:error, :test, "error"}, @bulk_op_id)
    end
  end
end
