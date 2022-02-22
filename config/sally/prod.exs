import Config

config :sally, Sally.Host,
  firmware: [
    search: ["/dar/www/wisslanding/htdocs/sally", "."],
    file_regex: ~r/^[0-9]{2}[.].+-ruth[.]bin$/
  ],
  profiles: [search: ["/usr/local/helen_v2/etc/host", "."]]
