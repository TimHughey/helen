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

  def status(_type, name, opts \\ []) when is_binary(name) and is_list(opts) do
    case NamesAid.to_parts(name) do
      %{type: :imm} = parts -> make_imm_status(parts)
      %{type: :mut} = parts -> make_mut_status(parts)
    end
  end

  def make_imm_status(parts) do
    data = Map.take(parts, [:temp_f, :temp_c, :relhum])
    expired_ms = (parts[:expired_ms] || 0) * -1
    at = DateTime.utc_now() |> DateTime.add(expired_ms)
    s = %ImmStatus{name: parts.name, found?: true, status_at: at}

    case parts do
      %{rc: :ok} -> %ImmStatus{s | datapoints: data}
      %{rc: :expired} -> %ImmStatus{s | ttl_expired?: true, datapoints: data}
    end
    |> ImmStatus.finalize()
  end

  def make_mut_status(parts) do
    expired_ms = (parts[:expired_ms] || 0) * -1
    at = DateTime.utc_now() |> DateTime.add(expired_ms)
    s = %MutStatus{name: parts.name, cmd: parts.cmd, found?: true, status_at: at}

    case parts do
      %{rc: :ok} -> s
      %{rc: :expired} -> %MutStatus{s | ttl_expired?: true}
    end
    |> MutStatus.finalize()
  end
end
