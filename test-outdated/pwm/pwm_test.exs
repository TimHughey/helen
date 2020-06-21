defmodule PulseWidthTest do
  @moduledoc false

  use ExUnit.Case, async: true

  # import ExUnit.CaptureLog

  alias TimeSupport
  import HelenTest, only: [base_ext: 2, num_str: 1]

  setup do
    :ok
  end

  @moduletag :pwm

  @duty_max 8191

  setup_all do
    new_pwm = 0..11

    for p <- new_pwm, do: pwm_msg(pwm_id: p) |> PulseWidth.external_update()

    :ok
  end

  test "can create a PulseWidth duty command" do
    alias PulseWidth.Payload.Duty

    pwm = PulseWidth.names() |> hd() |> PulseWidth.find()

    assert %PulseWidth{} = pwm

    cmd = Duty.create_cmd(pwm, Ecto.UUID.generate(), duty: 1924)

    assert is_map(cmd)

    %{pwm_cmd: type, duty: duty, refid: refid} = cmd

    assert type == 0x10
    assert duty == 1924
    assert is_binary(refid)
  end

  test "can create a PulseWidth sequence command" do
    alias PulseWidth.Payload.Sequence

    pwm = PulseWidth.names() |> hd() |> PulseWidth.find()

    assert %PulseWidth{} = pwm

    cmd = Sequence.create_cmd(pwm, Ecto.UUID.generate(), %{name: "test"}, [])

    assert is_map(cmd)

    %{pwm_cmd: type, refid: refid, seq: seq} = cmd

    assert type == 0x20
    assert is_map(seq)
    assert is_binary(refid)
  end

  test "can add a PulseWidthCmd to an existing PulseWidth" do
    pwm = PulseWidth.find_by_device(device(1, 1))

    {rc, pwm} = PulseWidth.add_cmd(pwm, TimeSupport.utc_now())

    assert rc == :ok
    assert %PulseWidth{} = pwm
    assert Ecto.assoc_loaded?(pwm.cmds)
    assert length(pwm.cmds)
    assert is_binary(hd(pwm.cmds) |> Map.get(:refid))
  end

  test "can set the duty of a PulseWidth" do
    device = device(2, 1)

    PulseWidth.duty(device, duty: :rand.uniform(@duty_max))

    assert true
  end

  test "can specify a percentage for duty" do
    device = device(3, 1)

    PulseWidth.duty(device, duty: 0.5)

    assert true
  end

  test "the truth will set you free" do
    assert true
  end

  def device(pwm_num, pin_num),
    do:
      IO.iodata_to_binary([
        "pwm/",
        "pwm-rem",
        num_str(pwm_num),
        ".pin",
        Integer.to_string(pin_num)
      ])

  def pwm_msg(opts \\ []) when is_list(opts) do
    pwm_id = Keyword.get(opts, :pwm_id, 0)
    pin_num = Keyword.get(opts, :pin, 1)
    duty_min = Keyword.get(opts, :duty_min, 0)
    duty_max = Keyword.get(opts, :duty_max, @duty_max)
    duty = :rand.uniform(@duty_max)
    device = Keyword.get(opts, :device, device(pwm_id, pin_num))

    Map.merge(base_ext("pwm-remote", pwm_id), %{
      async: true,
      type: "pwm",
      duty: duty,
      duty_min: duty_min,
      duty_max: duty_max,
      device: device
    })
  end
end