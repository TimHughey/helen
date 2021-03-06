## This is Garden

```toml
[server]
timeout = "PT0.333S"
tz = "America/New_York"

[cmd.fade_bright]
description = "fade bright"
cmd = "random"
min = 256
max = 2048
primes = 35
step_ms = 55
step = 31
priority = 7

[cmd.fade_dim]
description = "fade bright"
cmd = "random"
min = 256
max = 1024
primes = 35
step_ms = 55
step = 13
priority = 7

# INDOOR GARDEN

[job.indoor_garden]
device = "indoor garden alpha"
description = "indoor garden"

[job.indoor_garden.day]
description = "daylight"
start = {sun_ref = "nautical_twilight_begin", cmd = "on"}
finish = {sun_ref = "nautical_twilight_begin", plus = "PT14H"}
otherwise = {cmd = "off"}

# FRONT PORCH

[job.porch]
device = "front leds porch"
description = "front porch chandelier"

[job.porch.day]
description = "daytime"
start = {sun_ref = "civil_twilight_begin", cmd = "off"}
finish = {sun_ref = "sunset"}

[job.porch.evening]
description = "random bright fading"
start = {sun_ref = "sunset", cmd = "fade_bright"}
finish = {sun_ref = "civil_twilight_end"}

[job.porch.night]
description = "random dim fading"
start = {sun_ref = "civil_twilight_end", cmd = "fade_dim"}
finish = {sun_ref = "civil_twilight_begin"}

# RED MAPLE

[job.red_maple]
device = "front leds red maple"
description = "red maple"

[job.red_maple.day]
description = "no light"
start = {sun_ref = "civil_twilight_begin", cmd = "off"}
finish = {sun_ref = "sunset"}

[job.red_maple.evening]
description = "random bright fading"
start = {sun_ref = "sunset", cmd = "fade_bright"}
finish = {sun_ref = "civil_twilight_end"}

[job.red_maple.night]
description = "random dim fading"
start = {sun_ref = "civil_twilight_end", cmd = "fade_dim"}
finish = {sun_ref = "civil_twilight_begin"}

# EVERGREEN

[job.evergreen]
device = "front leds evergreen"
description = "front evergreen"

[job.evergreen.day]
description = "no light"
start = {sun_ref = "civil_twilight_begin", cmd = "off"}
finish = {sun_ref = "sunset"}

[job.evergreen.evening]
description = "random bright fading"
start = {sun_ref = "sunset", cmd = "fade_bright"}
finish = {sun_ref = "civil_twilight_end"}

[job.evergreen.night]
description = "random dim fading"
start = {sun_ref = "civil_twilight_end", cmd = "fade_dim"}
finish = {sun_ref = "civil_twilight_begin"}
```
