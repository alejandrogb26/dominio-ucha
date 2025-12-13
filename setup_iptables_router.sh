#!/bin/bash

# Autor: Alejandro Gómez Blanco
# Fecha: 15/08/2025
# Descripción: Configuración del router por defecto.

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
iptables -N win22PrinServices
iptables -N services


# --------------------
# |   CADENA INPUT   |
# --------------------
iptables -A INPUT -s 127.0.0.0/8 -j ACCEPT					                # Permitir todo el tráfico interno del host.
iptables -A INPUT -s 172.30.1.0/24 -j ACCEPT					            # Permitir todo el tráfico de la red servidor.
iptables -A INPUT -s 192.168.150.151 -j ACCEPT					            # Permitir todo el tráfico de la Raspberry con destino al host.

iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT		# Permitir todas las conexiones relacionadas o establecidas.


# ----------------------
# |   CADENA FORWARD   |
# ----------------------
# Gestionar los equipos de los profes (172.21.X.100/24)
# ----------------------------------------------------
iptables -A FORWARD -s 172.21.0.0/16 -d 172.30.1.100 -j win22PrinServices				# Permitir todo el tráfico TCP/UDP/ICMP desde las redes clientes hacia el servidor Windows Server
																						# (***Preguntar a Chema como tienen configurado el tráfico hacia el Windows Server***)

iptables -A FORWARD -s 172.21.0.0/16 -d 172.30.1.0/24 -j services						# Permitir el acceso, desde las 172.21.0.0/16, a los servicios de la red 172.30.1.0/24.
iptables -A FORWARD -s 172.21.0.0/16 -j ACCEPT

iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT


# --------------------------------
# |   CADENA win22PrinServices   |
# --------------------------------
iptables -A win22PrinServices -p tcp -j ACCEPT
iptables -A win22PrinServices -p udp -j ACCEPT
iptables -A win22PrinServices -p icmp -j ACCEPT

# -----------------------
# |   CADENA services   |
# -----------------------
iptables -A services -d 172.30.1.150 -p tcp --dport 80 -j ACCEPT									# Permitir acceder al repositorio local de Debian 12.
iptables -A services -d 172.30.1.200 -p tcp --dport 443 -j ACCEPT
iptables -A services -d 172.30.1.250 -p tcp --dport 445 -j ACCEPT

# ----------------------------------------------------------------------------------------------
# |-------------------------------- REGLAS NAT ------------------------------------------------|
# ----------------------------------------------------------------------------------------------
# -------------------------
# |   CADENA PREROUTING   |
# -------------------------
iptables -t nat -A PREROUTING -s 172.21.0.0/16 -d 172.30.1.100 -p tcp --dport 443 -j DNAT --to-destination 172.30.1.200
