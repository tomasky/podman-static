#!/bin/sh

set -eux

podman run -p 8081:8080 --rm alpine:3.24 /bin/sh -c "echo \$'#!/bin/sh\ntimeout 1 cat - >/dev/null; echo -e \\\"HTTP/1.1 200 OK\n\nup\\\"' > /tmp/healthy && chmod +x /tmp/healthy && timeout 9 nc -l -p 8080 -e /tmp/healthy" &

# The published port is IPv4 only, so connect to 127.0.0.1 explicitly: resolving
# "localhost" may pick ::1 first and fail with "Connection refused".
# Retry while the container starts and netavark publishes the port.
attempts=0
until wget -O - 127.0.0.1:8081; do
	attempts=$((attempts + 1))
	[ "$attempts" -lt 15 ] || exit 1
	sleep 1
done
