# Скрипт проверяет срок действия паролей пользователей в группе, и если он скоро истекает, 
# то высылает письмо руководителю такого пользователя за 14, 10 и 3 дней до блокировки УЗ.
# Автор Афанасенко Сергей
# Последнее изменение 08/10/19

cls
$start = [datetime]::Now
$today = $start
$textEncoding = [System.Text.Encoding]::UTF8
$expired = Get-ADUser -filter "enabled -eq '$true' -and mail -like '*' "`
                    -Properties Name, Mail, PasswordNeverExpires, distinguishedName, `
                                memberof, PasswordExpired, PasswordLastSet, EmailAddress, manager, company `
                    -SearchBase "OU=Company,DC=domain,DC=local" | `
           where { 
                ($_.passwordexpired -eq $false) `
                -and ($_.PasswordNeverExpires -ne '$True') `
                -and $((get-adgroup -identity 'G001GG-Пользователи без ПК').distinguishedname -in $_.memberof) `
               }

ForEach ($user in $expired) {
$maxPasswordAge = 90
$interval = 3, 10, 15
$pwdLastSet = $user.PasswordLastSet
$expireson = $pwdLastSet.AddDays($maxPasswordAge)
$daysToExpire = New-TimeSpan -Start $today -End $Expireson
$manager = Get-aduser $user.Manager -Properties mail
$username = $user.Name
$usercompany = $user.company
$managername = $manager.Name
$managermail = $manager.Mail
$body = "
    <font face=""verdana"">
    Уважаемый $managername,
    <p> Для Вашего удобства напоминаем, что срок действия пароля учетной записи $username ($usercompany) для входа в корпоративную сеть истекает $expireson МСК.<br>
    Пожалуйста, заранее обеспечьте смену пароля учетной записи во избежание блокировки доступа к корпоративным ресурсам, которые в том числе доступны с мобильных устройств.<br>
    <p>Для смены пароля учетной записи:<br>
    1. С корпоративного компьютера или ноутбука нажмите клавиши Ctrl-Alt-Del, затем нажмите <Смена пароля><br>
    2. Если отсутствует доступ в сеть domain обратитесь в техническую поддержку по телефону +7(495) 000-00-00, доб. 35-55.<br>
    <p>Срок действия пароля учетной записи – 90 дней. Периодическая смена паролей помогает защитить Вашу информацию.<br>
    </P>
	Работаем, превышая ожидания.<br>
    Ваши Информационные технологии.
    </P>
    ---------------<br>
    Данное письмо сгенерировано автоматически. Пожалуйста, не отвечайте на него.
    </font>"
if (($manager.mail) -and ($daysToExpire.Days -in $interval))
{ Send-MailMessage -From PassExpNotifier@domain.ru -To $managermail -SmtpServer smtp.domain.local -Subject "Истекает срок действия пароля учетной записи подчиненного" -body $body -bodyasHTML -priority High -Encoding $textEncoding } }
$stop = [datetime]::Now
$runTime = New-TimeSpan $start $stop
Write-Output "Время работы скрипта: $runtime"