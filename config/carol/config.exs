import Config

if config_env() == :test do
  config :carol, CarolTest,
    opts: [
      alfred: AlfredSim,
      latitude: 40.21089564609479,
      longitude: -74.0109850020794,
      timezone: "America/New_York"
    ],
    instances: [
      front_chandelier: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "front chandelier pwm",
        episodes: [
          [id: "Evening", event: :sunset, execute: [params: [min: 384, max: 1024]]],
          [id: "Overnight", event: "astro set", execute: [params: [min: 175, max: 640]]],
          [id: "Day", event: "civil rise", execute: [cmd: :off]]
        ]
      ],
      front_evergreen: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "front evergreen pwm",
        episodes: [
          [id: "Evening", event: "sunset", execute: [params: [min: 384, max: 1024]]],
          [id: "Overnight", event: "astro set", execute: [params: [min: 175, max: 640]]],
          [id: "Day", event: "civil rise", execute: [cmd: :off]]
        ]
      ],
      front_red_maple: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "front red maple pwm",
        episodes: [
          [id: "Evening", event: "sunset", execute: [params: [min: 384, max: 1024]]],
          [id: "Overnight", event: "astro set", execute: [params: [min: 175, max: 640]]],
          [id: "Day", event: "civil rise", execute: [cmd: :off]]
        ]
      ]
    ]

  config :carol, CarolNoEpisodes,
    opts: [
      alfred: AlfredSim
    ],
    instances: [
      first_instance: [equipment: "first instance power"],
      second_instance: [equipment: "second instance power"]
    ]

  config :carol, CarolWithEpisodes,
    opts: [
      alfred: AlfredSim,
      latitude: 40.21089564609479,
      longitude: -74.0109850020794,
      timezone: "America/New_York"
    ],
    instances: [
      first_instance: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "mut abcdef off",
        episodes: [
          [id: "First", event: "beginning of day", execute: [cmd: :on]],
          [id: "Second", event: "end of day", shift: [hours: -1], execute: [cmd: :off]],
          [id: "Last", event: "end of day", execute: [cmd: :off]]
        ]
      ]
    ]

  config :carol, UseCarol.Alpha,
    opts: [alfred: AlfredSim],
    instances: [
      first: [equipment: "first instance power"],
      second: [equipment: "second instance power"],
      last: [equipment: "last instance power"]
    ]

  config :carol, UseCarol.Beta,
    opts: [
      alfred: AlfredSim,
      timezone: "America/New_York",
      latitude: 40.21089564609479,
      longitude: -74.0109850020794
    ],
    instances: [
      first_instance: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "mut abcdef off",
        episodes: [
          [id: "First", event: "beginning of day", execute: [cmd: :on]],
          [id: "Second", event: "end of day", shift: [hours: -1], execute: [cmd: :off]],
          [id: "Last", event: "end of day", execute: [cmd: :off]]
        ]
      ],
      second_instance: [
        defaults: [execute: [params: [type: "random", primes: 8, step: 6, step_ms: 40]]],
        equipment: "mut abcdefg off",
        episodes: [
          [id: "First", event: "beginning of day", execute: [cmd: :on]],
          [id: "Second", event: "end of day", shift: [hours: -1], execute: [cmd: :off]],
          [id: "Last", event: "end of day", execute: [cmd: :off]]
        ]
      ]
    ]
end
