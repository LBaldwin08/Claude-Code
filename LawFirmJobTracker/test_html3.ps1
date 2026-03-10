$ErrorActionPreference = "SilentlyContinue"
$h = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
}
$mh = @{
    'User-Agent'      = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15A372 Safari/604.1'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
}

function Snip { param($html, $pattern, $label, $n=4)
    $m = [regex]::Matches($html, $pattern)
    Write-Host "$label ($($m.Count) matches):"
    $m | Select-Object -First $n | ForEach-Object { Write-Host "  $($_.Value.Substring(0,[Math]::Min(150,$_.Value.Length)))" }
}

# ---- iCIMS: try mobile=true which skips iframe wrapper ----
Write-Host "=== iCIMS Milbank mobile=true keyword=research ==="
try {
    $url = "https://careers-milbank.icims.com/jobs/search?ss=1&searchKeyword=research&mobile=true&needsRedirect=false&hashed=-435739606"
    $r = Invoke-WebRequest -Uri $url -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content '/jobs/\d+/[^"]+/job' "job URL paths"
    Snip $r.Content 'iCIMS_JobTitle[^>]*>\s*(?:<[^>]+>)*([^<]{5,80})' "iCIMS_JobTitle"
    Snip $r.Content '"job-title"[^>]*>\s*([^<]{5,80})' "job-title divs"
    Snip $r.Content '<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([^<]+)' "h2 job links"
} catch { Write-Host "ERR: $_" }

Write-Host ""
Write-Host "=== iCIMS Willkie mobile=true keyword=research ==="
try {
    $url = "https://uscareers-willkie.icims.com/jobs/search?ss=1&searchKeyword=research&mobile=true&needsRedirect=false&hashed=-435739606"
    $r = Invoke-WebRequest -Uri $url -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content '/jobs/\d+/[^"]+/job' "job URL paths"
    Snip $r.Content 'href="([^"]*icims[^"]*)"' "icims links"
} catch { Write-Host "ERR: $_" }

# ---- Taleo: try mobile RSS/XML feed ----
Write-Host ""
Write-Host "=== Taleo Paul Weiss RSS feed ==="
try {
    $r = Invoke-WebRequest -Uri "https://paulweiss.taleo.net/careersection/ex/jobsearch.ftl?keywords=research" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'var\s+listTitle\s*=' "embedded JS var"
    Snip $r.Content '"requisitionList"\s*:\s*\[' "requisitionList"
    Snip $r.Content 'jobId":"(\d+)","title":"([^"]+)"' "JSON job objects"
    Snip $r.Content '"title":"([^"]{5,80})"' "JSON titles"
    # Scrape a chunk of the JS-heavy section
    $idx = $r.Content.IndexOf("jobId")
    if ($idx -gt 0) { Write-Host "jobId found at idx $idx"; Write-Host $r.Content.Substring($idx, [Math]::Min(500, $r.Content.Length - $idx)) }
    else { Write-Host "No jobId found in page" }
} catch { Write-Host "ERR: $_" }

# ---- Custom: try alternate staff pages ----
Write-Host ""
Write-Host "=== Jones Day business professionals ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.jonesday.com/en/careers/business-professionals" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="(/en/careers[^"]{10,80})"' "career links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring|kenexa' "ATS refs"
} catch { Write-Host "ERR: $_" }

Write-Host ""
Write-Host "=== Greenberg Traurig staff jobs ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.gtlaw.com/en/careers/staff-positions" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|staff)[^"]{0,80})"' "job links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
} catch { Write-Host "ERR: $_" }

Write-Host ""
Write-Host "=== Cadwalader staff jobs ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.cadwalader.com/careers/staff-openings" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|staff|career)[^"]{0,80})"' "job links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
    Write-Host "HTML snippet:"
    Write-Host $r.Content.Substring(0,[Math]::Min(3000,$r.Content.Length))
} catch { Write-Host "ERR: $_" }

Write-Host ""
Write-Host "=== Debevoise staff jobs ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.debevoise.com/careers/business-services-staff" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|staff|career)[^"]{0,80})"' "job links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
} catch {
    Write-Host "ERR: $($_.Exception.Message)"
    # Try the base careers URL
    try {
        $r2 = Invoke-WebRequest -Uri "https://www.debevoise.com/careers" -Headers $h -TimeoutSec 15 -UseBasicParsing
        Snip $r2.Content 'href="([^"]{10,}(?:open|position|job|staff|career)[^"]{0,80})"' "job links"
        Snip $r2.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
        Write-Host $r2.Content.Substring(0,[Math]::Min(2000,$r2.Content.Length))
    } catch { Write-Host "Base ERR: $_" }
}

Write-Host ""
Write-Host "=== O'Melveny staff jobs ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.omm.com/careers/staff-positions/" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|staff|career)[^"]{0,80})"' "job links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
} catch { Write-Host "ERR: $_" }

Write-Host ""
Write-Host "=== Covington staff jobs ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.cov.com/en/careers/business-professional" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status=$($r.StatusCode) Len=$($r.Content.Length)"
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|staff|career)[^"]{0,80})"' "job links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS refs"
} catch { Write-Host "ERR: $_" }
