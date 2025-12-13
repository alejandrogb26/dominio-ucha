# 🏆 Simulación de Intranet y Automatización de Usuarios – GaliciaSkills 2025

Durante el curso 2025-2026 tuve la oportunidad de participar en las  
[**GaliciaSkills 2025**](https://www.edu.xunta.gal/fp/galiciaskills-2025), dentro de la especialidad  
[**TIC – Administración de Sistemas en Red**](https://www.edu.xunta.gal/fp/listaxe-oficial-participantes-galiciaskills-2025#tic-sistemas-rede).

Como parte de la preparación para la competición, desarrollé una **simulación completa de la intranet del  
[CIFP Rodolfo Ucha Piñeiro](https://www.cifprodolfoucha.es/)**, abarcando tanto la **infraestructura de servidores** como la **configuración de los equipos cliente**.

---

## 🎯 Objetivo del proyecto

El objetivo principal fue **recrear un entorno realista de centro educativo**, similar al utilizado en producción, y **automatizar tareas clave de administración de sistemas**, con especial foco en:

- Gestión de usuarios
- Integración entre sistemas Windows y Linux
- Seguridad perimetral
- Automatización mediante scripts

---

## 👥 Automatización del alta de usuarios en Active Directory

Una de las partes más importantes de la simulación fue la **automatización del alta de alumnos en un dominio Windows (Active Directory)**.

El flujo de trabajo implementado es el siguiente:

1. **Base de datos simulando XADE**
   - Archivo: `xade.sql`
   - Contiene los datos de los alumnos, simulando el funcionamiento del sistema XADE real.

2. **Exportación de usuarios**
   - Script en Python: `exportarUsuariosDB.py`
   - Exporta los datos de la base de datos a formato **JSON**.
   - Ejemplo de salida:
     ```text
     usuarios_ad_export_20251008_163532.json
     ```

3. **Alta automática en Active Directory**
   - Script en **PowerShell**
   - Funciones principales:
     - Crear los usuarios en el dominio Windows
     - Asignar atributos
     - Crear las carpetas personales de los alumnos
     - Integración con un servidor **Ubuntu** que actúa como **NAS**

---

## 🔥 Seguridad y red

Además de la gestión de usuarios, el proyecto incluye scripts relacionados con la **seguridad de red y el encaminamiento**:

- **Scripts `.sh` para iptables**
  - Inicialización de las reglas del:
    - Proxy
    - Router

- **Script en Bash para la gestión dinámica del proxy**
  - Permite administrar las reglas del proxy
  - El proxy actúa también como **router de salida a Internet**

---

## 🧱 Tecnologías utilizadas

- **Windows Server / Active Directory**
- **Ubuntu Server**
- **Python**
- **PowerShell**
- **Bash**
- **MySQL / MariaDB**
- **iptables**
- **JSON**

---

## 🎓 Contexto educativo

Este proyecto fue desarrollado como parte de la **preparación para una competición de FP**, con un enfoque totalmente práctico y realista, simulando:

- Entornos de producción
- Procedimientos automatizados
- Integración entre distintos sistemas operativos
- Escenarios habituales en centros educativos y redes corporativas

---

## 👤 Autor

**Alejandro Gómez Blanco**  
Participante en **GaliciaSkills 2025 – TIC Administración de Sistemas en Red**
