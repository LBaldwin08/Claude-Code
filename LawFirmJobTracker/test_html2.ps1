$ErrorActionPreference = "SilentlyContinue"
$h = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
}
$jh = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'     = 'application/json, text/plain, */*'
}

function Snip { param($html, $pattern, $label, $n=3)
    $m = [regex]::Matches($html, $pattern)
    Write-Host "$label ($($m.Count) matches):"
    $m | Select-Object -First $n | ForEach-Object { Write-Host "  $($_.Value.Substring(0, [Math]::Min(120, $_.Value.Length)))" }
}

# ---- iCIMS: try non-iframe URL and look for job id/title patterns ----
Write-Host "=== iCIMS Sidley (non-iframe, keyword=research) ==="
try {
    $r = Invoke-WebRequest -Uri "https://careers-sidley.icims.com/jobs/search?ss=1&searchKeyword=research" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="[^"]*icims[^"]*jobs/\d+[^"]*"' "Job href links"
    Snip $r.Content '"job-title"[^>]*>([^<]{5,80})<' "job-title spans"
    Snip $r.Content 'data-job-id="(\d+)"' "data-job-id attrs"
    Snip $r.Content '/jobs/(\d+)/[^"]+/job' "job URL paths"
} catch { Write-Host "ERR: $_" }

# ---- iCIMS: try JSON feed ----
Write-Host ""
Write-Host "=== iCIMS Sidley JSON feed ==="
try {
    $r = Invoke-WebRequest -Uri "https://careers-sidley.icims.com/jobs/search?ss=1&searchKeyword=research&outputtype=json" -Headers $jh -TimeoutSec 10 -UseBasicParsing
    Write-Host "Status: $($r.StatusCode)  Len: $($r.Content.Length)"
    Write-Host $r.Content.Substring(0, [Math]::Min(500, $r.Content.Length))
} catch { Write-Host "ERR JSON: $_" }

# ---- iCIMS Milbank (different subdomain pattern) ----
Write-Host ""
Write-Host "=== iCIMS Milbank (keyword=research) ==="
try {
    $r = Invoke-WebRequest -Uri "https://careers-milbank.icims.com/jobs/search?ss=1&searchKeyword=research" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content '/jobs/\d+/[^"]+/job' "job URL paths"
    Snip $r.Content 'iCIMS_JobTitle[^>]*>\s*<[^>]+>([^<]{5,80})' "iCIMS_JobTitle"
} catch { Write-Host "ERR: $_" }

# ---- Taleo: check for JS data or alternate endpoints ----
Write-Host ""
Write-Host "=== Taleo Paul Weiss (check for embedded JSON) ==="
try {
    $r = Invoke-WebRequest -Uri "https://paulweiss.taleo.net/careersection/ex/jobsearch.ftl?keyword=research" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content '"jobs"\s*:\s*\[' "JSON jobs array"
    Snip $r.Content 'ftl\?job=\d+' "Taleo job links"
    Snip $r.Content '"title"\s*:\s*"([^"]{5,80})"' "JSON titles"
    Snip $r.Content 'careersection[^"]*jobdetail[^"]*' "jobdetail links"
    # Check first 2000 chars for structure clues
    Write-Host "Page snippet:"
    Write-Host $r.Content.Substring(0, [Math]::Min(1000, $r.Content.Length))
} catch { Write-Host "ERR: $_" }

# ---- Cravath: inspect full page for job links ----
Write-Host ""
Write-Host "=== Cravath full scan ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.cravath.com/careers/index.html" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy)[^"]{0,60})"' "job-like links"
    Snip $r.Content '"url"\s*:\s*"([^"]+)"' "JSON urls"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters' "ATS references"
} catch { Write-Host "ERR: $_" }

# ---- Cahill: inspect for job listings ----
Write-Host ""
Write-Host "=== Cahill ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.cahill.com/careers" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy|careers)[^"]{0,60})"' "job-like links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters' "ATS references"
    Write-Host "Full HTML snippet:"
    Write-Host $r.Content.Substring(0, [Math]::Min(2000, $r.Content.Length))
} catch { Write-Host "ERR: $_" }

# ---- Jones Day: check base page ----
Write-Host ""
Write-Host "=== Jones Day ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.jonesday.com/en/careers" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy)[^"]{0,60})"' "job-like links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS references"
    Snip $r.Content 'api[^"]{0,60}job[^"]{0,60}"' "API endpoints"
} catch { Write-Host "ERR: $_" }

# ---- Proskauer: check main careers page ----
Write-Host ""
Write-Host "=== Proskauer ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.proskauer.com/careers" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy)[^"]{0,60})"' "job-like links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS references"
    Snip $r.Content 'api[^"]{0,60}(?:job|career)[^"]{0,60}"' "API endpoints"
} catch { Write-Host "ERR: $_" }

# ---- Arnold Porter ----
Write-Host ""
Write-Host "=== Arnold Porter ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.arnoldporter.com/en/careers" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy)[^"]{0,60})"' "job-like links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS references"
    Snip $r.Content 'api[^"]{0,60}(?:job|career)[^"]{0,60}"' "API endpoints"
} catch { Write-Host "ERR: $_" }

# ---- Cadwalader: may have direct staff job list ----
Write-Host ""
Write-Host "=== Cadwalader (staff jobs) ==="
try {
    $r = Invoke-WebRequest -Uri "https://www.cadwalader.com/careers/" -Headers $h -TimeoutSec 15 -UseBasicParsing
    Snip $r.Content 'href="([^"]{10,}(?:open|position|job|vacancy|careers)[^"]{0,80})"' "job-like links"
    Snip $r.Content 'greenhouse|lever|icims|workday|taleo|jobvite|smartrecruiters|brassring' "ATS references"
} catch { Write-Host "ERR: $_" }
