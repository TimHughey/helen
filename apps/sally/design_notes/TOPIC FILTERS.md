# Sally Topic filters

### Ruth to Sally

##### Common Base

All messages from Ruth to Sally utilize a common base topic filter structure:

`/<env>/r/<host_ident>`

###### Example

`test/r/ruth.30aea423a21`

##### Subsystem and Category

Topic filters following the common base utilized a well defined structure:

`<common>/<subsystem>/<category>`

##### Host Boot

Announcement a host has started. This message should trigger a return message to assign
the host a name and provide the operational profile for runtime.

`<common>/host/boot`

###### Example

`test/r/ruth.30aea423a21/host/boot`

##### Host Run

`<common>/host/run`

###### Example

`test/r/ruth.30aea423a21/host/run`

##### Mutable Device Status

`<common>/<subsystem>/status/<device_ident>`

###### Example

`/test/r/ruth.30aea423a210/mut/status/ds:28ff88d4011703`

##### Mutable Device Command Ack

`<common>/<subsystem>/cmdack/<device_ident>`

###### Example

`/test/r/ruth.30aea423a210/mut/cmdack/ds:28ff88d4011703`

### Sally To Ruth

##### Common Base

All messages from Sally to Ruth utilize a common base topic filter structure:

`<env>/<host_ident>/<subsystem>`

###### Example

`/test/ruth.30aea423a210/host`

##### Host Profile

`<host common>/profile/<host_name>`

###### Example

`/test/ruth.30aea423a210/host/profile/test-with-devs`

### Mutable Device Commands

`<common/<subsystem>/<device_ident>`

###### Example

`/test/ruth.30aea423a210/ds/ds:28ff88d4011703`
