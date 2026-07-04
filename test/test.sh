#!/usr/bin/env bash
# Run all tests — unit + integration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

total_pass=0 total_fail=0
green="$(printf '\033[0;32m')" red="$(printf '\033[0;31m')" reset="$(printf '\033[0m')"

run_suite() {
	local label="$1" script="$2"
	local out ok pass fail

	out=$(bash "$script" 2>&1) && ok=$? || ok=$?

	# Parse counts from the last line: "  ✓ N passed" or "  ✗ N passed, M failed"
	pass=$(echo "$out" | tail -1 | sed -n 's/.* \([0-9]*\) passed.*/\1/p')
	fail=$(echo "$out" | tail -1 | sed -n 's/.* \([0-9]*\) failed.*/\1/p')
	pass=${pass:-0} fail=${fail:-0}

	if [ "$ok" -eq 0 ]; then
		printf "  ${green}✓${reset} %s  (%d)\n" "$label" "$pass"
	else
		printf "  ${red}✗${reset} %s\n" "$label"
		echo "$out"
	fi

	total_pass=$((total_pass + pass))
	total_fail=$((total_fail + fail))
}

echo ""
run_suite "merge-gitignore" test/test-merge-gitignore.sh
run_suite "merge-gitconfig" test/test-merge-gitconfig.sh
run_suite "bootstrap" test/test-bootstrap.sh
echo ""

if [ "$total_fail" -eq 0 ]; then
	printf "  ${green}all %d assertions passed${reset}\n" "$total_pass"
else
	printf "  %d passed, ${red}%d failed${reset}\n" "$total_pass" "$total_fail"
	exit 1
fi
