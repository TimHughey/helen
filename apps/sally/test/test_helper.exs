Application.ensure_all_started(:sally)

include = ExUnit.configuration() |> get_in([:include])
isolated = [:sally_isolated]

if Enum.any?(include, &match?(:sally_isolated, &1)) do
  ExUnit.configure(exclude: [:test], include: isolated)
  ExUnit.start()
else
  ExUnit.start(exclude: isolated)
end
