import json
import mariadb
from datetime import datetime

def export_usuarios_ad_to_json():
    try:
        # Configuración de la conexión a la base de datos
        conn = mariadb.connect(
            user="root",
            password="Marte_26",
            host="localhost",
            database="xadeFP"
        )
        cursor = conn.cursor(dictionary=True)

        # Consulta para obtener todos los usuariosAD con información del alumno
        query_usuarios = """
        SELECT u.*
        FROM usuariosAD u
        """
        cursor.execute(query_usuarios)
        usuarios = cursor.fetchall()

        # Para cada usuario, obtener los grupos a los que pertenece
        for usuario in usuarios:
            query_grupos = """
            SELECT g.nombre
            FROM gruposAD g
            JOIN usuariosADGruposAD ug ON g.id = ug.idGrupo
            WHERE ug.idUsuario = ?
            """
            cursor.execute(query_grupos, (usuario['id'],))
            grupos = cursor.fetchall()

            # Convertir la lista de diccionarios a una lista simple de nombres de grupos
            usuario['grupos'] = [grupo['nombre'] for grupo in grupos]

        # Nombre del archivo de salida con timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_filename = f"usuarios_ad_export_{timestamp}.json"

        # Escribir los datos a un archivo JSON
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(usuarios, f, ensure_ascii=False, indent=4)

        print(f"Datos exportados correctamente a {output_filename}")

    except mariadb.Error as e:
        print(f"Error al conectarse a MariaDB: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    export_usuarios_ad_to_json()
