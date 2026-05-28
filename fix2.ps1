$map = @{
    '0.01' = '3'
    '0.015' = '4'
    '0.025' = '6'
    '0.03' = '8'
    '0.04' = '10'
    '0.05' = '13'
    '0.06' = '15'
    '0.07' = '18'
    '0.08' = '20'
    '0.1' = '26'
    '0.11' = '28'
    '0.12' = '31'
    '0.13' = '33'
    '0.14' = '36'
    '0.15' = '38'
    '0.16' = '41'
    '0.17' = '43'
    '0.18' = '46'
    '0.19' = '48'
    '0.2' = '51'
    '0.22' = '56'
    '0.23' = '59'
    '0.24' = '61'
    '0.25' = '64'
    '0.26' = '66'
    '0.27' = '69'
    '0.28' = '71'
    '0.29' = '74'
    '0.3' = '77'
    '0.32' = '82'
    '0.33' = '84'
    '0.35' = '89'
    '0.37' = '94'
    '0.38' = '97'
    '0.4' = '102'
    '0.42' = '107'
    '0.43' = '110'
    '0.45' = '115'
    '0.46' = '117'
    '0.48' = '122'
    '0.5' = '128'
    '0.52' = '133'
    '0.54' = '138'
    '0.55' = '140'
    '0.56' = '143'
    '0.57' = '145'
    '0.58' = '148'
    '0.59' = '150'
    '0.6' = '153'
    '0.62' = '158'
    '0.63' = '161'
    '0.65' = '166'
    '0.66' = '168'
    '0.67' = '171'
    '0.68' = '174'
    '0.7' = '179'
    '0.72' = '184'
    '0.73' = '186'
    '0.75' = '191'
    '0.8' = '204'
    '0.85' = '217'
    '0.9' = '230'
    '0.92' = '235'
}

$files = Get-ChildItem 'c:\Users\sheha\Desktop\i_connect\lib\screens' -Filter '*.dart' -Recurse
$count = 0

foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $newText = $text
    
    # Process all opacities
    foreach ($k in $map.Keys) {
        $v = $map[$k]
        # Escape for regex and replace all occurrences
        $pattern = [Regex]::Escape("withOpacity($k)")
        $replacement = "withAlpha($v)"
        $newText = $newText -replace $pattern, $replacement
    }
    
    if ($newText -ne $text) {
        [System.IO.File]::WriteAllText($file.FullName, $newText)
        $count++
    }
}

Write-Host "Modified $count files"
