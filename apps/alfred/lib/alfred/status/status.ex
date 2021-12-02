defprotocol Alfred.Status do
  # @type struct_or_nil :: struct() | nil
  # @type status_mod :: atom()
  # @type status_struct :: %{name: binary(), good?: boolean(), status_at: DateTime.t()}
  # @spec create(status_mod(), struct_or_nil()) :: status_struct()

  @fallback_to_any true
  def found(status_source, opts \\ [])
  def not_found(not_found_tuple, status_mod, opts \\ [])
  # def create(status_mod, status_struct, opts \\ [])

  # @spec good?(struct()) :: boolean()
  # def good(src, status, opts \\ [])
  #
  # def good(%{datapoints: []} = src, %{valid?: _} = status, opts)
  #     when is_struct(src)
  #     when is_struct(status)
  #     when is_list(opts) do
  # end
end

defimpl Alfred.Status, for: Any do
  alias Alfred.{ImmutableStatus, MutableStatus}

  def found(%_{device: %_{mutable: true}} = source, opts), do: create(source, MutableStatus, opts)
  def found(%_{device: %_{mutable: false}} = source, opts), do: create(source, ImmutableStatus, opts)

  def not_found({:not_found, name}, status_mod, opts)
      when is_atom(status_mod)
      when is_list(opts) do
    [found?: false, name: name, error: "#{name} not found", status_at: DateTime.utc_now()]
    |> then(fn fields -> struct(status_mod, fields) end)
  end

  def create(src, status_mod, opts) do
    seen_at = seen_at(src, opts)

    struct(status_mod, name: src.name, status_at: seen_at)
    |> check_ttl_expired(src, opts)
  end

  defp check_ttl_expired(status, src, opts) do
    seen_at = status.status_at
    ttl_ms = ttl_ms(src, opts)

    ttl_start_at = Timex.now() |> Timex.shift(millisecond: ttl_ms * -1)

    # if either the device hasn't been seen or the DevAlias hasn't been updated then the ttl is expired
    if Timex.before?(seen_at, ttl_start_at) do
      struct(status, ttl_expired?: true, error: "ttl expired")
    else
      status
    end
  end

  defp seen_at(src, opts) do
    case src do
      %_{device: %_{last_seen_at: seen_at}} -> seen_at
      %_{last_seen_at: seen_at} -> seen_at
      _ -> opts[:seen_at] || DateTime.utc_now()
    end
  end

  defp ttl_ms(src, opts) do
    opt_ttl_ms = opts[:ttl_ms] || 60_000

    case src do
      %_{ttl_ms: ttl_ms} -> ttl_ms
      _ -> opt_ttl_ms
    end
  end
end
