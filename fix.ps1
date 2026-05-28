$map = @{"0.01"="3";"0.015"="4";"0.025"="6";"0.03"="8";"0.04"="10";"0.05"="13";"0.06"="15";"0.07"="18";"0.08"="20";"0.1"="26";"0.12"="31";"0.15"="38";"0.18"="46";"0.2"="51";"0.25"="64";"0.3"="77";"0.35"="89";"0.4"="102";"0.45"="115";"0.5"="128";"0.55"="140";"0.6"="153";"0.7"="179";"0.8"="204";"0.9"="230"}

$files = Get-ChildItem 'c:\Users\sheha\Desktop\i_connect\lib\screens' -Filter '*.dart' -Recurse
$count = 0

foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $new = $text
    
    foreach ($k in $map.Keys) {
        $v = $map[$k]
        $new = $new -replace "\.withOpacity\($k\)", ".withAlpha($v)"
    }
    
    if ($new -ne $text) {
        [System.IO.File]::WriteAllText($file.FullName, $new)
        Write-Host $file.Name
        $count++
    }
}

Write-Host "`nDone: Modified $count files"
