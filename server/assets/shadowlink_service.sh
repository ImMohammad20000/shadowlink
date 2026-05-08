#!/bin/bash

# Run the reverse tunnel in the foreground so systemd tracks the actual process.
exec /opt/shadowlink/xray-core/xray run -c /opt/shadowlink/xray-core/tunnel_server.json
