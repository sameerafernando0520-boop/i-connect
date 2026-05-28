# PowerShell script to batch replace .withOpacity() with .withAlpha()

$opacityMap = @{
    '0.01'  = '3'
    '0.015' = '4'
    '0.025' = '6'
    '0.03'  = '8'
    '0.04'  = '10'
    '0.05'  = '13'
    '0.06'  = '15'
    '0.07'  = '18'
    '0.08'  = '20'
    '0.1'   = '26'
    '0.12'  = '31'
    '0.15'  = '38'
    '0.18'  = '46'
    '0.2'   = '51'
    '0.25'  = '64'
    '0.3'   = '77'
    '0.35'  = '89'
    '0.4'   = '102'
    '0.45'  = '115'
    '0.5'   = '128'
    '0.55'  = '140'
    '0.6'   = '153'
    '0.7'   = '179'
    '0.8'   = '204'
    '0.9'   = '230'
}

$screensDir = 'c:\Users\sheha\Desktop\i_connect\lib\screens'
$dartFiles = Get-ChildItem -Path $screensDir -Filter '*.dart' -Recurse
$totalReplacements = 0
$filesModified = 0

foreach ($file in $dartFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $originalContent = $content
    
    # Replace fixed opacity values
    foreach ($opacity in $opacityMap.Keys) {
        $alpha = $opacityMap[$opacity]
        $escapedOpacity = [Regex]::Escape($opacity)
        
        # Handle dynamic opacity: isDark ? 0.XX : 0.YY
        $pattern = "\.withOpacity\(isDark \? $escapedOpacity :"
        $replacement = ".withAlpha(isDark ? $alpha :"
        $content = $content -replace $pattern, $replacement
        
        # Handle: 0.XX) format
        $pattern = ": $escapedOpacity\)"
        $replacement = ": $alpha)"
        $content = $content -replace $pattern, $replacement
        
        # Handle fixed values
        $pattern = "\.withOpacity\($escapedOpacity\)"
        $replacement = ".withAlpha($alpha)"
        $content = $content -replace $pattern, $replacement
    }
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content
        $filesModified++
        $originalMatches = [Regex]::Matches($originalContent, '\.withOpacity\(')
        $totalReplacements += $originalMatches.Count
        Write-Host "✓ $(Split-Path -Leaf $file.FullName): $($originalMatches.Count) replacements" -ForegroundColor Green
    }
}

Write-Host "`n✓ Batch conversion complete!" -ForegroundColor Green
Write-Host "  Files modified: $filesModified" -ForegroundColor Green
Write-Host "  Total replacements: $totalReplacements" -ForegroundColor Green
