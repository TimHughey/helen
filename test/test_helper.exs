#
# before running tests delete everything in the database
#
[
  Thermostat,
  Dutycycle,
  Switch.Alias,
  Switch.Device,
  PulseWidth,
  Sensor,
  Remote,
  Remote.Profile.Schema
]
|> HelenTest.delete_all()

#
# ExUnit.configure(
#   exclude: [ota: true, mixtank: true, dutycycle: true],
#   include: [thermostat: true]
# )

# create the default Remote Profile
Remote.Profile.Schema.create("default")

ExUnit.start()
