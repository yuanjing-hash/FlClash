#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
for suite in root-shell process-lifetime heartbeat tun-device cleanup ui-options dns-cache ip-rule-compat stop-core authorization-parser restoration lock uninstall boot service-entry authorization notification diagnostics ota-diagnostics runtime; do
    printf '==> %s\n' "$suite"
    sh "$TESTS/$suite-test.sh"
done
