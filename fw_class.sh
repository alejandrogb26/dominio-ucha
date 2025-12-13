#!/bin/bash

# Autor: Alejandro Gómez Blanco
# Fecha: 16/08/2025
# Script de gestión de iptables para aulas
# Debian 12 router/proxy

# Detalles de cada opción del comando
# -e: Activa el modo "exit on error", lo que significa que el script se detendrá si un comando falla.
# -u: Activa el modo "undefined variable", lo que significa que el script se detendrá si se utiliza una variable no definida.
# -o pipefail: Hace que el script falle si un comando en una tubería falla.
set -euo pipefail

# ------------------------
# FUNCIONES AUXILIARES
# ------------------------

usage() {
    cat <<EOF
Uso: $0 --aula <1-40> --mode <all|https|ports|host|site> [--tcp <puertos>] [--udp <puertos>] [--sites <lista>] [--equipos <lista>] [--ping] [--until <HH:MM>]

Opciones:
  --aula <1-40>     Número de aula a configurar
  --mode <mode>     Modo de operación:
                    all:    Permite todo el tráfico
                    https:  Solo puerto 443 (HTTPS)
                    ports:  Puertos específicos (requiere --tcp/--udp)
                    host:   Equipos específicos (requiere --equipos)
                    site:   Sitios web especificos
  --tcp <puertos>   Lista de puertos TCP separados por comas (para modes ports/host)
  --udp <puertos>   Lista de puertos UDP separados por comas (para modes ports/host)
  --sites <lista>   Lista de URLs separadas por comas (para mode site)
  --equipos <lista> Lista de equipos separados por comas (para mode host)
  --ping            Permitir ping (ICMP echo-request)
  --until <HH:MM>   Hora de expiración de las reglas (formato 24h)

Ejemplos:
  # Permitir todo el tráfico del aula 29 hasta las 15:00
  $0 --aula 29 --mode all --until 15:00

  # Solo permitir HTTPS del aula 10 hasta las 18:30
  $0 --aula 10 --mode https --until 18:30

  # Permitir puertos específicos en el aula 5 hasta mañana a las 08:00
  $0 --aula 5 --mode ports --tcp 22,80,443 --udp 53 --until 08:00

  # Permitir puerto 8080 solo a equipos 1,2,15 del aula 12 con ping hasta las 13:45
  $0 --aula 12 --mode host --tcp 8080 --equipos 1,2,15 --ping --until 13:45

  # Permitir los sitios 'youtube.com', 'cifprodolfoucha.es', 'chatgpt.com' en el aula 33 hasta las 9:15
  $0 --aula 33 --mode site --sites youtube.com,cifprodolfoucha.es,chatgpt.com --until 09:15
EOF
    exit 1
}

validate_ports() {
    local ports=$1
    local protocol=$2

    # Validar formato de puertos
    if ! [[ "$ports" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        echo "Formato de puertos $protocol inválido: $ports"
        exit 1
    fi
}

validate_sites() {
    local sites=$1

    # Validar formato de sitios
    if ! [[ "$sites" =~ ^[a-zA-Z0-9.-]+(,[a-zA-Z0-9.-]+)*$ ]]; then
        echo "Formato de sitios inválido: $sites"
        exit 1
    fi

    # Comprobar si el sitio es resolvible (DNS)
    for site in ${sites//,/ }; do
        if ! host "$site" >/dev/null 2>&1; then
            echo "Sitio no resolvible: $site"
            exit 1
        fi
    done
}

validate_time() {
    local time=$1

    if ! [[ "$time" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo "Formato de hora inválido: $time (usar HH:MM formato 24h)"
        exit 1
    fi
}

clean_rules() {
    local chain=$1

    echo "Eliminando reglas temporales de la cadena $chain..."
    iptables -F "$chain" 2>/dev/null || true
    echo "Reglas eliminadas"
}

remove_existing_at_jobs() {
    local chain=$1

    # Verificar si hay trabajos en la cola
    if ! atq >/dev/null 2>&1; then
        return 0 # No hay trabajos en la cola
    fi

    atq | while read job; do
        job_id=$(echo "$job" | awk '{print $1}')

        # Obtener la última línea que contiene la ruta del script
        job_file=$(at -c "$job_id" 2>/dev/null | tail -2 | awk 'NF{print; exit}')

        # Verificar si el archivo existe y contiene nuestra cadena
        if [[ -n "$job_file" && -f "$job_file" ]]; then
            if grep -q "clean_rules.*$chain" "$job_file" 2>/dev/null; then
                echo "Eliminando trabajo AT existente (ID: $job_id) para $chain"
                atrm "$job_id" 2>/dev/null && rm -- "$job_file" 2>/dev/null || { echo "Error al eliminar trabajo AT (ID: $job_id) o archivo"; exit 1; }
            fi
        fi
    done
}

# ------------------------
# PARÁMETROS
# ------------------------
if [[ $# -eq 0 ]]; then
    usage
fi

AULA=""
MODE=""
TCP_PORTS=""
UDP_PORTS=""
SITES=""
EQUIPOS=""
PING=false
UNTIL=""

# getopt -> parsea y normaliza los argumentos que se pasan al script
# -o "" -> no hay opciones cortas (tipo -m), solo largas
# -l aula:,mode:,tcp:,udp:,equipos:,ping,until:
#    • aula:, mode:, tcp:, udp:, equipos:, until: -> requieren un valor
#    • ping -> no requiere valor (es un flag)
#
# -- "$@" -> pasa todos los parámetros que puso el usuario
# || usage -> si getopt falla (ej: opción no válida), mostramos la ayuda
OPTS=$(getopt -o "" -l aula:,mode:,tcp:,udp:,equipos:,sites:,ping,until: -- "$@") || usage


# eval set -- "$OPTS"
# • "set -- <lista>" sustituye los parámetros posicionales ($1, $2, …) del script
#   por la lista normalizada que devuelve getopt
# • "eval" es necesario porque getopt devuelve una cadena con comillas
#   y así bash la interpreta correctamente
# Ejemplo:
#   ./fw_class.sh --aula 29 --mode ports --tcp 22,80 --ping
# se transforma internamente en:
#   $1=--aula $2=29 $3=--mode $4=ports $5=--tcp $6=22,80 $7=--ping $8=--
eval set -- "$OPTS"

while :; do
    case "$1" in
        --aula) AULA="$2"; shift 2;;
        --mode) MODE="$2"; shift 2;;
        --tcp) TCP_PORTS="$2"; shift 2;;
        --udp) UDP_PORTS="$2"; shift 2;;
        --sites) SITES="$2"; shift 2;;
        --equipos) EQUIPOS="$2"; shift 2;;
        --ping) PING=true; shift;;
        --until) UNTIL="$2"; shift 2;;
        --) shift; break;;
        *) usage;;
    esac
done

# Validaciones
if [[ -z "$AULA" ]] || ! [[ "$AULA" =~ ^[0-9]+$ ]] || (( AULA < 1 || AULA > 40 )); then
    echo "Error: Debes indicar un aula válida (1-40)"
    exit 1
fi

if [[ -z "$MODE" ]]; then
    echo "Error: Debes indicar un modo (--mode all|https|ports|host|site)"
    exit 1
fi

if [[ "$MODE" == "ports" ]] && [[ -z "$TCP_PORTS" && -z "$UDP_PORTS" ]]; then
    echo "Error: Modo 'ports' requiere al menos --tcp o --udp"
    exit 1
fi

if [[ "$MODE" == "host" ]] && [[ -z "$EQUIPOS" ]]; then
    echo "Error: Modo 'host' requiere --equipos"
    exit 1
fi

if [[ "$MODE" == "site" ]] && [[ -z "$SITES" ]]; then
    echo "Error: Modo 'site' requiere --sites"
    exit 1
fi

if [[ -n "$SITES" ]]; then
    validate_sites "$SITES"
fi

if [[ -n "$TCP_PORTS" ]]; then
    validate_ports "$TCP_PORTS" "TCP"
fi

if [[ -n "$UDP_PORTS" ]]; then
    validate_ports "$UDP_PORTS" "UDP"
fi

if [[ -n "$UNTIL" ]]; then
    validate_time "$UNTIL"
fi

CHAIN="aula$AULA"

# ------------------------
# GESTIÓN DE REGLAS EXISTENTES
# ------------------------

# Eliminar trabajos at existentes para esta cadena
if [[ -n "$UNTIL" ]]; then
    remove_existing_at_jobs "$CHAIN"
fi

# Limpiar reglas existentes
if iptables -F "$CHAIN"; then
    echo "Cadena $CHAIN limpiada"
fi

# ------------------------
# REGLAS IPTABLES
# ------------------------

# Aplicar reglas
case "$MODE" in
    all)
        iptables -A "$CHAIN" -j ACCEPT
        echo "Todo el tráfico permitido"
        ;;

    https)
        iptables -A "$CHAIN" -p tcp --dport 443 -j ACCEPT
        echo "Puerto TCP/443 (HTTPS) permitido"
        ;;

    ports)
        if [[ -n "$TCP_PORTS" ]]; then
            iptables -A "$CHAIN" -p tcp -m multiport --dports "$TCP_PORTS" -j ACCEPT
            echo "Puertos TCP $TCP_PORTS permitidos"
        fi
        if [[ -n "$UDP_PORTS" ]]; then
            iptables -A "$CHAIN" -p udp -m multiport --dports "$UDP_PORTS" -j ACCEPT
            echo "Puertos UDP $UDP_PORTS permitidos"
        fi
        ;;

    host)
        for eq in $(echo "$EQUIPOS" | tr ',' ' '); do
            if ! [[ "$eq" =~ ^[0-9]+$ ]]; then
                echo "Error: Número de equipo inválido: $eq"
                exit 1
            fi

            IP="172.21.$AULA.$eq"

            if [[ -n "$TCP_PORTS" ]]; then
                iptables -A "$CHAIN" -s "$IP" -p tcp -m multiport --dports "$TCP_PORTS" -j ACCEPT
                echo "Equipo $IP: Puertos TCP $TCP_PORTS permitidos"
            fi

            if [[ -n "$UDP_PORTS" ]]; then
                iptables -A "$CHAIN" -s "$IP" -p udp -m multiport --dports "$UDP_PORTS" -j ACCEPT
                echo "Equipo $IP: Puertos UDP $UDP_PORTS permitidos"
            fi
        done
        ;;

    site)
        for site in $(echo "$SITES" | tr ',' ' '); do
            # Obtener todas las IPs asociadas al sitio
            IPs=$(host "$site" | awk '/has address/ { print $4 }')
            if [[ -z "$IPs" ]]; then
                echo "Error: No se pudo resolver la IP para el sitio: $site"
                exit 1
            fi

            # Crear reglas para cada IP
            for IP in $IPs; do
                iptables -A "$CHAIN" -p tcp -d "$IP" --dport 443 -j ACCEPT
                iptables -A "$CHAIN" -p tcp -d "$IP" --dport 80 -j ACCEPT
                echo "Regla creada para el sitio: $site (IP: $IP)"
            done
        done
        ;;

    *)
        echo "Error: Modo desconocido: $MODE"
        usage
        ;;
esac

if [[ "$PING" == true ]]; then
    iptables -A "$CHAIN" -p icmp --icmp-type echo-request -j ACCEPT
    echo "Ping (ICMP echo-request) permitido"
fi

# Programar limpieza si se especificó --until
if [[ -n "$UNTIL" ]]; then
    # Crear script temporal para limpieza
    CLEAN_SCRIPT=$(mktemp)
    cat > "$CLEAN_SCRIPT" <<EOF
#!/bin/bash
# Script generado automáticamente para limpiar reglas de $CHAIN
set -euo pipefail
$(type clean_rules | tail -n +2)
clean_rules "$CHAIN"
rm -- "$CLEAN_SCRIPT"  # Auto-eliminarse después de ejecutar
EOF
    chmod +x "$CLEAN_SCRIPT"

    # Programar la limpieza
    echo "Programando limpieza de reglas para las $UNTIL"
    if echo "$CLEAN_SCRIPT" | at "$UNTIL" 2>/dev/null; then
        # Mostrar información del trabajo programado
        JOB=$(atq | grep "$UNTIL" | tail -n 1 | awk '{print $1}')
        echo "Trabajo AT programado (ID: $JOB) para limpiar reglas a las $UNTIL"
    else
        echo "Error: No se pudo programar la limpieza automática"
        exit 1
    fi
fi

echo "Reglas aplicadas correctamente en la cadena $CHAIN"
