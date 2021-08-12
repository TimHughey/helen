defmodule Lights.ControlMap do
  @moduledoc false

  defmacro is_valid?(ctrl_map) do
    quote do
      case unquote(ctrl_map) do
        %{invalid: _} -> false
        %{device: dev} when dev in [:missing, :not_found] -> false
        %{start: %{invalid: _x}} -> false
        %{finish: %{invalid: _x}} -> false
        _x -> true
      end
    end
  end

  # entry point for creating all control maps
  # (1 of 3) has defined cmds
  def make_control_maps(%{cfg: %{job: jobs, cmd: cmds}}) do
    import Access, only: [key: 2]

    # spin through all jobs
    for {job_name, job_spec} when is_map(job_spec) <- jobs,
        # spin through specs specs for each job
        {id, spec} when is_map(spec) <- job_spec,
        reduce: [] do
      acc ->
        # assemble the revised map for this id/spec, including the list of
        # defined commands for individual cmd validations
        new_spec =
          %{
            job: job_name,
            id: id,
            path: [:cfg, job_name, id],
            description: get_in(spec, [key(:description, "no description")]),
            otherwise: get_in(spec, [:otherwise]),
            available_cmds: cmds
          }
          |> validate_device(job_spec)

        [acc, make_control_maps_for(new_spec, spec)]
    end
    |> List.flatten()
  end

  # (2 of 3) missing cmd definitions, ok add an empty map
  def make_control_maps(%{cfg: %{job: _jobs}} = s) do
    put_in(s, [:cfg, :cmd], %{}) |> make_control_maps()
  end

  # (3 of 3) missing or empty jobs
  def make_control_maps(_s), do: []

  # (1 of 2) a well formed spec
  defp make_control_maps_for(
         %{available_cmds: cmds} = new_spec,
         %{start: %{sun_ref: _, cmd: _} = start, finish: %{sun_ref: _} = finish}
       ) do
    put_in(new_spec, [:start], make_spec(start, cmds))
    |> put_in([:finish], make_spec(finish, cmds))
    |> clean()
  end

  # (2 of 2) unmatched or malformed spec
  defp make_control_maps_for(new_spec, spec) do
    invalid_msg(new_spec, "malformed spec", spec)
  end

  defp make_spec(%{sun_ref: ref} = spec, known_cmds) do
    # this sequence will accumulate a fresh map into the first arg
    # using the second arg to source data, as needed.
    # all datetimes and durations have been validated during initial parse.
    # the only possible invalid conditions are related to the :cmd
    calc_at(%{ref: ref}, spec)
    |> validate_cmd(spec, known_cmds)
  end

  defp calc_at(acc, %{sun_ref: ref} = spec) do
    import Agnus, only: [sun_info: 1]
    import Timex, only: [add: 2, subtract: 2]

    # get the actual %DateTime for the sun_ref
    # NOTE: the sun ref key validated during parse of the config
    at = sun_info(ref)

    # calcuate the actual date time using the optional :minus or :plus
    # if :minus is present, subtract from sun ref
    # if :plus is present, add to sun ref
    # neither present, move sun ref to at key

    # NOTE: plus/minus have been validated as Durations during parsing
    case spec do
      %{minus: x} -> put_in(acc, [:at], subtract(at, x))
      %{plus: x} -> put_in(acc, [:at], add(at, x))
      _x -> put_in(acc, [:at], at)
    end
  end

  defp validate_cmd(acc, spec, known) do
    put_cmd = fn x -> put_in(acc, [:cmd], x) end
    # validate the optional :cmd
    # 1. :on or :off
    # 2. references a defined cmd
    # 3. no cmd, just pass through the accumulator
    case get_in(spec, [:cmd]) do
      x when x in [:on, :off] -> put_cmd.(x)
      x when is_map_key(known, x) -> put_cmd.(get_in(known, [x]) || :bad_cmd)
      x when is_nil(x) -> put_cmd.(:undefined)
      x -> invalid_msg(acc, "unknown cmd", x)
    end
  end

  defp validate_device(acc, job) when is_map(job) do
    case get_in(job, [:device]) do
      x when is_binary(x) -> validate_device(acc, x)
      x when is_nil(x) -> invalid_msg(acc, "device missing", {:device, :missing})
      x -> invalid_msg(acc, "device not supported", x)
    end
  end

  defp validate_device(acc, device) do
    import Lights.Devices, only: [exists?: 1]

    if exists?(device) do
      put_in(acc, [:device], device)
    else
      invalid_msg(acc, "device #{device} not found", {:device, :not_found})
    end
  end

  defp invalid_msg(%{invalid: x} = acc, msg, what) when is_list(x) do
    invalids = [x, [make_msg(msg, what)]] |> List.flatten()
    acc = put_in(acc, [:invalid], invalids)

    case what do
      {:device = x, val} -> put_in(acc, [x], val)
      _x -> acc
    end
  end

  defp invalid_msg(acc, msg, what) do
    put_in(acc, [:invalid], []) |> invalid_msg(msg, what)
  end

  defp make_msg(msg, what) do
    case what do
      {_what} -> msg
      what -> Enum.join([msg, inspect(what)], " ")
    end
  end

  defp clean(ctrl_map) do
    for trash <- [:otherwise, :available_cmds], reduce: ctrl_map do
      acc ->
        case acc do
          %{otherwise: nil} = x -> Map.delete(x, :otherwise)
          x -> Map.delete(x, trash)
        end
    end
  end
end
