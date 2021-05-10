defmodule Repo do
  @moduledoc false

  #    Helen
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

  use Ecto.Repo,
    otp_app: :helen,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def prepare_query(_operation, query, opts) do
    if Repo.in_transaction?() == false do
      # alias Ecto.Adapters.SQL
      # sql = SQL.to_sql(operation, Repo, query)
      # explain = Repo.explain(operation, query)
      #
      # [
      #   "operation: ",
      #   inspect(operation),
      #   " query: ",
      #   inspect(query),
      #   " opts:",
      #   inspect(opts)
      # ] |> Logger.debug()
      #
      # ["explain:\n", explain, "\n"]
      # |> Logger.debug()
    end

    {query, opts}
  end
end
