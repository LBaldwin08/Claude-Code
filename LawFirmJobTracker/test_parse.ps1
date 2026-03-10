$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    "C:\Users\lbald\Desktop\LawFirmJobTracker\law_firm_jobs.ps1",
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count -eq 0) {
    Write-Host "No parse errors found."
} else {
    Write-Host "$($errors.Count) parse error(s):"
    foreach ($e in $errors) {
        Write-Host "  Line $($e.Extent.StartLineNumber), Col $($e.Extent.StartColumnNumber): $($e.Message)"
        Write-Host "    >> $($e.Extent.Text.Substring(0, [Math]::Min(80, $e.Extent.Text.Length)))"
    }
}
