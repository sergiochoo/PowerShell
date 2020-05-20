# Сергей Афанасенко 20/05/2020
# Скрипт импортирует данные для заполнения из CSV-файла.
# Файл CSV должен быть формата DOS (с ";" в качестве разделителя)
# Столбцы, которые забираются из файла:
# GroupName	 ResourceName	Owner	Order
# 

cls
$groups = import-csv -Path $PSScriptRoot\change.csv -Encoding OEM -Delimiter ";"

ForEach ($group in $groups){
                $NewDescription = $group.Owner + "; " + $group.Order; Get-AdGroup $group.GroupName | `
                Set-ADGroup -Description $NewDescription -Replace @{info=$group.ResourceName}
                }