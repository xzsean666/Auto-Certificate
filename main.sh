#!/usr/bin/env bash
# Backwards compatibility wrapper forwarding to ngx-cert-manager
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/ngx-cert-manager" "$@"
