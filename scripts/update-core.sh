#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
go get tailscale.com@latest
go mod tidy
echo "Updated tailscale.com. Commit go.mod/go.sum and rebuild."
