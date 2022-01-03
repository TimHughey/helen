import Config

config :glow, Glow,
  opts: [
    latitude: 40.21089564609479,
    longitude: -74.0109850020794,
    timezone: "America/New_York"
  ],
  instances: [
    front_chandelier: [
      equipment: "front chandelier pwm",
      defaults: [execute: [params: [primes: 8, step: 6, step_ms: 40]]],
      episodes: [
        [id: "Evening", event: "sunset", execute: [type: "random", params: [min: 384, max: 1024]]],
        [id: "Overnight", event: "astro set", execute: [type: "random", params: [min: 175, max: 640]]],
        [id: "Day", event: "civil rise", execute: [cmd: "off"]]
      ]
    ],
    front_evergreen: [
      equipment: "front evergreen pwm",
      defaults: [execute: [params: [step: 12, step_ms: 40]]],
      episodes: [
        [id: "Evening", event: "sunset", execute: [type: "random", params: [min: 384, max: 3072]]],
        [id: "Overnight", event: "astro set", execute: [type: "random", params: [min: 175, max: 2560]]],
        [id: "Day", event: "civil rise", execute: [cmd: "off"]]
      ]
    ],
    front_red_maple: [
      equipment: "front red maple pwm",
      defaults: [execute: [params: [primes: 8, step: 12, step_ms: 40]]],
      episodes: [
        [id: "Evening", event: "sunset", execute: [type: "random", params: [min: 384, max: 3072]]],
        [id: "Overnight", event: "astro set", execute: [type: "random", params: [min: 175, max: 2560]]],
        [id: "Day", event: "civil rise", execute: [cmd: "off"]]
      ]
    ],
    greenhouse: [
      equipment: "greenhouse alpha power",
      episodes: [
        [id: "Sunshine", event: "civil rise", execute: [cmd: "on"]],
        [id: "Night", event: "civil rise", shift: [hours: 14], execute: [cmd: "off"]]
      ]
    ]
  ]
