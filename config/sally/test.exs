import Config

# configuration for testing Sally.Config
config :sally, SallyConfigAgentTest, key1: [hello: :doctor, yesterday: :tomorrow]
config :sally, SallyConfigTest, host_profiles: [search_paths: ["test/toml"]]
config :sally, SallyConfigDirectoryTest, host_profiles: [search_paths: ["test/toml"]]
