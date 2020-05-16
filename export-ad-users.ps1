# Скрипт выгружает всех пользователей AD в csv
# Автор Афанасенко Сергей
# Последнее изменение 18/09/19

Import-Module ActiveDirectory
cls
$date = Get-Date -uformat "%Y%m%d"
$Dest = $null
$Dest = "C:\temp\powershell\export.csv"

Write-Host "Производится загрузка данных из AD. Это может занять несколько минут"

# Указать имя домена
$server = "<domain.local>"

$users = $NULL
$users = Get-ADUser -Server $server -ResultSetSize $null -Filter * -Properties SamAccountName,displayName,pwdLastSet,badPasswordTime,Company,mail,Department,Title,telephoneNumber,extensionAttribute14,Description,distinguishedName,LastlogonTimeStamp,accountExpires,whenCreated,whenChanged,Enabled,l,st,userAccountControl,State,comment,canonicalname,streetAddress,physicalDeliveryOfficeName,name

$data = @()

foreach ($user in $users)
{
		$forwardslash = $user.canonicalname.split("/")
		$ou = $null
		for($i = 0; $i -lt $forwardslash.count - 1; $i++){
			$ou += $forwardslash[$i] + "/"
		}
		
		$LastlogonTimeStamp = $null
		$pwdLastSet = $null
		$badPasswordTime = $null
		#$owner = Get-Acl "AD:\$((Get-ADUser $user).DistinguishedName)" 
		$LastlogonTimeStamp = [DateTime]::FromFileTime($user.LastlogonTimeStamp)
		$pwdLastSet = [DateTime]::FromFileTime($user.pwdLastSet)
		$badPasswordTime = [DateTime]::FromFileTime($user.badPasswordTime)
		$expirationdate = $null

		if ($user.accountExpires -eq "9223372036854775807")
		{
			$isexpired = $false
			$expirationdate = $false
		} elseif  ($user.accountExpires -eq "0")
		{
			$isexpired = $false
			$expirationdate = $false
		} else
		{
			$expirationdate = [DateTime]::FromFileTime($user.accountExpires)
			
			if ($expirationdate -ge [datetime]::now){
				$isexpired = $false
			} else {
					$isexpired = $true
			}
		}
			if ($expirationdate -ne $false){
				$expirationdatestr = $expirationdate.ToString("dd.MM.yyyy")
			} else	{
				$expirationdatestr = "(никогда)"
			}
	
	    $data += new-object psobject -Property @{
			Login=$user.SamAccountName
			ФИО = $user.displayName
			email = $user.mail
			Должность = $user.Title
			Организация = $user.Company
			Подразделение = $user.Department
			Телефон = $user.telephoneNumber
			Город = $user.l
			Область = $user.st
			Описание = $user.Description
			"Орг.единица" = $ou
			Комментарий = $user.comment
			extensionAttribute14 = $user.extensionAttribute14
			"Уз включена" = $user.Enabled
			"Когда создана" = $user.whenCreated.ToString("dd.MM.yyyy hh:mm")
			Истекает = $expirationdatestr
			"Последний вход" = $LastlogonTimeStamp.ToString("dd.MM.yyyy hh:mm")
			Адрес = $user.streetAddress
			Комната = $user.physicalDeliveryOfficeName
			UAC = $user.userAccountControl
			BadPasswordTime = $badPasswordTime.ToString("dd.MM.yyyy hh:mm")
			PwdLastSet = $pwdLastSet.ToString("dd.MM.yyyy hh:mm")
			КогдаИзменена = $user.whenChanged.ToString("dd.MM.yyyy hh:mm")
			Создатель = $owner.owner
			SID = $user.SID
			"Object GUID" = $user.ObjectGUID
			"Имя объекта" = $user.Name
			} | select Login,ФИО,email,Должность,Организация,Подразделение,Телефон,Город,Область,Описание,"Орг.единица",Комментарий,extensionAttribute14,"Уз включена","Когда cоздана",Истекает,"Последний вход",Адрес,Комната,UAC,BadPasswordTime,PwdLastSet,"Когда изменена",Создатель,SID,"Object GUID","Имя объекта"
}

Write-Host "Выгрузка в файл: " $Dest
$data | Export-Csv $Dest -Append -NoTypeInformation -Encoding utf8 -Delimiter ";"
Write-Host "Готово"