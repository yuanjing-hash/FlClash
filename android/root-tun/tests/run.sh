#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
for suite in restoration lock uninstall boot service-entry authorization notification diagnostics runtime; do
    sh "$TESTS/$suite-test.sh"
done
