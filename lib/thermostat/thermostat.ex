defmodule Thermostat do
  #    Master Control Program for Wiss Landing
  #    Copyright (C) 2016  Tim Hughey (thughey)

  #    This program is free software: you can redistribute it and/or modify
  #    it under the terms of the GNU General Public License as published by
  #    the Free Software Foundation, either version 3 of the License, or
  #    (at your option) any later version.

  #    This program is distributed in the hope that it will be useful,
  #    but WITHOUT ANY WARRANTY; without even the implied warranty of
  #    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  #    GNU General Public License for more details.

  #    You should have received a copy of the GNU General Public License
  #    along with this program.  If not, see <http://www.gnu.org/licenses/>

  @moduledoc """
    Thermostat schema
  """

  require Logger
  use Ecto.Schema

  import Repo, only: [one: 1, insert_or_update!: 1, preload: 3]
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]

  alias Janice.TimeSupport

  alias Thermostat.Profile
  alias Thermostat.Server

  schema "thermostat" do
    field(:name)
    field(:description)
    field(:switch)
    field(:active_profile)
    field(:sensor)
    field(:state)
    field(:state_at, :utc_datetime_usec)
    field(:log, :boolean)

    has_many(:profiles, Profile)

    timestamps()
  end

  # quietly handle requests to activate a profile that is already active
  def activate_profile(%Thermostat{active_profile: active} = t, profile)
      when is_binary(profile) and active === profile,
      do: {:ok, t}

  def activate_profile(%Thermostat{} = t, profile) when is_binary(profile) do
    if Profile.known?(t, profile) do
      {rc, ct} = change(t, active_profile: profile) |> Repo.update()

      if rc === :ok, do: {rc, Repo.preload(ct, :profiles)}, else: {rc, t}
    else
      {:unknown_profile, t}
    end
  end

  def add([]), do: []

  def add([%Thermostat{} = th | rest]) do
    [add(th)] ++ add(rest)
  end

  def add(%Thermostat{name: name} = th, opts \\ []) do
    q = from(t in Thermostat, where: t.name == ^name, select: {t})

    one(q) |> add(th, opts)
  end

  def add(nil, %Thermostat{name: name} = th, _opts) do
    th
    |> change([])
    |> insert_or_update!()
    |> Profile.ensure_standby_profile_exists()
    |> Thermostat.Server.start_server()

    Thermostat.Server.activate_profile(name, "standby")
  end

  def add(%Thermostat{name: name}, %Thermostat{}, _opts) do
    Logger.warn([inspect(name, pretty: true), " already exists"])
    :already_exists
  end

  # all() function header
  def all(atom, opts \\ [])

  def all(:ids, opts) when is_list(opts) do
    for t <- Repo.all(Thermostat), do: Map.get(t, :id)
  end

  # REFACTORED
  def delete(name) when is_binary(name) do
    th = get_by(name: name)

    if is_nil(th),
      do: {:not_found, name},
      else: delete(th)
  end

  def delete(%Thermostat{id: id}, opts \\ [timeout: 5 * 60 * 1000]) do
    th =
      Repo.get(Thermostat, id)
      |> preload([:profiles], force: true)

    if is_nil(th),
      do: [server: :not_found, db: :not_found],
      else: [server: Server.delete(th), db: elem(Repo.delete(th, opts), 0)]
  end

  # REFACTORED!
  # HAS TEST CASE
  def delete_all(:dangerous) do
    for th <- Repo.all(Thermostat), do: delete(th)
  end

  def get_by(opts) when is_list(opts) do
    filter = Keyword.take(opts, [:id, :device, :name])

    select =
      Keyword.take(opts, [:only]) |> Keyword.get_values(:only) |> List.flatten()

    if Enum.empty?(filter) do
      Logger.warn(["get_by bad args: ", inspect(opts, pretty: true)])
      []
    else
      th =
        from(
          t in Thermostat,
          join: p in assoc(t, :profiles),
          where: ^filter,
          preload: [profiles: p]
        )
        |> one()

      if is_nil(th) or Enum.empty?(select), do: th, else: Map.take(th, select)
    end
  end

  def log?(%Thermostat{log: log}), do: log

  def profiles(
        %Thermostat{active_profile: active_profile, profiles: profiles} = th,
        opts \\ []
      )
      when is_list(opts) do
    active = opts[:active] || false
    names = opts[:names] || false

    cond do
      active and not is_nil(active_profile) -> Profile.active(th)
      active and is_nil(active_profile) -> :none
      names -> Profile.names(th)
      true -> profiles
    end
  end

  def state(%Thermostat{state: curr_state}), do: curr_state

  def state(%Thermostat{} = t, new_state) when is_binary(new_state) do
    {rc, ct} =
      change(t, state: new_state, state_at: TimeSupport.utc_now())
      |> Repo.update()

    if rc === :ok, do: {rc, Repo.preload(ct, :profiles)}, else: {rc, t}
  end

  def switch(%Thermostat{switch: sw}), do: sw
end
