<#
.SYNOPSIS
    Script para gestionar usuarios de Active Directory y directorios en servidor Ubuntu

.DESCRIPTION
    Este script:
    1. Elimina todos los usuarios de la OU alumnado en AD
    2. Limpia los directorios 1 y 2 en el servidor Ubuntu
    3. Crea nuevos usuarios en AD basados en un archivo JSON
    4. Crea directorios y enlaces simbólicos en el servidor Ubuntu

.PARAMETER JsonFilePath
    Ruta al archivo JSON con la configuración de usuarios

.PARAMETER Domain
    Dominio de Active Directory (opcional)

.PARAMETER ADUsersOU
    OU de Active Directory donde se crearán los usuarios (opcional)

.PARAMETER UbuntuServer
    Dirección IP del servidor Ubuntu (opcional)

.PARAMETER UbuntuUser
    Usuario para conectarse al servidor Ubuntu (opcional)

.EXAMPLE
    .\Manage-ADUsers.ps1 -JsonFilePath "C:\scripts\usuarios_ad_export.json"

.NOTES
    Autor: Alejandro Gómez Blanco
    Versión: 2.0
    Fecha: $(Get-Date -Format "yyyy-MM-dd")
    Requiere: Module Posh-SSH, ActiveDirectory
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
            if (-not (Test-Path $_)) { throw "El archivo JSON no existe en la ruta especificada" }
            if ($_ -notmatch '\.json$') { throw "El archivo debe ser un JSON" }
            $true
        })]
    [string]$JsonFilePath,

    [string]$Domain = "cifprodolfoucha.local",

    [string]$ADUsersOU = "OU=alumnado,DC=cifprodolfoucha,DC=local",

    [string]$UbuntuServer = "172.30.1.250",

    [string]$UbuntuUser = "root"
)

# --------------------------
# |  CONFIGURACIÓN INICIAL |
# --------------------------
$ErrorActionPreference = "Stop"
$Global:SSHSession = $null
$script:StartTime = Get-Date
$script:ExecutionLog = New-Object System.Collections.ArrayList

# ----------------------
# |      FUNCIONES     |
# ----------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        [switch]$NoConsoleOutput
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    $null = $script:ExecutionLog.Add($logEntry)

    if (-not $NoConsoleOutput) {
        $color = @{
            'INFO'    = 'Green'
            'WARNING' = 'Yellow'
            'ERROR'   = 'Red'
            'DEBUG'   = 'Cyan'
        }[$Level]

        Write-Host $logEntry -ForegroundColor $color
    }
}

function Get-SecureCredential {
    param(
        [string]$Message,
        [string]$UserName,
        [switch]$DomainCredential
    )

    try {
        if ($DomainCredential) {
            $cred = Get-Credential -Message $Message -UserName "${UserName}@$Domain"
        }
        else {
            $cred = Get-Credential -Message $Message -UserName $UserName
        }

        if (-not $cred) {
            throw "Credenciales no proporcionadas"
        }

        return $cred
    }
    catch {
        Write-Log -Message "Error al obtener credenciales: $_" -Level ERROR
        throw
    }
}

function Connect-SSHSession {
    param (
        [string]$Server,
        [string]$User,
        [string]$Password,
        [int]$Timeout = 30
    )

    if ($Global:SSHSession -and $Global:SSHSession.IsConnected) {
        Write-Log -Message "Reutilizando sesión SSH existente (SessionId: $($Global:SSHSession.SessionId))" -Level DEBUG
        return $Global:SSHSession
    }

    try {
        $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($User, $secpasswd)

        Write-Log -Message "Estableciendo nueva sesión SSH con $Server..." -Level INFO
        $Global:SSHSession = New-SSHSession -ComputerName $Server -Credential $credential -AcceptKey -ConnectionTimeout $Timeout

        if (-not $Global:SSHSession) {
            throw "No se pudo establecer la sesión SSH"
        }

        Write-Log -Message "Sesión SSH establecida correctamente (SessionId: $($Global:SSHSession.SessionId))" -Level INFO
        return $Global:SSHSession
    }
    catch {
        Write-Log -Message "Error al establecer sesión SSH: $_" -Level ERROR
        throw
    }
}

function Invoke-SSHCommandSingleton {
    param (
        [string]$Command,
        [int]$Timeout = 300
    )

    try {
        Write-Log -Message "Ejecutando comando SSH: $Command" -Level DEBUG
        $result = Invoke-SSHCommand -SessionId $Global:SSHSession.SessionId -Command $Command -TimeOut $Timeout

        if ($result.ExitStatus -ne 0) {
            Write-Log -Message "Comando SSH falló con código $($result.ExitStatus)" -Level WARNING
            Write-Log -Message "Error: $($result.Error)" -Level DEBUG
        }

        return $result
    }
    catch {
        Write-Log -Message "Error al ejecutar comando SSH: $_" -Level ERROR
        throw
    }
}

function Disconnect-SSHSession {
    if ($Global:SSHSession) {
        try {
            Write-Log -Message "Cerrando sesión SSH (SessionId: $($Global:SSHSession.SessionId))" -Level INFO
            Remove-SSHSession -SessionId $Global:SSHSession.SessionId | Out-Null
            $Global:SSHSession = $null
        }
        catch {
            Write-Log -Message "Error al cerrar sesión SSH: $_" -Level WARNING
        }
    }
}

function Test-UserJson {
    param(
        [object]$User,
        [int]$UserIndex
    )

    $requiredFields = @('samaccountname', 'displayName', 'userPrincipalName', 'distinguishedName',
        'rutHomePers', 'rutCarpCompartida', 'rutCarpComun', 'rutCarpCompSmb')

    foreach ($field in $requiredFields) {
        if (-not $User.$field) {
            throw "Usuario #$UserIndex inválido: campo '$field' faltante"
        }
    }

    if ($User.samaccountname -notmatch '^[a-z0-9]+$') {
        throw "Usuario #$UserIndex tiene nombre de usuario inválido: $($User.samaccountname)"
    }

    if ($User.displayName -notmatch '^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$') {
        Write-Log -Message "Usuario #$UserIndex ($($User.samaccountname)) tiene caracteres inusuales en el nombre: $($User.displayName)" -Level WARNING
    }
}

function Remove-ADUsers {
    param(
        [string]$OU,
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        Write-Log -Message "Buscando usuarios en OU $OU..." -Level INFO
        $users = Get-ADUser -Filter * -SearchBase $OU -SearchScope Subtree -Credential $Credential

        if (-not $users) {
            Write-Log -Message "No se encontraron usuarios para eliminar" -Level INFO
            return
        }

        Write-Log -Message "Encontrados $($users.Count) usuarios para eliminar" -Level INFO

        foreach ($user in $users) {
            try {
                Write-Log -Message "Eliminando usuario $($user.SamAccountName)..." -Level INFO
                Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false -Credential $Credential
                Write-Log -Message "Usuario $($user.SamAccountName) eliminado" -Level DEBUG
            }
            catch {
                Write-Log -Message "Error al eliminar usuario $($user.SamAccountName): $_" -Level WARNING
            }
        }

        Write-Log -Message "Proceso de eliminación de usuarios completado" -Level INFO
    }
    catch {
        Write-Log -Message "Error al buscar/eliminar usuarios: $_" -Level ERROR
        throw
    }
}

function Clear-UbuntuDirectories {
    param(
        [string[]]$Paths = @("/mnt/DatosPersonais", "/srv/komp/CarpPersonais")
    )

    try {
        foreach ($path in $Paths) {
            $cleanCommand = @"
if [ -d "$path" ]; then
    find "$path" -type d \( -name "1" -o -name "2" \) -exec bash -c 'echo "Limpiando {}"; rm -rf "{}"/*' \;
else
    echo "Directorio $path no existe";
    exit 1;
fi
"@

            Write-Log -Message "Limpiando directorios 1 y 2 en $path..." -Level INFO
            $result = Invoke-SSHCommandSingleton -Command $cleanCommand

            if ($result.ExitStatus -eq 0) {
                Write-Log -Message "Directorio $path limpiado correctamente" -Level INFO
            }
            else {
                throw "Error al limpiar ${path}: $($result.Error)"
            }

        }
    }
    catch {
        Write-Log -Message "Error al limpiar directorios en Ubuntu: $_" -Level ERROR
        throw
    }
}

function Reset-UbuntuQuotas {
    param(
        [string[]]$FileSystems = @("/mnt/DatosPersonais", "/mnt/Comun")
    )

    try {
        foreach ($fs in $FileSystems) {
            $quotaCommand = @"
if [ -d "$fs" ]; then
    echo "Procesando $fs...";
    quotaoff -ug "$fs";
    rm -f "${fs}/aquota.user" "${fs}/aquota.group";
    mount -o remount,rw "$fs";
    quotacheck -cugv "$fs";
    quotaon -ug "$fs";
else
    echo "Filesystem $fs no existe";
    exit 1;
fi
"@

            Write-Log -Message "Reseteando cuotas en $fs..." -Level INFO
            $result = Invoke-SSHCommandSingleton -Command $quotaCommand

            if ($result.ExitStatus -eq 0) {
                Write-Log -Message "Cuotas reseteadas correctamente en $fs" -Level INFO
            }
            else {
                throw "Error al resetear cuotas en ${fs}: $($result.Error)"
            }
        }
    }
    catch {
        Write-Log -Message "Error al resetear cuotas en Ubuntu: $_" -Level ERROR
        throw
    }
}

function New-ADUsersFromJson {
    param(
        [string]$JsonFile,
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        Write-Log -Message "Cargando archivo JSON $JsonFile..." -Level INFO
        $jsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json

        if (-not $jsonContent) {
            throw "El archivo JSON está vacío o es inválido"
        }

        Write-Log -Message "Encontrados $($jsonContent.Count) usuarios en el JSON" -Level INFO

        $userCount = 0
        foreach ($user in $jsonContent) {
            $userCount++
            try {
                Test-UserJson -User $user -UserIndex $userCount

                $userParams = @{
                    SamAccountName        = $user.samaccountname
                    UserPrincipalName     = "$($user.userPrincipalName)@$Domain"
                    Name                  = $user.samaccountname
                    GivenName             = ($user.displayName -split ' ')[0]
                    Surname               = ($user.displayName -split ' ')[1..2] -join ' '
                    DisplayName           = $user.displayName
                    Path                  = $user.distinguishedName -replace "^CN=[^,]+,", ""
                    HomeDirectory         = $user.rutCarpCompSmb
                    HomeDrive             = "X:"
                    AccountPassword       = (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
                    Enabled               = $true
                    ChangePasswordAtLogon = $true
                    Credential            = $Credential
                }

                Write-Log -Message "Creando usuario $($user.samaccountname)..." -Level INFO
                New-ADUser @userParams

                # Procesamiento de grupos
                foreach ($group in $user.grupos) {
                    try {
                        Add-ADGroupMember -Identity $group -Members $user.samaccountname -Credential $Credential
                        Write-Log -Message "  Añadido al grupo $group" -Level DEBUG
                    }
                    catch {
                        Write-Log -Message "  Error al añadir al grupo ${group}: $_" -Level WARNING
                    }
                }

                Write-Log -Message "Usuario $($user.samaccountname) creado correctamente" -Level INFO
            }
            catch {
                Write-Log -Message "Error procesando usuario #$userCount ($($user.samaccountname)): $_" -Level ERROR
                continue
            }
        }

        Write-Log -Message "Proceso de creación de usuarios completado. $userCount usuarios procesados." -Level INFO
    }
    catch {
        Write-Log -Message "Error al procesar el archivo JSON o crear usuarios: $_" -Level ERROR
        throw
    }
}

function Create-UbuntuUserDirs {
    param(
        [object[]]$Users
    )

    try {
        Write-Log -Message "Preparando creación de directorios en Ubuntu para $($Users.Count) usuarios..." -Level INFO

        foreach ($user in $Users) {
            try {
                $createDirCommand = @"
# Crear directorio personal
mkdir -p "$($user.rutHomePers)"
chown root "$($user.rutHomePers)"
chgrp admins "$($user.rutHomePers)"
chmod 2770 "$($user.rutHomePers)"
setfacl -m d:g:admins:rwx "$($user.rutHomePers)"
setfacl -m u:$($user.samaccountname):rwx "$($user.rutHomePers)"

# Configurar cuotas
setquota -u $($user.samaccountname) 3145728 3145728 0 0 "/mnt/DatosPersonais"
setquota -u $($user.samaccountname) 3145728 3145728 0 0 "/mnt/Comun"

# Crear directorio compartido
mkdir -p "$($user.rutCarpCompartida)"
chown root "$($user.rutCarpCompartida)"
chgrp admins "$($user.rutCarpCompartida)"
chmod 2770 "$($user.rutCarpCompartida)"
setfacl -m u:$($user.samaccountname):r-x "$($user.rutCarpCompartida)"

# Crear enlaces simbólicos
ln -sf "$($user.rutHomePers)" "$($user.rutCarpCompartida)/home"
ln -sf "/mnt/Software" "$($user.rutCarpCompartida)/Software"
ln -sf "$($user.rutCarpComun)" "$($user.rutCarpCompartida)/Comun"

echo "Directorios creados para $($user.samaccountname)"
"@

                Write-Log -Message "Creando directorios para $($user.samaccountname)..." -Level INFO
                $result = Invoke-SSHCommandSingleton -Command $createDirCommand

                if ($result.ExitStatus -eq 0) {
                    Write-Log -Message "Directorios creados correctamente para $($user.samaccountname)" -Level INFO
                }
                else {
                    throw "Error al crear directorios: $($result.Error)"
                }
            }
            catch {
                Write-Log -Message "Error al crear directorios para $($user.samaccountname): $_" -Level ERROR
                continue
            }
        }

        Write-Log -Message "Proceso de creación de directorios completado" -Level INFO
    }
    catch {
        Write-Log -Message "Error general al crear directorios en Ubuntu: $_" -Level ERROR
        throw
    }
}

function Save-ExecutionLog {
    param(
        [string]$LogPath = "C:\scripts\logs"
    )

    try {
        if (-not (Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }

        $logFileName = "ADUserManagement_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullLogPath = Join-Path $LogPath $logFileName

        $script:ExecutionLog | Out-File $fullLogPath -Force
        Write-Log -Message "Log guardado en $fullLogPath" -Level INFO -NoConsoleOutput
    }
    catch {
        Write-Log -Message "Error al guardar log: $_" -Level WARNING
    }
}

# ----------------------
# |  EJECUCIÓN PRINCIPAL |
# ----------------------

try {
    Write-Log -Message "Iniciando script de gestión de usuarios AD-Ubuntu" -Level INFO
    Write-Log -Message "Modo DryRun: $($DryRun.IsPresent)" -Level INFO

    # Paso 1: Obtener credenciales
    $ADCredential = Get-SecureCredential -Message "Credenciales de administrador de dominio" -UserName "alejandrogb" -DomainCredential

    $ubuntuPassword = Read-Host "Introduce la contraseña de root para el servidor Ubuntu ($UbuntuServer)" -AsSecureString
    $ubuntuPlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ubuntuPassword)
    )

    # Paso 2: Conectar a Ubuntu
    Connect-SSHSession -Server $UbuntuServer -User $UbuntuUser -Password $ubuntuPlainPassword

    # Paso 3: Eliminar usuarios AD
    Remove-ADUsers -OU $ADUsersOU -Credential $ADCredential

    # Paso 4: Limpiar directorios en Ubuntu
    Clear-UbuntuDirectories

    # Paso 5: Resetear cuotas en Ubuntu
    Reset-UbuntuQuotas

    # Paso 6: Crear usuarios desde JSON
    $users = Get-Content $JsonFilePath | ConvertFrom-Json
    New-ADUsersFromJson -JsonFile $JsonFilePath -Credential $ADCredential

    # Paso 7: Crear directorios en Ubuntu
    Create-UbuntuUserDirs -Users $users

    Write-Log -Message "Script completado exitosamente!" -Level INFO
}
catch {
    Write-Log -Message "ERROR NO CONTROLADO: $_" -Level ERROR
    Write-Log -Message "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    # Limpieza segura
    try {
        if ($ubuntuPlainPassword) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ubuntuPassword))
            $ubuntuPlainPassword = $null
        }

        Disconnect-SSHSession
        Save-ExecutionLog

        $elapsedTime = (Get-Date) - $script:StartTime
        Write-Log -Message "Tiempo total de ejecución: $($elapsedTime.ToString('hh\:mm\:ss'))" -Level INFO
    }
    catch {
        Write-Host "Error durante la limpieza: $_" -ForegroundColor Red
    }
}
