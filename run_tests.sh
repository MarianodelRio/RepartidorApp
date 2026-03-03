#!/usr/bin/env bash
# run_tests.sh — Tests + cobertura + análisis estático (Python y Flutter)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

section() { echo -e "\n${CYAN}${BOLD}── $1 ──${RESET}"; }
ok()      { echo -e "  ${GREEN}✔ $1${RESET}"; }
fail()    { echo -e "  ${RED}✘ $1${RESET}"; }

cd "$SCRIPT_DIR"
[[ -f "venv/bin/activate" ]] && source venv/bin/activate

# ─── BACKEND: tests ───────────────────────────────────────────────────────────
section "Unit tests Backend (Python)"

python -m pytest --cov=app --cov-report=term-missing -q 2>&1 \
  | awk '
      /^app\// { printf "  %-40s %s\n", $1, $4 }
      /passed|failed|error/ { print "  " $0 }
    '

# ─── BACKEND: análisis estático ───────────────────────────────────────────────
section "Análisis estático Backend (mypy)"

MYPY_OUT=$(python -m mypy app/ --no-error-summary 2>&1 || true)
if [[ -z "$MYPY_OUT" ]]; then
  ok "Sin errores de tipos"
else
  echo "$MYPY_OUT" | sed 's/^/  /'
  fail "mypy encontró errores"
fi

# ─── FLUTTER: tests ───────────────────────────────────────────────────────────
section "Unit tests Flutter (Dart)"

cd "$FLUTTER_DIR"
TMP=$(mktemp)
script -q -c "flutter test --coverage 2>&1" "$TMP" >/dev/null 2>&1 || true
strings "$TMP" | grep -oE "\+[0-9]+: (All tests passed.*|.* FAILED.*)" | tail -1 \
  | sed 's/+[0-9]*: //' || true
rm -f "$TMP"

LCOV="$FLUTTER_DIR/coverage/lcov.info"
if [[ -f "$LCOV" ]]; then
  echo ""
  awk '
    /^SF:/        { file=$0; sub(/^SF:/, "", file); total=0; cov=0 }
    /^DA:/        { split($0,a,","); total++; if (a[2]+0 > 0) cov++ }
    /^end_of_record/ {
      if (total > 0)
        printf "  %-40s %.1f%%\n", file, (cov/total)*100
    }
  ' "$LCOV"

  TOTAL=$(grep -c "^DA:" "$LCOV")
  COVERED=$(awk '/^DA:/{split($0,a,","); if(a[2]+0>0) c++} END{print c+0}' "$LCOV")
  PCT=$(awk "BEGIN { printf \"%.1f\", ($COVERED/$TOTAL)*100 }")
  echo -e "\n  ${BOLD}TOTAL  ${PCT}%${RESET}"
fi

# ─── FLUTTER: análisis estático ───────────────────────────────────────────────
section "Análisis estático Flutter (dart analyze)"

cd "$FLUTTER_DIR"
ANALYZE_OUT=$(flutter analyze 2>&1 || true)
# Contar solo líneas de error/warning reales (no las de dependencias)
ISSUES=$(echo "$ANALYZE_OUT" | grep -cE "^\s*(error|warning|info|hint)\s" || true)

if echo "$ANALYZE_OUT" | grep -q "No issues found"; then
  ok "Sin problemas"
elif [[ "$ISSUES" -eq 0 ]]; then
  ok "Sin problemas"
else
  echo "$ANALYZE_OUT" | grep -E "^\s*(error|warning|info|hint)\s" | sed 's/^/  /'
  fail "$ISSUES problema(s) encontrado(s)"
fi
