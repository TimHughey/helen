defmodule NamesTestHelper do
  alias Alfred.NamesAgent

  # (1 of 2) make name is requested
  def make_names(%{make_names: count} = ctx) when is_integer(count) do
    ctx = put_in(ctx, [:names], []) |> put_in([:names_count], count)

    %{ctx | names: create_names(count)}
  end

  # (2 of 2) make names not requested, ensure names is not in the ctx
  def make_names(ctx), do: Map.delete(ctx, :names)

  # (1 of 2) make names map requested and names are available
  def make_seen(%{make_names: _} = ctx) do
    put_in(ctx, [:seen_list], create_seen_list(ctx))
  end

  # (2 0f 2) make names map not requested, ensure names map doesn't exist
  def make_seen(ctx), do: ctx

  def just_saw(ctx) do
    just_saw = fn x ->
      NamesAgent.just_saw(x.seen_list, DateTime.utc_now(), ctx.module)
      ctx
    end

    case ctx do
      %{just_saw: :auto} = x ->
        put_in(x, [:make_seen], true) |> make_seen() |> just_saw.()

      ctx ->
        ctx
    end
  end

  def random_name(ctx) do
    case ctx do
      %{names: [_ | _] = n} = x -> put_in(x, [:random_name], Enum.take_random(n, 1) |> hd())
      x -> x
    end
  end

  defp create_names(count) do
    for _id <- 1..count do
      unique_id = Ecto.UUID.generate() |> String.split("-") |> Enum.at(2)
      "name-#{unique_id}"
    end
  end

  defp create_seen_list(ctx) do
    for name <- ctx.names do
      base = %{name: name, ttl_ms: ctx[:ttl_ms] || 100}

      if :rand.uniform(2) == 1, do: put_in(base, [:pio], 0), else: base
    end
  end
end
