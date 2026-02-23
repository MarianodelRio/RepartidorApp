#!/bin/bash

#####################################################################
# 🚀 Repartidor App - Script de Inicio Automático                  #
#####################################################################
# Versión: ver variable SCRIPT_VERSION                              #
# Descripción: Inicia servicios Docker (OSRM+VROOM), backend       #
#              FastAPI y túnel ngrok con verificación completa.     #
# Uso: ./start.sh [opción]                                          #
#   Opciones:                                                       #
#     start    - Inicia todos los servicios (por defecto)          #
#     stop     - Detiene todos los servicios                        #
#     restart  - Reinicia todos los servicios                       #
#     status   - Muestra el estado de los servicios                #
#####################################################################

set -e  # Detener en caso de error

# ── Colores para output ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Configuración ──
SCRIPT_VERSION="3.0.0"
PROJECT_DIR="/home/mariano/Desktop/app_repartir"
VENV_PATH="$PROJECT_DIR/venv/bin/activate"
BACKEND_LOG="$PROJECT_DIR/backend.log"
NGROK_LOG="/tmp/ngrok.log"
BACKEND_PORT=8000
OSRM_PORT=5000
VROOM_PORT=3000
NGROK_API_PORT=4040

# ── Funciones auxiliares ──

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "════════════════════════════════════════════════════════════"
    echo "  🚀 Repartidor App - Inicio de Servicios v${SCRIPT_VERSION}"
    echo "════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_section() {
    echo -e "${BLUE}${BOLD}▶ $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 está instalado"
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
    # Consulta la API local de ngrok (más fiable que parsear el log)
    local max_attempts=10
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local url
        url=$(curl -s "http://127.0.0.1:${NGROK_API_PORT}/api/tunnels" 2>/dev/null \
              | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

# ── Función: Verificar requisitos ──
check_requirements() {
    print_section "Verificando requisitos previos..."
    
    local all_ok=true
    
    check_command docker || all_ok=false
    # docker compose puede ser plugin (docker compose) o standalone (docker-compose)
    if docker compose version &>/dev/null; then
        print_success "docker compose disponible (plugin v2)"
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        print_success "docker-compose disponible (v1)"
        COMPOSE_CMD="docker-compose"
    else
        print_error "docker compose no está disponible"
        print_info "Instala con: sudo apt install docker-compose-v2"
        all_ok=false
    fi
    check_command python3 || all_ok=false
    check_command ngrok || all_ok=false
    
    if [ ! -f "$VENV_PATH" ]; then
        print_error "Entorno virtual Python no encontrado en: $VENV_PATH"
        all_ok=false
    else
        print_success "Entorno virtual Python encontrado"
    fi
    
    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "Directorio del proyecto no encontrado: $PROJECT_DIR"
        all_ok=false
    else
        print_success "Directorio del proyecto encontrado"
    fi
    
    if [ "$all_ok" = false ]; then
        echo ""
        print_error "Faltan requisitos necesarios. Por favor, instala las dependencias."
        exit 1
    fi
    
    echo ""
}

# ── Función: Iniciar servicios Docker ──
start_docker_services() {
    print_section "Iniciando servicios Docker (OSRM + VROOM)..."
    
    cd "$PROJECT_DIR"
    
    # Verificar si ya están corriendo
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas\|vroom-posadas"; then
        print_warning "Servicios Docker ya están corriendo"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "osrm|vroom"
    else
        $COMPOSE_CMD up -d
        if [ $? -eq 0 ]; then
            print_success "Servicios Docker iniciados"
        else
            print_error "Error al iniciar servicios Docker"
            exit 1
        fi
    fi
    
    echo ""
    
    # Esperar a que OSRM esté listo
    print_section "Verificando servicios Docker..."
    if wait_for_service "OSRM (puerto $OSRM_PORT)" \
        "curl -s 'http://localhost:$OSRM_PORT/route/v1/driving/-5.105,37.802;-5.110,37.800?overview=false' | grep -q '\"code\":\"Ok\"'"; then
        print_success "OSRM está operativo"
    else
        print_error "OSRM no responde correctamente"
        docker logs osrm-posadas --tail 20
        exit 1
    fi
    
    # Esperar a que VROOM esté listo
    if wait_for_service "VROOM (puerto $VROOM_PORT)" \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:$VROOM_PORT/health | grep -q 200"; then
        print_success "VROOM está operativo"
    else
        print_error "VROOM no responde correctamente"
        docker logs vroom-posadas --tail 20
        exit 1
    fi
    
    echo ""
}

# ── Función: Iniciar backend FastAPI ──
start_backend() {
    print_section "Iniciando backend FastAPI (puerto $BACKEND_PORT)..."
    
    cd "$PROJECT_DIR"
    
    # Verificar si ya está corriendo
    if lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Backend ya está corriendo en puerto $BACKEND_PORT"
        local pid=$(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t)
        print_info "PID: $pid"
    else
        # Activar venv y arrancar uvicorn en background
        source "$VENV_PATH"
        nohup uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT --reload > "$BACKEND_LOG" 2>&1 &
        local backend_pid=$!
        print_info "Backend iniciado con PID: $backend_pid"
    fi
    
    echo ""
    
    # Esperar a que el backend responda
    if wait_for_service "Backend" \
        "curl -s http://localhost:$BACKEND_PORT/health | grep -q '\"status\":\"ok\"'"; then
        print_success "Backend está operativo"
        local version=$(curl -s http://localhost:$BACKEND_PORT/health | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        print_info "Versión: $version"
        print_info "Docs: http://localhost:$BACKEND_PORT/docs"
    else
        print_error "Backend no responde correctamente"
        tail -n 20 "$BACKEND_LOG"
        exit 1
    fi
    
    echo ""
}

# ── Función: Iniciar ngrok ──
start_ngrok() {
    print_section "Iniciando túnel ngrok..."
    
    # Verificar si ya está corriendo
    if pgrep -x ngrok >/dev/null; then
        print_warning "ngrok ya está corriendo"
        local existing_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$existing_url" ]; then
            print_info "URL pública: $existing_url"
        fi
    else
        rm -f "$NGROK_LOG"
        nohup ngrok http $BACKEND_PORT --log=stdout > "$NGROK_LOG" 2>&1 &
        local ngrok_pid=$!
        print_info "ngrok iniciado con PID: $ngrok_pid"
        
        # Esperar a que ngrok esté listo
        sleep 3
        
        local public_url=$(get_ngrok_url)
        if [ -n "$public_url" ]; then
            print_success "Túnel ngrok creado"
            print_info "URL pública: ${BOLD}$public_url${NC}"
            print_info "Panel ngrok: http://127.0.0.1:$NGROK_API_PORT"
            
            # Verificar que la URL pública responde
            echo -n "  Verificando acceso público"
            if curl -s -o /dev/null -w '%{http_code}' "$public_url/health" | grep -q 200; then
                echo -e " ${GREEN}✓${NC}"
                print_success "Backend accesible públicamente"
            else
                echo -e " ${YELLOW}⚠${NC}"
                print_warning "La URL pública puede tardar unos segundos en estar disponible"
            fi
        else
            print_error "No se pudo obtener la URL pública de ngrok"
            print_info "Revisa el log: tail -f $NGROK_LOG"
        fi
    fi
    
    echo ""
}

# ── Función: Mostrar resumen ──
show_summary() {
    echo -e "${CYAN}${BOLD}"
    echo "════════════════════════════════════════════════════════════"
    echo "  ✨ Todos los servicios están operativos"
    echo "════════════════════════════════════════════════════════════"
    echo -e "${NC}"
    
    echo -e "${BOLD}Servicios Docker:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|osrm|vroom"
    
    echo ""
    echo -e "${BOLD}Puertos locales:${NC}"
    echo -e "  • OSRM:   http://localhost:$OSRM_PORT"
    echo -e "  • VROOM:  http://localhost:$VROOM_PORT"
    echo -e "  • Backend: http://localhost:$BACKEND_PORT"
    echo -e "  • Swagger: http://localhost:$BACKEND_PORT/docs"
    
    echo ""
    echo -e "${BOLD}Acceso público (ngrok):${NC}"
    local public_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
    if [ -n "$public_url" ]; then
        echo -e "  • URL: ${GREEN}${BOLD}$public_url${NC}"
        echo -e "  • Health: $public_url/health"
        echo -e "  • Panel ngrok: http://127.0.0.1:$NGROK_API_PORT"
    else
        echo -e "  ${YELLOW}⚠ ngrok no está corriendo o no se pudo obtener la URL${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}Logs:${NC}"
    echo -e "  • Backend: tail -f $BACKEND_LOG"
    echo -e "  • ngrok:   tail -f $NGROK_LOG"
    echo -e "  • OSRM:    docker logs osrm-posadas -f"
    echo -e "  • VROOM:   docker logs vroom-posadas -f"
    
    echo ""
    echo -e "${BOLD}Comandos útiles:${NC}"
    echo -e "  • Detener todo: ${CYAN}./start.sh stop${NC}"
    echo -e "  • Ver estado:   ${CYAN}./start.sh status${NC}"
    echo -e "  • Reiniciar:    ${CYAN}./start.sh restart${NC}"
    
    echo ""
}

# ── Función: Detener servicios ──
stop_services() {
    print_section "Deteniendo servicios..."
    
    # Detener ngrok
    if pgrep -x ngrok >/dev/null; then
        pkill ngrok
        print_success "ngrok detenido"
    else
        print_info "ngrok no estaba corriendo"
    fi
    
    # Detener backend (lsof puede devolver varios PIDs: padre + workers)
    local backend_pids
    backend_pids=$(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t 2>/dev/null || true)
    if [ -n "$backend_pids" ]; then
        echo "$backend_pids" | xargs kill 2>/dev/null || true
        sleep 1
        # Forzar si alguno sigue vivo
        echo "$backend_pids" | xargs kill -9 2>/dev/null || true
        print_success "Backend detenido (PID: $(echo "$backend_pids" | tr '\n' ' '))"
    else
        print_info "Backend no estaba corriendo"
    fi
    
    # Detener Docker
    cd "$PROJECT_DIR"
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas\|vroom-posadas"; then
        $COMPOSE_CMD down
        print_success "Servicios Docker detenidos"
    else
        print_info "Servicios Docker no estaban corriendo"
    fi
    
    echo ""
    print_success "Todos los servicios detenidos"
}

# ── Función: Mostrar estado ──
show_status() {
    print_section "Estado de los servicios..."
    
    # Docker
    echo -e "${BOLD}Docker:${NC}"
    if docker ps --format '{{.Names}}' | grep -q "osrm-posadas\|vroom-posadas"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|osrm|vroom"
        print_success "Servicios Docker activos"
    else
        print_info "Servicios Docker no están corriendo"
    fi
    
    echo ""
    
    # Backend
    echo -e "${BOLD}Backend FastAPI:${NC}"
    local backend_pid=$(lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t 2>/dev/null)
    if [ -n "$backend_pid" ]; then
        print_success "Backend corriendo (PID: $backend_pid, puerto: $BACKEND_PORT)"
        if curl -s http://localhost:$BACKEND_PORT/health | grep -q '"status":"ok"'; then
            local version=$(curl -s http://localhost:$BACKEND_PORT/health | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
            print_info "Versión: $version"
            print_success "Health check OK"
        else
            print_warning "Health check falló"
        fi
    else
        print_info "Backend no está corriendo"
    fi
    
    echo ""
    
    # ngrok
    echo -e "${BOLD}ngrok:${NC}"
    if pgrep -x ngrok >/dev/null; then
        local public_url=$(curl -s http://127.0.0.1:$NGROK_API_PORT/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$public_url" ]; then
            print_success "ngrok corriendo"
            print_info "URL pública: $public_url"
        else
            print_warning "ngrok corriendo pero no se pudo obtener la URL"
        fi
    else
        print_info "ngrok no está corriendo"
    fi
    
    echo ""
}

# ── Main ──
main() {
    local action="${1:-start}"
    
    case "$action" in
        start)
            print_header
            check_requirements
            start_docker_services
            start_backend
            start_ngrok
            show_summary
            ;;
        stop)
            print_header
            stop_services
            ;;
        restart)
            print_header
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
            tail -n 50 "$BACKEND_LOG" 2>/dev/null || echo "(sin log de backend)"
            echo ""
            echo -e "${BOLD}=== ngrok (últimas 20 líneas) ===${NC}"
            tail -n 20 "$NGROK_LOG" 2>/dev/null || echo "(sin log de ngrok)"
            echo ""
            echo -e "${BOLD}=== OSRM (últimas 20 líneas) ===${NC}"
            docker logs osrm-posadas --tail 20 2>/dev/null || echo "(OSRM no está corriendo)"
            echo ""
            echo -e "${BOLD}=== VROOM (últimas 20 líneas) ===${NC}"
            docker logs vroom-posadas --tail 20 2>/dev/null || echo "(VROOM no está corriendo)"
            ;;
        *)
            echo "Uso: $0 {start|stop|restart|status|logs}"
            echo ""
            echo "Opciones:"
            echo "  start    - Inicia todos los servicios (por defecto)"
            echo "  stop     - Detiene todos los servicios"
            echo "  restart  - Reinicia todos los servicios"
            echo "  status   - Muestra el estado de los servicios"
            echo "  logs     - Muestra los últimos logs de todos los servicios"
            exit 1
            ;;
    esac
}

# Ejecutar
main "$@"
