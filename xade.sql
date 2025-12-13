DROP DATABASE xadeFP;
CREATE DATABASE xadeFP;
USE xadeFP;

-- Familias ciclo
CREATE TABLE familiasCiclos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT
);

-- Ciclos Formativos
CREATE TABLE ciclosFormativos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    idFamilia INT NOT NULL,
    siglas VARCHAR(10) NOT NULL UNIQUE,
    
    CONSTRAINT FK_CICLOSFORMATIVOS_IDFAMILIA
        FOREIGN KEY (idFamilia)
        REFERENCES familiasCiclos(id)
        ON UPDATE CASCADE
);

-- Grupos por ciclo
CREATE TABLE grupos (
    idCiclo INT NOT NULL,
    curso ENUM('1','2') NOT NULL,
    tipo ENUM('ordinario','distancia','dual') NOT NULL,
    anoInicio YEAR NOT NULL,
    anoFin YEAR NOT NULL,
    PRIMARY KEY(idCiclo, curso, tipo, anoInicio, anoFin),
    
    CONSTRAINT FK_GRUPOS_IDCLICLO
        FOREIGN KEY (idCiclo)
        REFERENCES ciclosFormativos(id)
        ON UPDATE CASCADE
);

-- Módulos asociados a ciclos
CREATE TABLE modulos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    idCiclo INT NOT NULL,
    cursoImpartido ENUM('1','2') NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    codigo VARCHAR(20) UNIQUE,
    horas INT NOT NULL,
    info TEXT,
    CONSTRAINT FK_MODULOS_IDCICLO
        FOREIGN KEY (idCiclo)
        REFERENCES ciclosFormativos(id)
        ON UPDATE CASCADE
);

-- Alumnos
CREATE TABLE alumnos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    dni VARCHAR(9) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    apellido1 VARCHAR(100) NOT NULL,
    apellido2 VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    telefono VARCHAR(15),
    fechaNacimiento DATE
);

-- Matrícula de alumnos en grupos
CREATE TABLE matriculas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    idAlumno INT NOT NULL,
    idCiclo INT NOT NULL,
    curso ENUM('1','2') NOT NULL,
    tipo ENUM('ordinario','distancia','dual') NOT NULL,
    anoInicio YEAR NOT NULL,
    anoFin YEAR NOT NULL,
    fechaMatricula DATE NOT NULL,
    
    CONSTRAINT FK_MATRICULAS_IDALUMNO
        FOREIGN KEY (idAlumno)
        REFERENCES alumnos(id)
        ON UPDATE CASCADE,
    CONSTRAINT FK_MATRICULAS_IDGRUPO
        FOREIGN KEY (idCiclo, curso, tipo, anoInicio, anoFin)
        REFERENCES grupos(idCiclo, curso, tipo, anoInicio, anoFin)
        ON UPDATE CASCADE
);

-- Procedure para añadir el usuario a los grupos que le corresponden.
DELIMITER $$
CREATE PROCEDURE addUserToGroups(IN pIdUsuarioAD INT)
BEGIN
    DECLARE vIdGrupo INT;
    DECLARE done BOOLEAN DEFAULT FALSE;
    
    DECLARE cur_grupos CURSOR FOR
        SELECT id FROM gruposAD 
        WHERE SUBSTRING_INDEX(distinguishedName, ',', -7) IN (
            SELECT SUBSTRING_INDEX(distinguishedName, ',', -7)
            FROM usuariosAD WHERE id = pIdUsuarioAD
        );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN cur_grupos;
        read_loop: LOOP
            FETCH cur_grupos INTO vIdGrupo;
            
            IF done THEN
                LEAVE read_loop;
            END IF;
            
            INSERT INTO usuariosADGruposAD(idUsuario, idGrupo) VALUES (pIdUsuarioAD, vIdGrupo);
        END LOOP read_loop;
    CLOSE cur_grupos;
END $$
DELIMITER ;

-- Trigger para introducir los datos del alumno
DELIMITER $$
CREATE TRIGGER insertNewUserInAD AFTER INSERT ON matriculas
FOR EACH ROW
BEGIN
    # Declarar las variables.
    DECLARE username VARCHAR(50);
    DECLARE siglasCiclo VARCHAR(10);
    DECLARE familiaCiclo VARCHAR(100);
    DECLARE distinguishedNameAlumno VARCHAR(255);
    DECLARE displayNameAlumno VARCHAR(150);
    DECLARE rutHomePersVar VARCHAR(255);
    DECLARE rutCarpComunVar VARCHAR(255);
    DECLARE rutCarpCompartidaVar VARCHAR(255);
    DECLARE rutCarpCompSmbVar VARCHAR(255);
    
    
    # ---------------------------------
    # 1. OBTENER LOS DATOS DEL ALUMNO
    # ---------------------------------
    # Crear el username del alumno
    SELECT LOWER(CONCAT(nombre, LEFT(apellido1, 1), LEFT(apellido2, 1))) INTO username FROM alumnos WHERE id = NEW.idAlumno;

    # Obtener las siglas del ciclo.
    SELECT LOWER(siglas) INTO siglasCiclo FROM ciclosFormativos WHERE id = NEW.idCiclo;

    # Obtener el nombre de la familia profesional del ciclo.
    SELECT LOWER(nombre) INTO familiaCiclo FROM familiasCiclos
    WHERE id = (
        SELECT idFamilia FROM ciclosFormativos
        WHERE id = NEW.idCiclo
    );
    
    # Construir el distinguishedName del alumno.
    SET distinguishedNameAlumno = CONCAT('CN=', username, ',OU=', NEW.curso, ',OU=', NEW.tipo, ',OU=', siglasCiclo, ',OU=', familiaCiclo, ',OU=alumnado,DC=cifprodolfoucha,DC=local');
    
    # Crear el displayname del alumno.
    SELECT 
        CONCAT(
            UPPER(LEFT(nombre, 1)), LOWER(SUBSTRING(nombre, 2)), ' ',
            UPPER(LEFT(apellido1, 1)), LOWER(SUBSTRING(apellido1, 2)), ' ',
            UPPER(LEFT(apellido2, 1)), LOWER(SUBSTRING(apellido2, 2))
        )
    INTO displayNameAlumno FROM alumnos
    WHERE id = NEW.idAlumno;
    
    # Crear el rutHomePers del alumno.
    SET rutHomePersVar = CONCAT('/mnt/DatosPersonais/', familiaCiclo, '/', siglasCiclo, '/', NEW.tipo, '/', NEW.curso, '/', username);
    
    # Crear el rutCarpComun del alumno.
    SET rutCarpComunVar = CONCAT('/mnt/Comun/', SUBSTRING_INDEX(SUBSTRING_INDEX(rutHomePersVar, '/', 7), '/', -4));
    
    # Crear el rutCarpCompartida del alumno.
    SET rutCarpCompartidaVar = CONCAT('/srv/komp/CarpPersonais/', familiaCiclo, '/', siglasCiclo, '/', NEW.tipo, '/', NEW.curso, '/', username);
    
    # Crear el rutCarpCompSmb del alumno.
    SET rutCarpCompSmbVar = CONCAT('\\\\ARQUIVOS\\datPers\\', REPLACE(SUBSTRING_INDEX(rutCarpCompartidaVar, '/', -5), '/', '\\'));
    
    # Insertar el alumno en la tabla 'usuariosAD'.
    INSERT INTO usuariosAD (idAlumno, samaccountname, userPrincipalName, distinguishedName, displayName, rutHomePers, rutCarpComun, rutCarpCompartida, rutCarpCompSmb) 
    VALUES (NEW.idAlumno, username, username, distinguishedNameAlumno, displayNameAlumno, rutHomePersVar, rutCarpComunVar, rutCarpCompartidaVar, rutCarpCompSmbVar);
    
    # -------------------------------------------------
    # 2. Añadir el usuario a los grupos que corresponde
    # -------------------------------------------------
    CALL addUserToGroups((SELECT id FROM usuariosAD WHERE idAlumno = NEW.idAlumno));
END $$
DELIMITER ;

-- Información necesaria para crear cuentas en Active Directory
CREATE TABLE usuariosAD (
    id INT AUTO_INCREMENT PRIMARY KEY,
    idAlumno INT NOT NULL,
    samaccountname VARCHAR(50) NOT NULL UNIQUE,
    userPrincipalName VARCHAR(100) NOT NULL,
    distinguishedName VARCHAR(255) NOT NULL,
    displayName VARCHAR(150),
    rutHomePers VARCHAR(255) NOT NULL,
    rutCarpComun VARCHAR(255) NOT NULL,
    rutCarpCompartida VARCHAR(255) NOT NULL,
    rutCarpCompSmb VARCHAR(255) NOT NULL,
    
    CONSTRAINT FK_USUARIOSAD_IDALUMNO
        FOREIGN KEY (idAlumno)
        REFERENCES alumnos(id)
        ON UPDATE CASCADE
);

CREATE TABLE gruposAD (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    distinguishedName VARCHAR(255) NOT NULL,
    descripcion VARCHAR(255)
);

CREATE TABLE usuariosADGruposAD (
    idUsuario INT NOT NULL,
    idGrupo INT NOT NULL,
    PRIMARY KEY (idUsuario, idGrupo),
    
    CONSTRAINT FK_USUARIOSADGRUPOAD_IDUSUARIO
        FOREIGN KEY (idUsuario)
        REFERENCES usuariosAD(id)
        ON UPDATE CASCADE,
    CONSTRAINT FK_USUARIOSADGRUPOAD_IDGRUPO
        FOREIGN KEY (idGrupo)
        REFERENCES gruposAD(id)
        ON UPDATE CASCADE
);
