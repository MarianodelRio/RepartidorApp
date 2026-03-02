#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  run_tests.sh — Lanza todos los tests y muestra cobertura de código
#
#  Uso:
#    ./run_tests.sh            # backend + flutter
#    ./run_tests.sh backend    # solo backend Python
#    ./run_tests.sh flutter    # solo Flutter
#    ./run_tests.sh --html     # backend + flutter + abre informe HTML
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"
OPEN_HTML=false
RUN_BACKEND=true
RUN_FLUTTER=true

# ── Argumento opcional ────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    backend)  RUN_FLUTTER=false ;;
    flutter)  RUN_BACKEND=false ;;
    --html)   OPEN_HTML=true ;;
  esac
done

# ── Colores ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

section() { echo -e "\n${CYAN}${BOLD}━━━  $1  ━━━${RESET}"; }
ok()      { echo -e "${GREEN}✔  $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠  $1${RESET}"; }
fail()    { echo -e "${RED}✘  $1${RESET}"; }

# ═════════════════════════════════════════════════════════════════════════════
#  BACKEND — pytest + pytest-cov
# ═════════════════════════════════════════════════════════════════════════════
run_backend() {
  section "BACKEND — Tests + Cobertura (Python)"
  cd "$SCRIPT_DIR"

  # Activa el venv si existe
  if [[ -f "venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source venv/bin/activate
  else
    warn "venv no encontrado — usando Python del sistema"
  fi

  # Comprueba que pytest-cov está instalado
  if ! python -m pytest --co -q 2>/dev/null | head -1 &>/dev/null; then
    warn "Instalando dependencias de test..."
    pip install -q pytest pytest-cov httpx
  fi

  echo ""
  # --cov=app       → mide solo el código de producción (carpeta app/)
  # --cov-report=term-missing → muestra en terminal qué líneas faltan
  # --cov-report=html         → genera informe HTML navegable
  python -m pytest \
    --cov=app \
    --cov-report=term-missing \
    --cov-report=html:coverage/backend_html \
    -q \
    "$@"

  BACKEND_EXIT=$?
  echo ""
  if [[ $BACKEND_EXIT -eq 0 ]]; then
    ok "Backend: todos los tests pasaron"
    echo -e "   Informe HTML → ${BOLD}coverage/backend_html/index.html${RESET}"
  else
    fail "Backend: hay tests fallando"
  fi

  return $BACKEND_EXIT
}

# ═════════════════════════════════════════════════════════════════════════════
#  FLUTTER — flutter test --coverage + lcov (si disponible)
# ═════════════════════════════════════════════════════════════════════════════
run_flutter() {
  section "FLUTTER — Tests + Cobertura (Dart)"
  cd "$FLUTTER_DIR"

  echo ""
  flutter test --coverage 2>&1
  FLUTTER_EXIT=$?

  # flutter test --coverage genera flutter_app/coverage/lcov.info
  LCOV_FILE="$FLUTTER_DIR/coverage/lcov.info"

  echo ""
  if [[ $FLUTTER_EXIT -eq 0 ]]; then
    ok "Flutter: todos los tests pasaron"
  else
    fail "Flutter: hay tests fallando"
  fi

  # ── Resumen de cobertura con lcov ────────────────────────────────────────
  if command -v lcov &>/dev/null && [[ -f "$LCOV_FILE" ]]; then
    echo ""
    echo -e "${BOLD}Resumen de cobertura Flutter:${RESET}"
    lcov --summary "$LCOV_FILE" 2>&1 | grep -E "lines|functions|branches"

    # Informe HTML si genhtml está disponible
    if command -v genhtml &>/dev/null; then
      genhtml "$LCOV_FILE" \
        --output-directory "$SCRIPT_DIR/coverage/flutter_html" \
        --quiet
      echo -e "   Informe HTML → ${BOLD}coverage/flutter_html/index.html${RESET}"
    fi
  elif [[ -f "$LCOV_FILE" ]]; then
    # lcov no instalado: calcular % manualmente desde lcov.info
    echo ""
    echo -e "${BOLD}Cobertura Flutter (desde lcov.info):${RESET}"
    # DA = líneas ejecutables, LH = líneas cubiertas
    TOTAL=$(grep -c "^DA:" "$LCOV_FILE" 2>/dev/null || echo 0)
    COVERED=$(grep "^DA:" "$LCOV_FILE" 2>/dev/null | grep -cv ",0$" || echo 0)
    if [[ $TOTAL -gt 0 ]]; then
      PCT=$(awk "BEGIN { printf \"%.1f\", ($COVERED/$TOTAL)*100 }")
      echo -e "   Líneas: ${COVERED}/${TOTAL}  →  ${BOLD}${PCT}%${RESET}"
    fi
    warn "Instala 'lcov' para un resumen más completo: sudo apt install lcov"
  else
    warn "No se generó lcov.info — la cobertura no está disponible"
  fi

  return $FLUTTER_EXIT
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════════════════════
BACKEND_EXIT=0
FLUTTER_EXIT=0

[[ "$RUN_BACKEND" == true ]] && run_backend || true
BACKEND_EXIT=${BACKEND_EXIT:-0}

[[ "$RUN_FLUTTER" == true ]] && run_flutter || true
FLUTTER_EXIT=${FLUTTER_EXIT:-0}

# ── Resumen final ─────────────────────────────────────────────────────────────
section "RESUMEN"
[[ "$RUN_BACKEND" == true ]] && {
  [[ $BACKEND_EXIT -eq 0 ]] && ok "Backend  OK" || fail "Backend  FALLIDO"
}
[[ "$RUN_FLUTTER" == true ]] && {
  [[ $FLUTTER_EXIT -eq 0 ]] && ok "Flutter  OK" || fail "Flutter  FALLIDO"
}

# ── Abre HTML si se pidió ────────────────────────────────────────────────────
if [[ "$OPEN_HTML" == true ]]; then
  [[ "$RUN_BACKEND" == true && -f "$SCRIPT_DIR/coverage/backend_html/index.html" ]] && \
    xdg-open "$SCRIPT_DIR/coverage/backend_html/index.html" 2>/dev/null || true
  [[ "$RUN_FLUTTER" == true && -f "$SCRIPT_DIR/coverage/flutter_html/index.html" ]] && \
    xdg-open "$SCRIPT_DIR/coverage/flutter_html/index.html" 2>/dev/null || true
fi

# Salida con error si alguna suite falló
[[ $BACKEND_EXIT -eq 0 && $FLUTTER_EXIT -eq 0 ]]
