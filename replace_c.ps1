$file = 'c:\Users\sheha\Desktop\i_connect\lib\screens\admin\assign_engineer_sheet.dart'
$text = [System.IO.File]::ReadAllText($file)

# Replace all _C references with Brand equivalents
$replacements = @{
    '_C.darkBg'        = 'Brand.darkBg'
    '_C.darkCard'      = 'Brand.darkCard'
    '_C.darkCardElev'  = 'Brand.darkCardElevated'
    '_C.darkBorder'    = 'Brand.darkBorder'
    '_C.darkBorderLt'  = 'Brand.darkBorderLight'
    '_C.darkTextPri'   = 'Brand.darkTextPrimary'
    '_C.darkTextSec'   = 'Brand.darkTextSecondary'
    '_C.lightGreen'    = 'Brand.lightGreen'
    '_C.lightGreenDark'= 'Brand.lightGreenDark'
    '_C.royalBlue'     = 'Brand.royalBlue'
    '_C.royalBlueLight'= 'Brand.royalBlueLight'
}

foreach ($k in $replacements.Keys) {
    $v = $replacements[$k]
    $text = $text -replace [Regex]::Escape($k), $v
}

[System.IO.File]::WriteAllText($file, $text)
Write-Host "Done: Replaced all _C references in assign_engineer_sheet.dart"
