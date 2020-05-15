# Скрипт настраивает новый ESXI-хост по подобию исходного хоста
# Автор Афанасенко Сергей
# Последнее изменение 23/07/19

$VISRV = Connect-VIServer vcsa.domain.local
# Исходный хост
$BASEHost = Get-VMHost -Name esxi1.domain.local
# Целевой хост
$NEWHost = Get-VMHost -Name esxi2.domain.local

# Копируем стандартные свичи
$BASEHost |Get-VirtualSwitch | foreach {
   If (($NEWHost |Get-VirtualSwitch -Name $_.Name-ErrorAction SilentlyContinue)-eq $null){
       Write-Host "Creating Virtual Switch $($_.Name)"
       $NewSwitch = $NEWHost |New-VirtualSwitch -Name $_.Name-NumPorts $_.NumPorts-Mtu $_.Mtu
       $vSwitch = $_
    }
$vSwitch = 'vSwitch0'
   $_ |Get-VirtualPortGroup | where {($_.name -notlike "VMOTION") -and ($_.name -notlike "FT") -and ($_.name -notlike "MGMT")} |Foreach {
       If (($NEWHost |Get-VirtualPortGroup -Name $_.Name-ErrorAction SilentlyContinue)-eq $null){
           Write-Host "Creating Portgroup $($_.Name)"
           $NewPortGroup = $NEWHost |Get-VirtualSwitch -Name $vSwitch |New-VirtualPortGroup -Name $_.Name-VLanId $_.VLanID
        }
    }
}

# Переименовываем управляющую сеть
$NEWHost | Get-VirtualPortGroup -Name "Management network" | Set-VirtualPortGroup -Name "MGMT"

# Настраиваем syslog
$NEWHost | Set-VMHostAdvancedConfiguration -Name Syslog.global.logHost -Value "udp://<SyslogServerIP>:514"
$NEWHost | Set-VMHostAdvancedConfiguration -Name Syslog.global.logDirUnique -Value "True"

# Переводим новых хост в режим high perfomance
$view = ($NEWHost | Get-View)
(Get-View $view.ConfigManager.PowerSystem).ConfigurePowerPolicy(1)

# Настройка NTP
$NEWHost | Add-VMHostNtpServer -NtpServer <NTP server IP>
$NEWHost | Get-VMHostService | Where-Object {$_.key -eq "ntpd" } | Start-VMHostService
$NEWHost | Get-VMHostService | Where-Object {$_.key -eq "ntpd" } | Set-VMHostService -policy "on"

# Настройка SSH
$NEWHost | Get-VMHostService | Where-Object {$_.key -eq "TSM-SSH" } | Start-VMHostService
$NEWHost | Get-VMHostService | Where-Object {$_.key -eq "TSM-SSH" } | Set-VMHostService -policy "on"

# Разрешаем SSH и syslog на фаерволе
$NEWHost | Get-VMHostFirewallException | where {$_.Name.StartsWith('SSH Server')} | Set-VMHostFirewallException -Enabled $true
$NEWHost | Get-VMHostFirewallException | where {$_.Name.StartsWith('syslog')} | Set-VMHostFirewallException -Enabled $true

# выводим Имя и SN хоста
$NEWHost | Select Name,@{N='Serial';E={(Get-EsxCli -VMHost $_).hardware.platform.get().SerialNumber}}