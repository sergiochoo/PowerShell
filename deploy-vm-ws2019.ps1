# Скрипт разворачивает ВМ с заданными параметрами и настраивает ОС // только для Windows Server 2019
# Автор Афанасенко Сергей
# Последнее изменение 15/05/20

# Общие параметры
$joindomainaccount = "JoinDomainUser"  # УЗ без прав в домене
$dc = "DC"                             # КД
$templateName = 'WinSrv2019'           # Имя шаблона
$customizationName = 'WinSrv2019'      # Имя кастомизации
$ifname = "Ethernet0"
$now = Get-Date -UFormat "%d %b %Y"
$me = $env:USERNAME
$start = [datetime]::Now

# Параметры ВМ
$servername = "Servername"  # задать имя сервера
$serverpath = "OU=Servers,DC=domain,DC=local" Указать DN для, где создавать УЗ компьютера

$CPU = '8'                                       # количество ядер
$MEM = '16'                                      # количество Гб памяти
$hard2 =''                                       # Если нужен дополнительный диск - вписать требуемое количество Гб
$hard3 =''                                       # либо оставить '' если диск не нужен.
$hard4 =''                                       #
$ipaddress = "10.0.0.100"                        # указать IP
$nm = "255.255.255.0"                            # указать маску подсети
$gw = "10.0.0.1"                                 # шлюз
$vlan = 'Vlan100'                                # vlan
$zni = "1234"                                    # вписать номер ЗнИ
$owner = "Иванов И.И."                           # ответственный согласно ЗнИ

# Дополнительные компоненты - отметить 1, если нужно установить
$netfx35 = '0'                # установить .NET Framework 3.5
$iis     = '0'                # установить Internet Information Server
$rds     = '0'                # установить службу RDS connection host + licencing

# Параметры логгирования
$logfile = ".\Logs\"+$servername+"_$(get-date -Format yyyyddmm_hhmmtt).log"

# Расскомментировать нужное значение имени кластера
#$cluster = 'CLUSTER1'
 $cluster = 'CLUSTER2'

# Папка в VCenter, куда кидать ВМ
$subfolder = "TEST"
#$subfolder = "PROD"

# Подпапка
$subSubfolder = "MICROSOFT HOSTS"
#$subSubfolder = "Some Project"

# Запрос пароля локального администратора сервера в шаблоне
$pass = Read-Host "Ввести пароль администратора сервера" -AsSecureString

cls
Start-Transcript -Path $Logfile
Get-Date -UFormat %H:%M:%S
Write-Host "PowerCli module is loading" -ForegroundColor Green
& 'c:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1'
Connect-VIServer vcsa.domain.local  # Указать имя VCenter-a

# Начинаем
Get-Date -UFormat %H:%M:%S

# Проверка на количество символов в имени сервера
if ($servername.length -gt 15) {
    Write-Output "х Количество символов в имени сервера превышает 15 символов"
    Exit
}

Write-Host "Начинаем установку" -ForegroundColor Green

# Создаем учетку в AD
New-ADComputer -Name $servername -SAMAccountName $servername -Path $serverpath

sleep 15

# Назначаем права для УЗ JoinDomainUser на ввод в домен
$serverdn = Get-ADComputer $servername | select -ExpandProperty DistinguishedName
$ADSI = [ADSI]"LDAP://$serverdn"

$NTAccount = New-Object System.Security.Principal.NTAccount($joindomainaccount)
$IdentityReference = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])

# права на запись DNS host name
$writetodns = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,'Self', 'Allow', '72e39547-7b18-11d1-adef-00c04fd8d5cd', 'None', 'bf967a86-0de6-11d0-a285-00aa003049e2')
$ADSI.psbase.ObjectSecurity.SetAccessRule($writetodns)
# права на запись запись service principal name
$writetospn = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,'Self', 'Allow', 'f3a64788-5306-11d1-a9c5-0000f80367c1', 'None', 'bf967a86-0de6-11d0-a285-00aa003049e2')
$ADSI.psbase.ObjectSecurity.AddAccessRule($writetospn)
# права на запись Account Restrictions
$writeaccperm = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,'ReadProperty, WriteProperty','Allow','4c164200-20c0-11d0-a768-00aa006e0529','None','bf967a86-0de6-11d0-a285-00aa003049e2')
$ADSI.psbase.ObjectSecurity.AddAccessRule($writeaccperm)
# права на сброс пароля
$resetpasswd = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,'ExtendedRight','Allow','00299570-246d-11d0-a768-00aa006e0529','None','bf967a86-0de6-11d0-a285-00aa003049e2')
$ADSI.psbase.ObjectSecurity.AddAccessRule($resetpasswd)
# права на создание и удаление объектов типа "компьютер"
$createdeleteobj = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,'CreateChild, DeleteChild','Allow','bf967a86-0de6-11d0-a285-00aa003049e2','All',[guid]::Empty)
$ADSI.psbase.ObjectSecurity.AddAccessRule($createdeleteobj)
$ADSI.psbase.commitchanges()

# Получаем значения переменных
# путь к папке
$folder = Get-Folder -Name $SubSubfolder -Location $Subfolder

# Имя шаблона
$template = Get-Template -Name $templateName

# Имя спецификации
$customization = Get-OSCustomizationSpec -Name $customizationName

# выбираем самый незагруженный хост
$VMHost = Get-VMHost -State Connected -Location $cluster | Sort-Object -Property CPuUsageMhz -Descending:$false | Select -First 1

# выбираем самый незагруженный датастор, исключая имена, содержащие в имени "!"
$datastore = Get-Cluster -Name $cluster | `
             Get-Datastore | where {$_.ExtensionData.Summary.MultipleHostAccess} | `
             where {$_.State -eq 'Available'} | `
             where {$_.Name -notlike '*!*'} | `
             Sort-Object -Property FreespaceGB -Descending:$true | `
             Select -First 1

# Создаем ВМ на основе полученных ранее параметров
Get-Date -UFormat %H:%M:%S
Write-Host "Создаем ВМ..." -ForegroundColor Green

New-VM -Template $template `
       -Name $servername `
       -VMHost $VMHost `
       -Datastore $datastore `
       -OSCustomizationSpec $customization `
       -Location $folder `
       -DiskStorageFormat Thin | Set-VM -NumCpu $CPU -MemoryGB $MEM -Confirm:$false

Get-Date -UFormat %H:%M:%S
Write-Host "ВМ создана" -ForegroundColor Green

$VM = Get-VM -Name $servername

# проверяем, указано ли добавление дополнительного диска и если да, то добавляем
if ($hard2 -ne '') {New-HardDisk -VM $VM -StorageFormat Thin -CapacityGB $hard2}
if ($hard3 -ne '') {New-HardDisk -VM $VM -StorageFormat Thin -CapacityGB $hard3}
if ($hard4 -ne '') {New-HardDisk -VM $VM -StorageFormat Thin -CapacityGB $hard4}

# Загружаем ОС и ждем 15 минут пока отработает кастомизация

Start-VM -VM $vm -Confirm:$false -runAsync | Out-Null
Get-Date -UFormat %H:%M:%S
Write-Host "Запуск ВМ $servername" -ForegroundColor Yellow
Start-Sleep -Seconds 900;

# Обновляем VMWare Tools и перезагружаем ВМ
Get-Date -UFormat %H:%M:%S
Write-Host "Обновляем VMWare Tools и перезагружаем ВМ" -ForegroundColor Green
$VM | Update-Tools

Start-Sleep -Seconds 300;

Get-Date -UFormat %H:%M:%S
Write-Host "ВМ запущена" -ForegroundColor Green

# Создаем обязательные группы в AD
New-ADGroup -Name "G001TSU-$servername" -SamAccountName "G001TSU-$servername" -GroupCategory Security -GroupScope DomainLocal `
            -Path "OU=Служебные группы,DC=domain,DC=local" `
            -Description "Группа пользователей удаленного рабочего стола на сервере $servername; #$zni; $owner"
New-ADGroup -Name "G001TSA-$servername" -SamAccountName "G001TSA-$servername" -GroupCategory Security -GroupScope DomainLocal `
            -Path "OU=Служебные группы,DC=domain,DC=local" `
            -Description "Группа администраторов на сервере $servername; #$zni; $owner"

# Настройка ОС и установка софта
# Отключаем фаервол и службу Computer Browser
Get-Date -UFormat %H:%M:%S
Write-Host "Отключаем фаервол и службу Computer Browser"  -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Set-NetFirewallProfile * -Enabled False" -GuestUser $servername\Administrator -GuestPassword $pass

# Устанавливаем Telnet client
Get-Date -UFormat %H:%M:%S
Write-Host "Устанавливаем Telnet client" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Install-WindowsFeature -name Telnet-Client" -GuestUser $servername\Administrator -GuestPassword $pass

# Устанавливаем IIS
if ($iis -eq '1') {
Get-Date -UFormat %H:%M:%S
Write-Host "Устанавливаем IIS" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Install-WindowsFeature -name 'Web-Server' -IncludeManagementTools" -GuestUser $servername\Administrator -GuestPassword $pass
}

# Устанавливаем RDS Host
if ($rds -eq '1') {
Get-Date -UFormat %H:%M:%S
Write-Host "Устанавливаем RDS Host" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Install-WindowsFeature RDS-RD-Server, RSAT-RDS-Tools, RDS-Licensing, RSAT-RDS-Licensing-Diagnosis-UI" -GuestUser $servername\Administrator -GuestPassword $pass
}

# Устанавливаем .NET Framework 3.5
if ($netfx35 -eq '1') {
Get-Date -UFormat %H:%M:%S
Write-Host "Устанавливаем .NET Framework 3.5" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "DISM /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:\\someFSserver\Distros4newServers\sxs\2019_en" -GuestUser $servername\Administrator -GuestPassword $pass
}

# Скрываемся из обозревателя компьютеров
Get-Date -UFormat %H:%M:%S
Write-Host "Скрываемся из обозревателя компьютеров" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText 'net config server /hidden:yes' -GuestUser "$servername\Administrator" -GuestPassword $pass

# Установка антивируса
Get-Date -UFormat %H:%M:%S
Write-Host "Установка антивируса" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText 'msiexec.exe -i "\\someFSserver\Distros4newServers\ESET\efsw4.5xml_nt64.msi" /qb! /L*v "c:\windows\temp\eset.txt" REBOOT="ReallySupress"' -GuestUser "$servername\Administrator" -GuestPassword $pass

# Установка клиента SCCM
Get-Date -UFormat %H:%M:%S
Write-Host "Установка клиента SCCM" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText '"\\someFSserver\Distros4newServers\SCCM\ccmsetup.exe"' -GuestUser "$servername\Administrator" -GuestPassword $pass

# Добавляем группы доступа
Get-Date -UFormat %H:%M:%S
Write-Host "Добавляем группы доступа" -ForegroundColor Green
$grouptsa = "domain\G001TSA-$servername"
$grouptsu = "domain\G001TSU-$servername"
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Add-LocalGroupMember -Group Administrators -Member $grouptsa" -GuestUser $servername\Administrator -GuestPassword $pass
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $grouptsu" -GuestUser $servername\Administrator -GuestPassword $pass

# Установка обновлений
Get-Date -UFormat %H:%M:%S
Write-Host "Установка последних обновлений" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText 'wusa.exe "\\someFSserver\Distros4newServers\Updates\2019\windows10.0-kb4549947.msu" /quiet /norestart' -GuestUser "$servername\Administrator" -GuestPassword $pass
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText 'wusa.exe "\\someFSserver\Distros4newServers\Updates\2019\windows10.0-kb4549949.msu" /quiet /norestart' -GuestUser "$servername\Administrator" -GuestPassword $pass

# Установка агента SCOM-а
Get-Date -UFormat %H:%M:%S
Write-Host "Установка агента SCOM" -ForegroundColor Green
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText 'msiexec.exe /i \\someFSserver\Distros4newServers\SCOM\MOMAgent.msi /qn /l*v %temp%\OMAgentinstall.log USE_SETTINGS_FROM_AD=0 MANAGEMENT_GROUP=001-MG1 MANAGEMENT_SERVER_DNS=scom.domain.local MANAGEMENT_SERVER_AD_NAME=scom.domain.local ACTIONS_USE_COMPUTER_ACCOUNT=1 USE_MANUALLY_SPECIFIED_SETTINGS=1 AcceptEndUserLicenseAgreement=1' -GuestUser "$servername\Administrator" -GuestPassword $pass

# Меняем буквы диска и размечаем новый диск, если есть
Get-Date -UFormat %H:%M:%S
Write-Host "Замена буквы диска" -ForegroundColor Green
# Замена буквы CD-ROM-а
$cdromletter = @"
Get-WmiObject -Class Win32_Volume -Filter "DriveLetter = 'D:'" |
Set-WmiInstance -Arguments @{DriveLetter="Q:"; Label="Label"}
"@
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText $cdromletter -GuestUser $servername\Administrator -GuestPassword $pass

sleep 10
# Инициализация дополнительных дисков
if ($hard2 -ne '') {
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Get-Disk | Where partitionstyle -eq 'raw' | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data'" -GuestUser $servername\Administrator -GuestPassword $pass
}
if ($hard3 -ne '') {
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Get-Disk | Where partitionstyle -eq 'raw' | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data'" -GuestUser $servername\Administrator -GuestPassword $pass
}
if ($hard4 -ne '') {
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Get-Disk | Where partitionstyle -eq 'raw' | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Data'" -GuestUser $servername\Administrator -GuestPassword $pass
}
# Замена IP адреса
Get-Date -UFormat %H:%M:%S

Write-Host "Замена IP адреса" -ForegroundColor Green
$VM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $vlan -Confirm:$False
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Get-NetAdapter -InterfaceIndex 3 | Rename-NetAdapter -NewName Ethernet0" -GuestUser $servername\Administrator -GuestPassword $pass
Invoke-VMScript -VM $VM -ScriptType bat -ScriptText "netsh interface ipv4 set address name=$ifname static $ipaddress $nm $gw" -GuestUser $servername\Administrator -GuestPassword $pass
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText "Set-DnsClientServerAddress -InterfaceIndex 3 -ServerAddresses 10.0.0.2, 10.0.0.3" -GuestUser $servername\Administrator -GuestPassword $pass

# Отключаем NetBIOS over TCPIP
$disableNBoTCP = @'
    $adapters = (gwmi win32_networkadapterconfiguration)
    foreach ($adapter in $adapters)
        {
        $adapter.settcpipnetbios(2)
        }
'@
Invoke-VMScript -VM $VM -ScriptType Powershell -ScriptText $disableNBoTCP -GuestUser $servername\Administrator -GuestPassword $pass

# Добавляем описание ВМ в VCenter
Get-Date -UFormat %H:%M:%S
Write-Host "Добавляем описание ВМ в VCenter" -ForegroundColor Green
$notes = "$now / $me / $zni"
$VM | Set-VM -Notes $notes -Confirm:$False

Get-Date -UFormat %H:%M:%S
Write-Host "Работы закончены" -ForegroundColor Green
$stop = [datetime]::Now
$runTime = New-TimeSpan $start $stop
Write-Output "Время работы скрипта: $runtime"
Stop-Transcript