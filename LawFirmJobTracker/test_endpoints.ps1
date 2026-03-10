# Test all candidate ATS endpoints before adding to main script
$ErrorActionPreference = "SilentlyContinue"
$headers = @{
    'User-Agent'   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'       = 'application/json'
    'Content-Type' = 'application/json'
}
$htmlHeaders = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
}
$body = '{"appliedFacets":{},"limit":3,"offset":0,"searchText":"library"}'

function Test-Workday {
    param($name, $tenant, $instance, $site)
    $url = "https://$tenant.$instance.myworkdayjobs.com/wday/cxs/$tenant/$site/jobs"
    try {
        $r = Invoke-RestMethod -Method POST -Uri $url -Body $body -Headers $headers -TimeoutSec 10
        Write-Host "OK  [Workday] $name  total=$($r.total)  url=$url"
    } catch {
        Write-Host "ERR [Workday] $name  $($_.Exception.Message.Split([char]10)[0])  url=$url"
    }
}

function Test-ICIMS {
    param($name, $subdomain)
    $url = "https://$subdomain.icims.com/jobs/search?ss=1&searchKeyword=library&in_iframe=1"
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $htmlHeaders -TimeoutSec 10 -UseBasicParsing
        Write-Host "OK  [iCIMS]   $name  status=$($r.StatusCode)  len=$($r.Content.Length)"
    } catch {
        Write-Host "ERR [iCIMS]   $name  $($_.Exception.Message.Split([char]10)[0])"
    }
}

function Test-Taleo {
    param($name, $subdomain, $section)
    $url = "https://$subdomain.taleo.net/careersection/$section/jobsearch.ftl?keyword=library"
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $htmlHeaders -TimeoutSec 10 -UseBasicParsing
        Write-Host "OK  [Taleo]   $name  status=$($r.StatusCode)  len=$($r.Content.Length)"
    } catch {
        Write-Host "ERR [Taleo]   $name  $($_.Exception.Message.Split([char]10)[0])"
    }
}

function Test-Custom {
    param($name, $url)
    try {
        $r = Invoke-WebRequest -Uri $url -Headers $htmlHeaders -TimeoutSec 10 -UseBasicParsing
        Write-Host "OK  [Custom]  $name  status=$($r.StatusCode)  len=$($r.Content.Length)"
    } catch {
        Write-Host "ERR [Custom]  $name  $($_.Exception.Message.Split([char]10)[0])"
    }
}

Write-Host "=== WORKDAY ==="
Test-Workday "Weil Gotshal"        "weil"          "wd1"  "work_at_weil"
Test-Workday "Simpson Thacher"     "stblaw"        "wd1"  "careers"
Test-Workday "Morgan Lewis"        "morganlewis"   "wd5"  "morganlewis"
Test-Workday "DLA Piper"           "dlapiper"      "wd1"  "dlapiper"
Test-Workday "Hogan Lovells"       "hoganlovells"  "wd3"  "Search"
Test-Workday "Dechert"             "dechert"       "wd12" "DechertCareers"
Test-Workday "Sullivan Cromwell"   "cromwell"      "wd3"  "01"
Test-Workday "White Case"          "whitecase"     "wd1"  "WhiteCase_External"

Write-Host ""
Write-Host "=== iCIMS ==="
Test-ICIMS "Sidley Austin"         "careers-sidley"
Test-ICIMS "Cleary Gottlieb"       "careers-clearygottlieb"
Test-ICIMS "Willkie"               "uscareers-willkie"
Test-ICIMS "Mayer Brown"           "jobs3-mayerbrown"
Test-ICIMS "Milbank"               "careers-milbank"

Write-Host ""
Write-Host "=== TALEO ==="
Test-Taleo "Paul Weiss"            "paulweiss"    "ex"
Test-Taleo "White Case (Taleo?)"   "whitecase"    "wc_external"

Write-Host ""
Write-Host "=== CUSTOM ==="
Test-Custom "Latham Watkins"       "https://www.lwcareers.com/en"
Test-Custom "Jones Day"            "https://www.jonesday.com/en/careers/search?query=library"
Test-Custom "Baker McKenzie"       "https://careers.bakermckenzie.com/en/search-results?keywords=library"
Test-Custom "Davis Polk"           "https://www.davispolk.com/careers"
Test-Custom "Cravath"              "https://www.cravath.com/careers/index.html"
Test-Custom "Debevoise"            "https://www.debevoise.com/careers"
Test-Custom "Proskauer"            "https://jobs.proskauer.com/search/?q=library"
Test-Custom "Gibson Dunn"          "https://www.gibsondunn.com/careers/"
Test-Custom "OMelveny"             "https://www.omm.com/careers/"
Test-Custom "Arnold Porter"        "https://careers.arnoldporter.com/search/?q=library"
Test-Custom "Covington"            "https://www.cov.com/en/careers"
Test-Custom "Greenberg Traurig"    "https://www.gtlaw.com/en/careers"
Test-Custom "Cahill"               "https://www.cahill.com/careers"
Test-Custom "Cadwalader"           "https://www.cadwalader.com/careers/"
