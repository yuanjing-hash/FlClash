#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
for suite in restoration uninstall boot service-entry authorization runtime; do
    sh "$TESTS/$suite-test.sh"
done
