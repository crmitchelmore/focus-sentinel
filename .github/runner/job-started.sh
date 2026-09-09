#!/bin/bash
set -euo pipefail
exec /opt/homebrew/bin/python3 /Users/bravostation/actions-runners/admin/hooks/runner-policy.py "$@"
