defmodule EnvironmentTest do
  @moduledoc false

  use ExUnit.Case, async: false

  use HelenTest

  @moduletag :env

  setup do
    :ok
  end

  test "can get Mqtt.Inbound env" do
    env = Application.get_all_env(:helen)

    # IO.puts(inspect(env, pretty: true))

    assert Keyword.has_key?(env, Mqtt.Inbound)
  end
end
