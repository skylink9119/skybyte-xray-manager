#!/usr/bin/env bash
# Isolated fixtures only; never operate on production services.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONPATH="$PWD/tests${PYTHONPATH:+:$PYTHONPATH}"
exec "${PYTHON_BIN:-python3}" -m unittest -v test_services.ServiceTests.test_uninstall_removes_owned_shortcut_and_preserves_backup test_services.ServiceTests.test_uninstall_preserves_replaced_shortcut test_services.ServiceTests.test_uninstall_without_nodes_or_unit_removes_manager_and_keeps_backup test_services.ServiceTests.test_uninstall_stop_failure_keeps_manager_and_configuration "$@"
