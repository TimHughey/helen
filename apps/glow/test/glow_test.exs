defmodule GlowTest do
  use ExUnit.Case
  use Carol.AssertAid, module: Glow

  @moduletag glow: true, glow_base: true

  # NOTE: required tests are provided by Carol.AssertAid
end
