#!/bin/bash

#####################################################################
# Repartidor App - Script de gestión de servicios                  #
#####################################################################
# Uso: ./start.sh [opción]                                          #
#   start        - Inicia todos los servicios (por defecto)        #
#   stop         - Detiene todos los servicios                     #
#   restart      - Reinicia todos los servicios                    #
#   status       - Muestra el estado de los servicios             #
#   logs         - Muestra los últimos logs de cada servicio       #
#   rebuild-map  - Reprocesa el PBF editado y reinicia OSRM       #
#####################################################################

set -e

# ── Colores ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Configuración ──
SCRIPT_VERSION="4.0.0"
PROJECT_DIR="/home/mariano/Desktop/app_repartir"
VENV_PATH="$PROJECT_DIR/venv/bin/activate"
BACKEND_LOG="$PROJECT_DIR/backend.log"
NGROK_LOG="/tmp/ngrok.log"
BACKEND_PORT=8000
OSRM_PORT=5000
NGROK_API_PORT=4040
OSRM_PBF="$PROJECT_DIR/osrm/posadas_editado.osm.pbf"
OSRM_DATA_NAME="posadas_editado"

# ── Helpers ──

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "════════════════════════════════════════════════════════════"
    echo "  Repartidor App - Gestión de servicios v${SCRIPT_VERSION}"
    echo "════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_section() { echo -e "${BLUE}${BOLD}▶ $1${NC}"; }
print_success() { echo -e "  ${GREEN}✓${NC} $1"; }
print_error()   { echo -e "  ${RED}✗${NC} $1"; }
print_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
print_info()    { echo -e "  ${CYAN}ℹ${NC} $1"; }

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 disponible"
        return 0
    else
        print_error "$1 NO está instalado"
        return 1
    fi
}

wait_for_service() {
    local name="$1"
    local check_cmd="$2"
    local max_attempts="${3:-30}"
    local attempt=0

    echo -n "  Esperando a $name"
    while [ $attempt -lt $max_attempts ]; do
        if eval "$check_cmd" &>/dev/null; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    echo -e " ${RED}✗ TIMEOUT${NC}"
    return 1
}

get_ngrok_url() {
    local attempt=0
    while [ $attempt -lt 10 ]; do
        local url
        url=$(curl -s "http://127.0.0.1:${NGROK_API_PORT}/api/tunnels" 2>/dev/null \
              | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$url" ]; then echo "$url"; return 0; fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

# Detecta el comando docker compose disponible (plugin v2 o standalone v1)
detect_compose() {
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        print_error "docker compose no está disponible"
        print_info "Instala con: sudo apt install docker-compose-v2"
        exit 1
    fi
}

# ── check_requirements ──────────────────────────────────────────────────────

check_requirements() {
    print_section "Verificando requisitos..."

    local all_ok=true
    check_command docker     || all_ok=false
    detect_compose
    print_success "docker compose disponible ($COMPOSE_CMD)"
    check_command python3    || all_ok=false
    check_command ngrok      || all_ok=false

    [ -f "$VENV_PATH" ] && print_success "Entorno virtual Python encontrado" \
                        || { print_error "Entorno virtual no encontrado: $VENV_PATH"; all_ok=false; }
    [ -d "$PROJECT_DIR" ] && print_success "Directorio del proyecto encontrado" \
                          || { print_error "Directorio no encontrado: $PROJECT_DIR"; all_ok=false; }

    [ "$all_ok" = false ] && { echo ""; print_error "Faltan requisitos. Instala las dependencias."; exit 1; }
    echo ""
}

# ── start_docker_services ───────────────────────────────────────────────────

start_docker_services() {
    print_section "Iniciando OSRM (Docker)..."
    cd "$PROJECT_DIR"

    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas"; then
        print_warning "OSRM ya está corriendo"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep osrm
    else
        $COMPOSE_CMD up -d
        print_success "Contenedor OSRM iniciado"
    fi
    echo ""

    print_section "Verificando OSRM..."
    if wait_for_service "OSRM (puerto $OSRM_PORT)" \
        "curl -s 'http://localhost:$OSRM_PORT/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false' | grep -q '\"code\":\"Ok\"'"; then
        print_success "OSRM operativo"
    else
        print_error "OSRM no responde"
        docker logs osrm-posadas --tail 20
        exit 1
    fi
    echo ""
}

# ── start_backend ───────────────────────────────────────────────────────────

start_backend() {
    print_section "Iniciando backend FastAPI (puerto $BACKEND_PORT)..."
    cd "$PROJECT_DIR"

    if lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Backend ya está corriendo en puerto $BACKEND_PORT"
        print_info "PID: $(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t)"
    else
        source "$VENV_PATH"
        nohup uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT --reload \
            > "$BACKEND_LOG" 2>&1 &
        print_info "Backend iniciado con PID: $!"
    fi
    echo ""

    if wait_for_service "Backend" \
        "curl -s http://localhost:$BACKEND_PORT/health | grep -q '\"status\":\"ok\"'"; then
        print_success "Backend operativo"
        local version
        version=$(curl -s http://localhost:$BACKEND_PORT/health | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        print_info "Versión: $version"
        print_info "Docs: http://localhost:$BACKEND_PORT/docs"
    else
        print_error "Backend no responde"
        tail -n 20 "$BACKEND_LOG"
        exit 1
    fi
    echo ""
}

# ── start_ngrok ─────────────────────────────────────────────────────────────

start_ngrok() {
    print_section "Iniciando túnel ngrok..."

    if pgrep -x ngrok >/dev/null; then
        print_warning "ngrok ya está corriendo"
        local existing_url
        existing_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null \
                       | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        [ -n "$existing_url" ] && print_info "URL pública: $existing_url"
    else
        rm -f "$NGROK_LOG"
        nohup ngrok http $BACKEND_PORT --log=stdout > "$NGROK_LOG" 2>&1 &
        print_info "ngrok iniciado con PID: $!"
        sleep 3

        local public_url
        public_url=$(get_ngrok_url)
        if [ -n "$public_url" ]; then
            print_success "Túnel ngrok creado"
            print_info "URL pública: ${BOLD}$public_url${NC}"
            print_info "Panel ngrok: http://127.0.0.1:$NGROK_API_PORT"
            echo -n "  Verificando acceso público"
            curl -s -o /dev/null -w '%{http_code}' "$public_url/health" | grep -q 200 \
                && echo -e " ${GREEN}✓${NC}" || echo -e " ${YELLOW}⚠ (puede tardar unos segundos)${NC}"
        else
            print_error "No se pudo obtener la URL pública de ngrok"
            print_info "Revisa el log: tail -f $NGROK_LOG"
        fi
    fi
    echo ""
}

# ── stop_services ───────────────────────────────────────────────────────────

stop_services() {
    print_section "Deteniendo servicios..."

    # ngrok
    if pgrep -x ngrok >/dev/null; then
        pkill ngrok && print_success "ngrok detenido"
    else
        print_info "ngrok no estaba corriendo"
    fi

    # Backend
    local backend_pids
    backend_pids=$(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t 2>/dev/null || true)
    if [ -n "$backend_pids" ]; then
        echo "$backend_pids" | xargs kill 2>/dev/null || true
        sleep 1
        echo "$backend_pids" | xargs kill -9 2>/dev/null || true
        print_success "Backend detenido"
    else
        print_info "Backend no estaba corriendo"
    fi

    # Docker (OSRM)
    cd "$PROJECT_DIR"
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas"; then
        $COMPOSE_CMD down
        print_success "OSRM detenido"
    else
        print_info "OSRM no estaba corriendo"
    fi

    echo ""
    print_success "Todos los servicios detenidos"
}

# ── rebuild_map ─────────────────────────────────────────────────────────────
# Reprocesa el PBF editado y reinicia OSRM. Usar tras editar el mapa en JOSM.

rebuild_map() {
    detect_compose
    print_section "Reprocesando mapa OSRM desde PBF..."

    # Verificar que el PBF existe
    if [ ! -f "$OSRM_PBF" ]; then
        print_error "PBF no encontrado: $OSRM_PBF"
        print_info "Guarda el mapa editado en JOSM como: osrm/posadas_editado.osm.pbf"
        exit 1
    fi
    print_info "PBF: $OSRM_PBF ($(du -sh "$OSRM_PBF" | cut -f1))"

    # Parar OSRM si está corriendo
    cd "$PROJECT_DIR"
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas"; then
        print_info "Parando OSRM..."
        $COMPOSE_CMD stop osrm
        print_success "OSRM parado"
    fi
    echo ""

    # Limpiar snap cache (los snaps cambian con el nuevo mapa)
    rm -f "$PROJECT_DIR/app/data/snap_cache.json"
    print_success "Snap cache eliminado"

    # Limpiar archivos procesados anteriores
    print_section "Eliminando procesado anterior..."
    rm -f "$PROJECT_DIR/osrm/${OSRM_DATA_NAME}".osrm* 2>/dev/null && \
        print_success "Archivos .osrm eliminados" || print_info "No había archivos previos"
    echo ""

    # Paso 1: extract
    print_section "Paso 1/3 — osrm-extract..."
    docker run --rm -v "$PROJECT_DIR/osrm:/data" osrm/osrm-backend \
        osrm-extract -p /opt/car.lua /data/${OSRM_DATA_NAME}.osm.pbf
    print_success "Extract completado"
    echo ""

    # Paso 2: partition
    print_section "Paso 2/3 — osrm-partition..."
    docker run --rm -v "$PROJECT_DIR/osrm:/data" osrm/osrm-backend \
        osrm-partition /data/${OSRM_DATA_NAME}.osrm
    print_success "Partition completado"
    echo ""

    # Paso 3: customize
    print_section "Paso 3/3 — osrm-customize..."
    docker run --rm -v "$PROJECT_DIR/osrm:/data" osrm/osrm-backend \
        osrm-customize /data/${OSRM_DATA_NAME}.osrm
    print_success "Customize completado"
    echo ""

    # Reiniciar OSRM con el nuevo mapa
    print_section "Iniciando OSRM con el nuevo mapa..."
    $COMPOSE_CMD up -d osrm

    if wait_for_service "OSRM (puerto $OSRM_PORT)" \
        "curl -s 'http://localhost:$OSRM_PORT/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false' | grep -q '\"code\":\"Ok\"'"; then
        print_success "OSRM operativo con el nuevo mapa"
    else
        print_error "OSRM no responde tras el rebuild"
        docker logs osrm-posadas --tail 30
        exit 1
    fi
    echo ""
    print_success "Mapa actualizado correctamente. El backend ya usa el nuevo mapa."
}

# ── show_summary ────────────────────────────────────────────────────────────

show_summary() {
    echo -e "${CYAN}${BOLD}"
    echo "════════════════════════════════════════════════════════════"
    echo "  ✓ Todos los servicios están operativos"
    echo "════════════════════════════════════════════════════════════"
    echo -e "${NC}"

    echo -e "${BOLD}Docker:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|osrm"

    echo ""
    echo -e "${BOLD}Puertos locales:${NC}"
    echo -e "  • OSRM:    http://localhost:$OSRM_PORT"
    echo -e "  • Backend: http://localhost:$BACKEND_PORT"
    echo -e "  • Swagger: http://localhost:$BACKEND_PORT/docs"

    echo ""
    echo -e "${BOLD}Acceso público (ngrok):${NC}"
    local public_url
    public_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null \
                 | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
    if [ -n "$public_url" ]; then
        echo -e "  • URL: ${GREEN}${BOLD}$public_url${NC}"
        echo -e "  • Panel: http://127.0.0.1:$NGROK_API_PORT"
    else
        echo -e "  ${YELLOW}⚠ ngrok no está corriendo o no se pudo obtener la URL${NC}"
    fi

    echo ""
    echo -e "${BOLD}Logs:${NC}"
    echo -e "  • Backend: tail -f $BACKEND_LOG"
    echo -e "  • OSRM:    docker logs osrm-posadas -f"
    echo -e "  • ngrok:   tail -f $NGROK_LOG"

    echo ""
    echo -e "${BOLD}Comandos:${NC}"
    echo -e "  • ./start.sh stop          → Detener todo"
    echo -e "  • ./start.sh restart       → Reiniciar todo"
    echo -e "  • ./start.sh status        → Ver estado"
    echo -e "  • ./start.sh rebuild-map   → Reprocesar PBF y reiniciar OSRM"
    echo ""
}

# ── show_status ─────────────────────────────────────────────────────────────

show_status() {
    print_section "Estado de los servicios..."

    echo -e "${BOLD}OSRM (Docker):${NC}"
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|osrm"
        if curl -s "http://localhost:$OSRM_PORT/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false" \
           | grep -q '"code":"Ok"' 2>/dev/null; then
            print_success "OSRM responde correctamente"
        else
            print_warning "OSRM container activo pero no responde a rutas"
        fi
    else
        print_info "OSRM no está corriendo"
    fi
    echo ""

    echo -e "${BOLD}Backend FastAPI:${NC}"
    local backend_pid
    backend_pid=$(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t 2>/dev/null || true)
    if [ -n "$backend_pid" ]; then
        print_success "Backend corriendo (PID: $backend_pid, puerto: $BACKEND_PORT)"
        local health
        health=$(curl -s http://localhost:$BACKEND_PORT/health 2>/dev/null)
        if echo "$health" | grep -q '"status":"ok"'; then
            local version
            version=$(echo "$health" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
            print_info "Versión: $version — Health OK"
        else
            print_warning "Health check falló"
        fi
    else
        print_info "Backend no está corriendo"
    fi
    echo ""

    echo -e "${BOLD}ngrok:${NC}"
    if pgrep -x ngrok >/dev/null; then
        local public_url
        public_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null \
                     | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        [ -n "$public_url" ] && { print_success "ngrok activo"; print_info "URL: $public_url"; } \
                             || print_warning "ngrok corriendo pero sin URL"
    else
        print_info "ngrok no está corriendo"
    fi
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    local action="${1:-start}"

    case "$action" in
        start)
            print_header
            check_requirements
            detect_compose
            start_docker_services
            start_backend
            start_ngrok
            show_summary
            ;;
        stop)
            print_header
            detect_compose
            stop_services
            ;;
        restart)
            print_header
            detect_compose
            stop_services
            sleep 2
            echo ""
            check_requirements
            start_docker_services
            start_backend
            start_ngrok
            show_summary
            ;;
        status)
            print_header
            show_status
            ;;
        logs)
            echo -e "${BOLD}=== Backend (últimas 50 líneas) ===${NC}"
            tail -n 50 "$BACKEND_LOG" 2>/dev/null || echo "(sin log)"
            echo ""
            echo -e "${BOLD}=== ngrok (últimas 20 líneas) ===${NC}"
            tail -n 20 "$NGROK_LOG" 2>/dev/null || echo "(sin log)"
            echo ""
            echo -e "${BOLD}=== OSRM (últimas 20 líneas) ===${NC}"
            docker logs osrm-posadas --tail 20 2>/dev/null || echo "(OSRM no está corriendo)"
            ;;
        rebuild-map)
            print_header
            rebuild_map
            ;;
        *)
            echo "Uso: $0 {start|stop|restart|status|logs|rebuild-map}"
            echo ""
            echo "  start        Inicia OSRM, backend y ngrok"
            echo "  stop         Detiene todos los servicios"
            echo "  restart      Reinicia todos los servicios"
            echo "  status       Muestra el estado actual"
            echo "  logs         Muestra los últimos logs"
            echo "  rebuild-map  Reprocesa el PBF editado y reinicia OSRM"
            exit 1
            ;;
    esac
}

main "$@"
