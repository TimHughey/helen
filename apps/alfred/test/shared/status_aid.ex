defmodule Alfred.StatusAid do
  alias Alfred.ImmutableStatus, as: ImmStatus
  alias Alfred.MutableStatus, as: MutStatus

  @callback status(name :: binary, opts :: list) :: %ImmStatus{} | %MutStatus{}

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour Alfred.StatusAid

      alias Alfred.StatusAid

      def status(name, opts \\ []), do: StatusAid.status(name, opts)
    end
  end

  alias Alfred.NamesAid

  def status(name, opts \\ []) when is_binary(name) and is_list(opts) do
    case NamesAid.to_parts(name) do
      %{type: :imm} = parts -> make_imm_status(parts)
      %{type: :mut} = parts -> make_mut_status(parts)
    end
  end

  def make_imm_status(parts) do
    data = Map.take(parts, [:temp_f, :temp_c, :relhum])
    expired_ms = (parts[:expired_ms] || 0) * -1
    at = DateTime.utc_now() |> DateTime.add(expired_ms)

    fields = [name: parts.name, found?: true, status_at: at]
    base_status = struct(ImmStatus, fields)

    case parts do
      %{rc: :ok} -> [datapoints: data]
      %{rc: :expired} -> [ttl_expired?: true, datapoints: data]
      %{rc: :error} -> [error: :foobar]
    end
    |> then(fn fields -> struct(base_status, fields) end)
    |> ImmStatus.finalize()
  end

  def make_mut_status(parts) do
    expired_ms = (parts[:expired_ms] || 0) * -1
    at = DateTime.utc_now() |> DateTime.add(expired_ms)

    fields = [name: parts.name, cmd: parts.cmd, found?: true, status_at: at]
    base_status = struct(MutStatus, fields)

    case parts do
      %{rc: :ok} -> []
      %{rc: :expired} -> [ttl_expired?: true]
      %{rc: :pending} -> [pending?: true]
      %{rc: :error} -> [error: :foobar]
    end
    |> then(fn fields -> struct(base_status, fields) end)
    |> MutStatus.finalize()
  end
end