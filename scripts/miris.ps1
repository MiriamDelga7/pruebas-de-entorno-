param($accion)
$ConfirmPreference = "None"
$ErrorActionPreference = "SilentlyContinue"
# ======================
# COMPROBACIONES DE IP
# ======================

function Revisar-IP {
    param($ip)

    # Verifica que el formato sea correcto de 4 numeros separados por puntos
    if ($ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }

    $partes = $ip -split '\.'
    foreach ($o in $partes) {
        # Cada octeto debe estar entre 0 y 255
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }

    # IP 0.0.0.0 no es valida
    if ($ip -eq "0.0.0.0") { return $false }
    # Primer y ultimo octeto del host no pueden ser 0 o 255
    if ([int]$partes[0] -eq 127 -or [int]$partes[0] -eq 0) { return $false }

    return $true
}

function IPaNumero {
    param($ip)
    # Convierte la IP a un numero para comparar rangos
    $p = $ip -split '\.'
    return ([int64]$p[0] -shl 24) -bor ([int64]$p[1] -shl 16) -bor ([int64]$p[2] -shl 8) -bor [int64]$p[3]
}

function NumeroaIP {
    param($num)
    # Convierte el numero de nuevo a formato IP
    $o1 = ($num -shr 24) -band 255
    $o2 = ($num -shr 16) -band 255
    $o3 = ($num -shr 8)  -band 255
    $o4 = $num -band 255
    return "$o1.$o2.$o3.$o4"
}

function ComprobarRango {
    param($ip1, $ip2)
    # Determina si la IP final es mayor o igual que la inicial
    return (IPaNumero $ip2) -ge (IPaNumero $ip1)
}

function Incrementar-IP {
    param($ip)
    # Suma 1 a la IP para no usar la IP del servidor en el rango DHCP
    $num = (IPaNumero $ip) + 1
    return NumeroaIP $num
}

function MismaRed {
    param($ip1, $ip2)
    # Comprueba si dos IPs pertenecen a la misma red /24
    $a = $ip1 -split '\.'
    $b = $ip2 -split '\.'
    return ($a[0] -eq $b[0] -and $a[1] -eq $b[1] -and $a[2] -eq $b[2])
}

function ObtenerMascara {
    param($ip)
    # Devuelve la mascara de subred segun la clase de la IP
    $o1 = ($ip -split '\.')[0]
    if ($o1 -le 126) { return "255.0.0.0" }
    elseif ($o1 -le 191) { return "255.255.0.0" }
    else { return "255.255.255.0" }
}

# ======================
# FUNCIONES DE DHCP
# ======================

function Comprobar-DHCP {
    # Revisa si el servicio DHCP esta instalado
    $feature = Get-WindowsFeature -Name DHCP
    if ($feature.Installed) { Write-Host "Servicio DHCP detectado" }
    else { Write-Host "Servicio DHCP no detectado" }
}

function Instalar-DHCP {
    # Instala el servicio DHCP si no esta presente
    $feature = Get-WindowsFeature -Name DHCP
    if ($feature.Installed) {
        $op = Read-Host "DHCP ya existe. Reinstalar y sobreescribir? (s/n)"
        if ($op -eq "s" -or $op -eq "S") {
            Write-Host "Reinstalando DHCP..."
            Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools -Restart:$false
            Install-WindowsFeature -Name DHCP -IncludeManagementTools
            Write-Host "Proceso de reinstalacion completado"
        } else { Write-Host "Operacion cancelada" }
    } else {
        Write-Host "Instalando DHCP..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
        Write-Host "Instalacion completada"
    }
}

function Configurar-DHCP {
    # Solicita IP inicial y final
    do {
        $IP_INICIAL = Read-Host "IP inicial"
        if (-not (Revisar-IP $IP_INICIAL)) { Write-Host "IP invalida"}
    } until (Revisar-IP $IP_INICIAL)

    do {
        $IP_FINAL = Read-Host "IP final"
        if (-not (Revisar-IP $IP_FINAL)) { Write-Host "IP invalida" }
    } until (Revisar-IP $IP_FINAL)

    if (-not (MismaRed $IP_INICIAL $IP_FINAL)) { Write-Host "Error"; return }
    if (-not (ComprobarRango $IP_INICIAL $IP_FINAL)) { Write-Host "Rango de IP invalido"; return }

    $IP_SERVIDOR = $IP_INICIAL
    $IP_RANGO_INICIAL = Incrementar-IP $IP_INICIAL
    if (-not (ComprobarRango $IP_RANGO_INICIAL $IP_FINAL)) { Write-Host "Error"; return }

    # Solicita gateway
    $GATEWAY = Read-Host "Introduce Gateway (enter para usar IP del servidor)"
    if ([string]::IsNullOrEmpty($GATEWAY)) { $GATEWAY = $IP_SERVIDOR }

    # Solicita DNS
    $DNS1 = Read-Host "DNS principal opcional"
    $DNS2 = Read-Host "DNS secundario opcional"
    if ([string]::IsNullOrEmpty($DNS1)) { $DNS1 = "8.8.8.8" }
    $DNS_CONFIG = if ([string]::IsNullOrEmpty($DNS2)) { $DNS1 } else { "$DNS1,$DNS2" }

    # Solicita tiempos de lease
    $LEASE_DEFAULT = Read-Host "Tiempo de conexion "
    $LEASE_MAX = Read-Host "Tiempo maximo de conexion "
    if ([string]::IsNullOrEmpty($LEASE_DEFAULT)) { $LEASE_DEFAULT = 300 }
    if ([string]::IsNullOrEmpty($LEASE_MAX)) { $LEASE_MAX = 300 }

    $mascara = ObtenerMascara $IP_SERVIDOR
    $partes = $IP_SERVIDOR -split '\.'
    $red = "$($partes[0]).$($partes[1]).$($partes[2]).0"

    # Detecta interfaz de red
    $interfaz = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "10.*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1).InterfaceAlias
    if (-not $interfaz) { Write-Host "No se detecto interfaz valida"; return }

    # Quita IP anterior si existia
    $ipActual = Get-NetIPAddress -InterfaceAlias $interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -eq "Manual"}
    if ($ipActual) { $ipActual | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }

    # Asigna IP al servidor
    New-NetIPAddress -InterfaceAlias $interfaz -IPAddress $IP_SERVIDOR -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

    # Elimina rangos existentes
    Remove-DhcpServerv4Scope -ScopeId $red -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    # Crea nuevo rango DHCP
    Add-DhcpServerv4Scope -Name "RedDHCP" -StartRange $IP_RANGO_INICIAL -EndRange $IP_FINAL -SubnetMask $mascara | Out-Null

    # Configura gateway y DNS
    Set-DhcpServerv4OptionValue -ScopeId $red -Router $GATEWAY -DnsServer $DNS_CONFIG -ErrorAction SilentlyContinue | Out-Null

    # Configura lease
    Set-DhcpServerv4Scope -ScopeId $red -LeaseDuration ([TimeSpan]::FromSeconds($LEASE_DEFAULT)) | Out-Null

    # Activa el rango
    Set-DhcpServerv4Scope -ScopeId $red -State Active -ErrorAction SilentlyContinue | Out-Null

    Restart-Service DHCPServer -ErrorAction SilentlyContinue

    # Muestra resumen
    Write-Host ""
    Write-Host "Configuracion correctamente"
    Write-Host "IP Servidor:" $IP_SERVIDOR
    Write-Host "Rango DHCP:" $IP_RANGO_INICIAL " - " $IP_FINAL
    Write-Host "Gateway:" $GATEWAY
    Write-Host "DNS:" $DNS_CONFIG
    Write-Host "Tiempo lease default:" $LEASE_DEFAULT
    Write-Host "Tiempo lease maximo:" $LEASE_MAX
}

# ======================
# MONITOREO
# ======================

function Estado-DHCP {
    Write-Host "Estado del servicio DHCP"
    Get-Service DHCPServer

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        foreach ($scope in $scopes) {
            Write-Host ""
            Write-Host "Rango actual:" $scope.ScopeId
            Get-DhcpServerv4Lease -ScopeId $scope.ScopeId |
            Select-Object IPAddress, HostName, ClientId, AddressState
        }
    } else { Write-Host "No rangos configurados" }
}

# ======================
# REINICIO Y RESET
# ======================

function Reset-DHCP {
    Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
    Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

    Restart-Service DHCPServer
    Write-Host "Proceso de reset completado"
}

# ======================
# MENU PRINCIPAL
# ======================

switch ($accion) {
    "verificar" { Comprobar-DHCP }
    "instalar" { Instalar-DHCP }
    "configurar" { Configurar-DHCP }
    "monitoreo" { Estado-DHCP }
    "reset" { Reset-DHCP }
    default {
        Write-Host "Comandos disponibles:"
        Write-Host ".\fdhcp.ps1 verificar"
        Write-Host ".\fdhcp.ps1 instalar"
        Write-Host ".\fdhcp.ps1 configurar"
        Write-Host ".\fdhcp.ps1 monitoreo"
        Write-Host ".\fdhcp.ps1 reset"
    }
}
