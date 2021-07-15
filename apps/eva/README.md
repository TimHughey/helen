# Eva

Eva controls habitat conditions using the reported values of immutable devices and the real world changes
brought forth by mutable devices.

Simply put... sensor readings (e.g. temperature, relative humidity) drive the actuatation of
devices (e.g. heaters, dehumidifiers) to condition the environment.

#### Example Configurations

##### Follow The Leader

This mode uses the equipment to keep the value of the follower sensor within a specific range of the leader sensor value.

```toml
variant = "follow"
description = "keeps follower sensor value close to the leader sensor value"
initial_mode = "ready"

[sensor.leader]
  name = "black temp"
  datapoint = "temp_f"
  since = "PT5M"

[sensor.follower]
  name = "green temp"
  range = [-0.3, 0.3]
  since = "PT5M"

[equipment]
  name = "relay0"
  impact = "raises"
```
