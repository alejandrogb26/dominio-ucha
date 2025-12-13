#!/bin/bash

# Autor: Alejandro Gómez Blanco
# Fecha: 09/08/2025
# Descripción: Configuración del firewall por defecto.

# --------------------------------------
# |   LIMPIAR COMPLETAMENTE IPTABLES   |
# --------------------------------------
# Eliminar todas las reglas en todas las tablas
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F
iptables -t security -F

# Eliminar todas las cadenas personalizadas
iptables -X
iptables -t nat -X
iptables -t mangle -X
iptables -t raw -X
iptables -t security -X

# Resetear contadores
iptables -Z
iptables -t nat -Z
iptables -t mangle -Z
iptables -t raw -Z
iptables -t security -Z

# Establecer políticas por defecto a ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT


# ------------------------------
# |   CADENAS PERSONALIZADAS   |
# ------------------------------
for i in $(seq 1 40); do
        iptables -N aula$i
done

iptables -N redServ


# --------------------
# |   CADENA INPUT   |
# --------------------
iptables -A INPUT -s 127.0.0.0/8 -j ACCEPT                                                      # Permitir todo el tráfico interno del host.
iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT                                                   # Permitir todo el tráfico de la Raspberry con destino al host.

iptables -A INPUT -s 172.21.0.0/16 -p tcp -i ens18 --dport 3128 -j ACCEPT                       # Permitir las peticiones HTTP a SQUID.
iptables -A INPUT -s 172.21.0.0/16 -p tcp -i ens18 --dport 3129 -j ACCEPT                       # Permitir las peticiones HTTPS a SQUID.

iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT          # Permitir todas las conexiones relacionadas o establecidas.


# ----------------------
# |   CADENA FORWARD   |
# ----------------------
iptables -A FORWARD -s 192.168.1.0/24 -j ACCEPT                                            # Permitir todo el tráfico de la Rapberry con destino a las redes virtuales (XCP-NG).

# Gestionar los equipos de los profes (172.21.X.100/24)
# ----------------------------------------------------
# 1. Borra todos los sets de ipset
for set in $(ipset list -n); do ipset destroy $set; done

# 2. Crear el conjunto de IPs de los equipos .100
ipset create pcsProfes hash:ip

# 3. Añadir todas las IPs .100 (Suponiendo que hay 40 aulas)
for i in {1..40}; do
    ipset add pcsProfes 172.21.$i.100
done

iptables -A FORWARD -m set --match-set pcsProfes src -j ACCEPT

# Crear las reglas para cada cadena de aula.
EXCLUDE=(29 33) # Lista de exclusiones creada para poder gestionar yo mismo las reglas de las aulas 29 33. Esto sobraría en el script normal.

for i in {1..40}; do
        iptables -A FORWARD -s 172.21.$i.0/24 -j aula$i

        saltar=false
        for ex in "${EXCLUDE[@]}"; do
                if [[ $i -eq $ex ]]; then
                        saltar=true
                        break
                fi
        done

        if $saltar; then
                echo "Saltando $i"
                continue
        fi

        iptables -A aula$i -j DROP
done

iptables -A FORWARD -s 172.30.1.0/24 -j redServ

iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# ---------------------
# |   CADENA aula29   |
# ---------------------
iptables -A aula29 -j ACCEPT    # REGLA TEMPORAL, LUEGO ELIMINAR !!!!

# ---------------------
# |   CADENA aula33   |
# ---------------------
iptables -A aula33 -p tcp -m multiport --dports 80,443 -j ACCEPT        # REGLA TEMPORAL, LUEGO ELIMINAR !!!!


# ----------------------
# |   CADENA redServ   |
# ----------------------
iptables -A redServ -j ACCEPT

# ----------------------------------------------------------------------------------------------
# |-------------------------------- REGLAS NAT ------------------------------------------------|
# ----------------------------------------------------------------------------------------------

# ------------------------
# |   CADENA conServMV   |
# ------------------------
iptables -t nat -N conServMV

iptables -t nat -A conServMV -p tcp -m tcp --dport 2200 -j DNAT --to-destination 172.30.1.253:22
iptables -t nat -A conServMV -p tcp -m tcp --dport 2201 -j DNAT --to-destination 172.30.1.200:22
iptables -t nat -A conServMV -p tcp -m tcp --dport 2202 -j DNAT --to-destination 172.30.1.250:22
iptables -t nat -A conServMV -p tcp -m tcp --dport 2203 -j DNAT --to-destination 172.30.1.150:22
iptables -t nat -A conServMV -p tcp -m tcp --dport 5000 -j DNAT --to-destination 172.30.1.100:3389
iptables -t nat -A conServMV -p tcp -m tcp --dport 5001 -j DNAT --to-destination 172.21.29.1:3389
iptables -t nat -A conServMV -p tcp -m tcp --dport 5002 -j DNAT --to-destination 172.21.29.100:3389
iptables -t nat -A conServMV -p tcp -m tcp --dport 5003 -j DNAT --to-destination 172.21.33.1:3389
iptables -t nat -A conServMV -p tcp -m tcp --dport 5004 -j DNAT --to-destination 172.21.33.100:3389
iptables -t nat -A conServMV -p tcp -m tcp --dport 6000 -j DNAT --to-destination 172.30.1.200:3306

# -------------------------
# |   CADENA PREROUTING   |
# -------------------------
#iptables -t nat -A PREROUTING -s 172.21.0.0/16 -p tcp --dport 80 -j REDIRECT --to-port 3128
#iptables -t nat -A PREROUTING -s 172.21.0.0/16 -p tcp --dport 443 -j REDIRECT --to-port 3129
iptables -t nat -A PREROUTING -s 192.168.1.0/24 -j conServMV


# --------------------------
# |   CADENA POSTROUTING   |
# --------------------------
iptables -t nat -A POSTROUTING -s 172.21.0.0/16 -o ens19 -j MASQUERADE

iptables -t nat -A POSTROUTING -s 172.30.1.0/24 -o ens19 -j MASQUERADE
