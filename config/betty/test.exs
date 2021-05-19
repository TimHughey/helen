import Config

config :betty, Betty.Connection,
  database: "helen_test",
  host: "influx.test.wisslanding.com",
  auth: [method: :basic, username: "helen_test", password: "helen_test"]
