defmodule SallyPwmBasicTest do
  @moduledoc false

  ##
  ## Test of basic Device and Alias creation via TestSupport
  ##

  use ExUnit.Case
  use Should

  @device_ident_default "basic"
  @device_host_default "sally.test-basic"
  @defaults [device_opts: [host: @device_host_default, ident: @device_ident_default]]

  @moduletag pwm_basic: true, defaults: @defaults

  alias Sally.PulseWidth.DB.{Alias, Device}
  alias Sally.PulseWidth.TestSupport, as: TS

  setup_all ctx do
    ctx
  end

  setup [:setup_init]

  @tag alias_opts: [name: "Basic Device and Alias", pio: 0, description: "db basic", ttl_ms: 50]
  test "can PulseWidth create a Device and Alias", ctx do
    txn_res =
      SallyRepo.transaction(fn ->
        SallyRepo.checkout(fn ->
          ctx = TS.ensure_device(ctx)
          should_be_schema(ctx.ts.device, Device)

          ctx = TS.create_alias(ctx)
          should_be_schema(ctx.ts.dev_alias, Alias)
        end)
      end)

    fail = pretty("txn failed", txn_res)
    assert elem(txn_res, 0) == :ok, fail
  end

  defp setup_init(ctx) do
    TS.init(ctx)
  end
end
