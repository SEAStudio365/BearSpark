#!/usr/bin/env bash
set -euo pipefail
# Dev-only probe: no typed text, symbol contents, or client document data.
exec /usr/bin/log stream --style compact --level debug \
  --predicate 'subsystem == "org.openvanilla.inputmethod.openvanilla" AND eventMessage BEGINSWITH "[symbol-hover]"'
