# Sally Topic filters

## Ruth -> Sally

- common: `/<env>/r/<host_ident>`
- host boot: `/host/boot`
- host run: `/host/run`
- host ota: `/host/ota`
- host log: `/host/log`
- cmdack: `<common>/<subsystem>/cmdack/<refid>`
- status: `<common>/<subsystem>/status/<device_ident`

## Sally -> Ruth

- common: `/<env>/<host_ident>`

### Host Directives

- host common: `<common>/host`
- boot: `<host common>/profile/<host_name>`

### Device Directives

- device common: `<common/<subsystem>/<device_ident>`
