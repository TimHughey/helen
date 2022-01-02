import Config

config :farm, Farm,
  opts: [
    latitude: 40.21089564609479,
    longitude: -74.0109850020794,
    timezone: "America/New_York"
  ],
  instances: [
    womb_circulation: [
      # NOTE: the cmd is specified in defaults for the single episode
      equipment: "womb circulation pwm",
      defaults: [execute: [params: [type: "fixed", percent: 25]]],
      episodes: [[id: "All Day", event: "beginning of day", execute: [cmd: "25% of max"]]]
    ]
  ]
