# Inspect HTML structure + retry failed custom sites
$ErrorActionPreference = "SilentlyContinue"
$h = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
}

function Show-JobLinks {
    param($name, $url, $pattern)
    try {
        $r    = Invoke-WebRequest -Uri $url -Headers $h -TimeoutSec 15 -UseBasicParsing
        $html = $r.Content
        $m    = [regex]::Matches($html, $pattern)
        Write-Host "--- $name ($($m.Count) matches) ---"
        $m | Select-Object -First 3 | ForEach-Object { Write-Host "  $($_.Value)" }
    } catch {
        Write-Host "--- $name  ERR: $($_.Exception.Message.Split([char]10)[0]) ---"
    }
}

function Retry-Url {
    param($name, $url)
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $h -TimeoutSec 15 -UseBasicParsing
        Write-Host "OK  $name  status=$($r.StatusCode)  len=$($r.Content.Length)"
    } catch {
        Write-Host "ERR $name  $($_.Exception.Message.Split([char]10)[0])"
    }
}

Write-Host "=== RETRY FAILED CUSTOM SITES ==="
Retry-Url "Latham (alt)"          "https://www.lwcareers.com/en/search-results?keywords=library"
Retry-Url "Jones Day (base)"      "https://www.jonesday.com/en/careers"
Retry-Url "Baker Mck (alt)"       "https://www.bakermckenzie.com/en/careers"
Retry-Url "Davis Polk (alt)"      "https://www.davispolk.com/careers/job-search"
Retry-Url "Proskauer (main)"      "https://www.proskauer.com/careers"
Retry-Url "Arnold Porter (main)"  "https://www.arnoldporter.com/en/careers"
Retry-Url "White Case WD2"        "https://whitecase.wd2.myworkdayjobs.com/wday/cxs/whitecase/WhiteCase_External/jobs"

Write-Host ""
Write-Host "=== INSPECT WORKING CUSTOM SITES ==="
# Look for href patterns that look like job posting links
Show-JobLinks "Cravath"          "https://www.cravath.com/careers/index.html"      'href="([^"]+(?:job|career|position|opening)[^"]*)"'
Show-JobLinks "Debevoise"        "https://www.debevoise.com/careers"                'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "Gibson Dunn"      "https://www.gibsondunn.com/careers/"              'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "OMelveny"         "https://www.omm.com/careers/"                     'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "Covington"        "https://www.cov.com/en/careers"                   'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "Greenberg Traurig" "https://www.gtlaw.com/en/careers"                'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "Cahill"           "https://www.cahill.com/careers"                   'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'
Show-JobLinks "Cadwalader"       "https://www.cadwalader.com/careers/"              'href="([^"]+(?:job|career|position|opening|apply)[^"]*)"'

Write-Host ""
Write-Host "=== INSPECT iCIMS SAMPLE ==="
# Check what job link patterns iCIMS returns
try {
    $r = Invoke-WebRequest -Uri "https://careers-sidley.icims.com/jobs/search?ss=1&searchKeyword=library&in_iframe=1" -Headers $h -TimeoutSec 15 -UseBasicParsing
    $m = [regex]::Matches($r.Content, 'href="([^"]*icims[^"]*(?:job|jobs)[^"]*)"')
    Write-Host "--- Sidley iCIMS links ($($m.Count)) ---"
    $m | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.Value)" }
    # Also check for title patterns
    $t = [regex]::Matches($r.Content, 'iCIMS_JobTitle[^>]*>([^<]+)<')
    Write-Host "  Titles found: $($t.Count)"
    $t | Select-Object -First 3 | ForEach-Object { Write-Host "  TITLE: $($_.Groups[1].Value.Trim())" }
} catch { Write-Host "Sidley iCIMS ERR: $_" }

Write-Host ""
Write-Host "=== INSPECT TALEO SAMPLE ==="
try {
    $r = Invoke-WebRequest -Uri "https://paulweiss.taleo.net/careersection/ex/jobsearch.ftl?keyword=library" -Headers $h -TimeoutSec 15 -UseBasicParsing
    $m = [regex]::Matches($r.Content, 'href="([^"]*(?:jobdetail|ftl\?)[^"]*)"')
    Write-Host "--- Paul Weiss Taleo links ($($m.Count)) ---"
    $m | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.Value)" }
    $t = [regex]::Matches($r.Content, '<td[^>]*class="[^"]*JobTitle[^"]*"[^>]*>.*?<a[^>]*>([^<]+)<')
    Write-Host "  Titles: $($t.Count)"
    $t | Select-Object -First 3 | ForEach-Object { Write-Host "  TITLE: $($_.Groups[1].Value.Trim())" }
} catch { Write-Host "Paul Weiss Taleo ERR: $_" }
