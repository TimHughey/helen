import Config

# configuration for testing Sally.Config
config :sally, Sally.Config.Test,
  key1: [hello: :doctor, yesterday: :tomorrow],
  path_error: [search: ["/never"]],
  profiles: [search: ["test/etc/host"]],
  firmware: [search: ["test/etc/host"], file_regex: ~r/^[0-9]{2}[.].+-ruth[.]bin$/],
  tmp: [search: ["/", "/var"]]

config :sally, Sally.Host,
  profiles: [search: ["test/etc/host", "."]],
  firmware: [search: ["test/etc/host", "."], file_regex: ~r/^[0-9]{2}[.].+-ruth[.]bin$/]
