# =============================================================================
# Law Firm Library & Research Job Tracker
# Daily newsletter for research and library positions at Skadden peer firms
# Sources: LinkedIn · AALL Job Board · Firm Career Pages · Indeed
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Net.Mail

# Load email credentials from config file
$configPath = Join-Path $PSScriptRoot "config.ps1"
if (Test-Path $configPath) { . $configPath }

# ---- CONFIGURATION ----------------------------------------------------------

$LAW_FIRMS = @(
    "Skadden Arps",
    "Latham Watkins",
    "Kirkland Ellis",
    "Sidley Austin",
    "Jones Day",
    "Baker McKenzie",
    "Weil Gotshal",
    "Paul Weiss Rifkind",
    "Davis Polk Wardwell",
    "Simpson Thacher Bartlett",
    "Cleary Gottlieb",
    "Sullivan Cromwell",
    "Cravath Swaine Moore",
    "Debevoise Plimpton",
    "Willkie Farr Gallagher",
    "Proskauer Rose",
    "White Case",
    "Gibson Dunn Crutcher",
    "OMelveny Myers",
    "Mayer Brown",
    "Dechert",
    "Arnold Porter",
    "Morgan Lewis Bockius",
    "Covington Burling",
    "Hogan Lovells",
    "DLA Piper",
    "Reed Smith",
    "Greenberg Traurig",
    "Milbank",
    "Cahill Gordon Reindel",
    "Cadwalader Wickersham Taft"
)

$FIRM_DISPLAY = @{
    "Skadden Arps"              = "Skadden, Arps, Slate, Meagher & Flom"
    "Latham Watkins"            = "Latham & Watkins"
    "Kirkland Ellis"            = "Kirkland & Ellis"
    "Sidley Austin"             = "Sidley Austin"
    "Jones Day"                 = "Jones Day"
    "Baker McKenzie"            = "Baker McKenzie"
    "Weil Gotshal"              = "Weil, Gotshal & Manges"
    "Paul Weiss Rifkind"        = "Paul, Weiss, Rifkind, Wharton & Garrison"
    "Davis Polk Wardwell"       = "Davis Polk & Wardwell"
    "Simpson Thacher Bartlett"  = "Simpson Thacher & Bartlett"
    "Cleary Gottlieb"           = "Cleary Gottlieb Steen & Hamilton"
    "Sullivan Cromwell"         = "Sullivan & Cromwell"
    "Cravath Swaine Moore"      = "Cravath, Swaine & Moore"
    "Debevoise Plimpton"        = "Debevoise & Plimpton"
    "Willkie Farr Gallagher"    = "Willkie Farr & Gallagher"
    "Proskauer Rose"            = "Proskauer Rose"
    "White Case"                = "White & Case"
    "Gibson Dunn Crutcher"      = "Gibson, Dunn & Crutcher"
    "OMelveny Myers"            = "O'Melveny & Myers"
    "Mayer Brown"               = "Mayer Brown"
    "Dechert"                   = "Dechert"
    "Arnold Porter"             = "Arnold & Porter"
    "Morgan Lewis Bockius"      = "Morgan, Lewis & Bockius"
    "Covington Burling"         = "Covington & Burling"
    "Hogan Lovells"             = "Hogan Lovells"
    "DLA Piper"                 = "DLA Piper"
    "Reed Smith"                = "Reed Smith"
    "Greenberg Traurig"         = "Greenberg Traurig"
    "Milbank"                   = "Milbank"
    "Cahill Gordon Reindel"     = "Cahill Gordon & Reindel"
    "Cadwalader Wickersham Taft"= "Cadwalader, Wickersham & Taft"
}

# Short-name lookup used to match LinkedIn/AALL company names to tracked firms
$FIRM_SHORT_NAMES = @{
    "skadden"       = "Skadden Arps"
    "latham"        = "Latham Watkins"
    "kirkland"      = "Kirkland Ellis"
    "sidley"        = "Sidley Austin"
    "jones day"     = "Jones Day"
    "baker mckenzie"= "Baker McKenzie"
    "weil"          = "Weil Gotshal"
    "paul weiss"    = "Paul Weiss Rifkind"
    "davis polk"    = "Davis Polk Wardwell"
    "simpson thacher"= "Simpson Thacher Bartlett"
    "cleary"        = "Cleary Gottlieb"
    "sullivan"      = "Sullivan Cromwell"
    "cravath"       = "Cravath Swaine Moore"
    "debevoise"     = "Debevoise Plimpton"
    "willkie"       = "Willkie Farr Gallagher"
    "proskauer"     = "Proskauer Rose"
    "white & case"  = "White Case"
    "white and case"= "White Case"
    "gibson dunn"   = "Gibson Dunn Crutcher"
    "gibson, dunn"  = "Gibson Dunn Crutcher"
    "o'melveny"     = "OMelveny Myers"
    "omelveny"      = "OMelveny Myers"
    "mayer brown"   = "Mayer Brown"
    "dechert"       = "Dechert"
    "arnold & porter"= "Arnold Porter"
    "arnold and porter"= "Arnold Porter"
    "morgan lewis"  = "Morgan Lewis Bockius"
    "covington"     = "Covington Burling"
    "hogan lovells" = "Hogan Lovells"
    "dla piper"     = "DLA Piper"
    "reed smith"    = "Reed Smith"
    "greenberg traurig"= "Greenberg Traurig"
    "milbank"       = "Milbank"
    "cahill"        = "Cahill Gordon Reindel"
    "cadwalader"    = "Cadwalader Wickersham Taft"
}

# Job title keywords — a job must match at least one
$TITLE_KEYWORDS = @(
    "librarian",
    "library",
    "research manager",
    "research director",
    "research coordinator",
    "research specialist",
    "research services",
    "knowledge management",
    "competitive intelligence",
    "information specialist",
    "information services",
    "information manager"
)

# LinkedIn search queries to run (replicates user's alert + broader library terms)
$LINKEDIN_SEARCHES = @(
    "law firm research",      # user's existing LinkedIn alert
    "law librarian",
    "legal librarian",
    "law library manager"
)

# Days back to search
$DAYS_BACK = 7

$OUTPUT_DIR = "$env:USERPROFILE\Desktop\LawFirmJobTracker\newsletters"
$LOG_FILE   = "$env:USERPROFILE\Desktop\LawFirmJobTracker\job_history.csv"

# Shared HTTP headers for web requests
$WEB_HEADERS = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
}

# ---- HELPER FUNCTIONS -------------------------------------------------------

function Write-Log {
    param($msg)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $msg"
}

function Test-RelevantTitle {
    param($title)
    $t = $title.ToLower()
    foreach ($kw in $TITLE_KEYWORDS) {
        if ($t -like "*$kw*") { return $true }
    }
    return $false
}

function Remove-HtmlTags {
    param($text)
    if (-not $text) { return "" }
    return [System.Text.RegularExpressions.Regex]::Replace($text, '<[^>]+>', '').Trim()
}

function Get-FriendlyDate {
    param($dateStr)
    if (-not $dateStr) { return "" }
    try {
        $d = [System.DateTime]::Parse($dateStr)
        return $d.ToString("MMMM dd, yyyy")
    } catch {
        return $dateStr
    }
}

# Match a company name string to a tracked firm key (returns $null if no match)
function Match-TrackedFirm {
    param($companyName)
    if (-not $companyName) { return $null }
    $comp = $companyName.ToLower()
    foreach ($shortName in ($FIRM_SHORT_NAMES.Keys | Sort-Object { $_.Length } -Descending)) {
        if ($comp -like "*$shortName*") {
            return $FIRM_SHORT_NAMES[$shortName]
        }
    }
    return $null
}

function New-JobObject {
    param($title, $link, $company, $firmKey, $pubDate, $snippet, $source, $location = "", $salary = "")
    $displayName = if ($FIRM_DISPLAY.ContainsKey($firmKey)) { $FIRM_DISPLAY[$firmKey] } else { $company }
    return [PSCustomObject]@{
        Title       = $title
        Link        = $link
        Company     = $company
        FirmKey     = $firmKey
        FirmDisplay = $displayName
        PubDate     = $pubDate
        Snippet     = $snippet
        Source      = $source
        Location    = $location
        Salary      = $salary
    }
}

# ---- JOB SOURCES ------------------------------------------------------------

function Search-LinkedIn {
    param($keywords)

    Write-Log "  [LinkedIn] '$keywords' ..."
    $jobs    = [System.Collections.Generic.Dictionary[string,object]]::new()
    $timeKey = if ($DAYS_BACK -le 1) { "r86400" } elseif ($DAYS_BACK -le 7) { "r604800" } else { "r2592000" }
    $start   = 0
    $maxJobs = 75  # 3 pages x 25

    while ($start -lt $maxJobs) {
        $encoded = [uri]::EscapeDataString($keywords)
        $url = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords=$encoded&location=United+States&geoId=103644278&f_TPR=$timeKey&start=$start&count=25"

        try {
            $headers = $WEB_HEADERS.Clone()
            $headers['Referer'] = 'https://www.linkedin.com/'
            $r    = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 20 -UseBasicParsing
            $html = $r.Content

            if ($html.Length -lt 200) { break }

            $titles    = [regex]::Matches($html, '(?s)<h3[^>]*base-search-card__title[^>]*>\s*(.*?)\s*</h3>')    | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode((Remove-HtmlTags $_.Groups[1].Value)) }
            $companies = [regex]::Matches($html, '(?s)<h4[^>]*base-search-card__subtitle[^>]*>.*?<a[^>]*>(.*?)</a>') | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode((Remove-HtmlTags $_.Groups[1].Value)) }
            $locations = [regex]::Matches($html, '(?s)<span[^>]*job-search-card__location[^>]*>\s*(.*?)\s*</span>') | ForEach-Object { $_.Groups[1].Value.Trim() }
            $dates     = [regex]::Matches($html, '<time[^>]*datetime="([^"]+)"')                                     | ForEach-Object { $_.Groups[1].Value }
            $links     = [regex]::Matches($html, 'href="(https://www\.linkedin\.com/jobs/view/[^"?]+)')              | ForEach-Object { $_.Groups[1].Value }

            if ($titles.Count -eq 0) { break }

            for ($i = 0; $i -lt $titles.Count; $i++) {
                $title   = if ($i -lt $titles.Count)    { $titles[$i] }    else { "" }
                $company = if ($i -lt $companies.Count) { $companies[$i] } else { "" }
                $loc     = if ($i -lt $locations.Count) { $locations[$i] } else { "" }
                $date    = if ($i -lt $dates.Count)     { $dates[$i] }     else { "" }
                $link    = if ($i -lt $links.Count)     { $links[$i] }     else { "" }

                if (-not $link -or $jobs.ContainsKey($link)) { continue }

                # Keep if from a tracked firm OR has a relevant title
                $firmKey = Match-TrackedFirm $company
                if (-not $firmKey -and -not (Test-RelevantTitle $title)) { continue }
                if (-not $firmKey) { $firmKey = "Other" }

                # Salary is optional — do a contextual lookup around the link in the HTML
                $salary = ""
                $linkIdx = $html.IndexOf($link)
                if ($linkIdx -gt 0) {
                    $cardBlock   = $html.Substring([Math]::Max(0, $linkIdx - 200), [Math]::Min(1500, $html.Length - [Math]::Max(0, $linkIdx - 200)))
                    $salaryMatch = [regex]::Match($cardBlock, '(?s)job-search-card__salary-info[^>]*>\s*([^<]+)<')
                    if ($salaryMatch.Success) { $salary = $salaryMatch.Groups[1].Value.Trim() }
                }

                $jobs[$link] = New-JobObject -title $title -link $link -company $company `
                    -firmKey $firmKey -pubDate $date -snippet "" -source "LinkedIn" -location $loc -salary $salary
            }

            $start += 25
            Start-Sleep -Milliseconds 1200

        } catch {
            break
        }
    }

    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

function Search-AALL {
    Write-Log "  [AALL] careers.aallnet.org ..."
    $jobs = [System.Collections.Generic.Dictionary[string,object]]::new()

    try {
        $r    = Invoke-WebRequest -Uri "https://careers.aallnet.org/jobs/" -Headers $WEB_HEADERS -TimeoutSec 20 -UseBasicParsing
        $html = $r.Content

        # Extract job links (pattern: /job/title/id/)
        $linkMatches = [regex]::Matches($html, 'href="(https://careers\.aallnet\.org/job/[^"]+)"')
        $seen = @{}

        foreach ($m in $linkMatches) {
            $link = $m.Groups[1].Value
            if ($seen[$link]) { continue }
            $seen[$link] = $true

            # Extract the block around this link for title, employer, location
            $idx   = $html.IndexOf($m.Value)
            $block = $html.Substring([Math]::Max(0, $idx - 50), [Math]::Min(1000, $html.Length - [Math]::Max(0, $idx - 50)))

            # Title from link text or h2/h3
            $titleMatch = [regex]::Match($block, '>([^<]{5,120})</a>')
            $title = if ($titleMatch.Success) { [System.Web.HttpUtility]::HtmlDecode($titleMatch.Groups[1].Value.Trim()) } else { "" }
            if (-not $title -or $title.Length -lt 4) { continue }

            # Employer — appears shortly after the title link
            $empMatch = [regex]::Match($block, 'employer[^>]*>([^<]+)<|organization[^>]*>([^<]+)<|<strong>([^<]+)</strong>')
            $company  = if ($empMatch.Success) { ($empMatch.Groups[1].Value + $empMatch.Groups[2].Value + $empMatch.Groups[3].Value).Trim() } else { "" }

            # Date
            $dateMatch = [regex]::Match($block, '(\d+)\s+days?\s+ago|(\d{1,2}/\d{1,2}/\d{4})')
            $pubDate   = if ($dateMatch.Success) { $dateMatch.Value } else { "" }

            $firmKey = Match-TrackedFirm $company
            if (-not $firmKey -and -not (Test-RelevantTitle $title)) { continue }
            if (-not $firmKey) { $firmKey = "Other" }

            $jobs[$link] = New-JobObject -title $title -link $link -company $company `
                -firmKey $firmKey -pubDate $pubDate -snippet "" -source "AALL"
        }
    } catch {
        Write-Log "    AALL error: $($_.Exception.Message)"
    }

    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

function Search-KirklandCareers {
    Write-Log "  [Kirkland & Ellis] staffjobsus.kirkland.com ..."
    $jobs    = [System.Collections.Generic.Dictionary[string,object]]::new()
    $queries = @("library", "research", "knowledge management", "competitive intelligence", "information services")

    foreach ($q in $queries) {
        try {
            $encoded = [uri]::EscapeDataString($q)
            $url  = "https://staffjobsus.kirkland.com/jobs/search/?q=$encoded"
            $r    = Invoke-WebRequest -Uri $url -Headers $WEB_HEADERS -TimeoutSec 20 -UseBasicParsing
            $html = $r.Content

            # Each job link has pattern /jobs/NNNNNNN-slug
            $linkMatches = [regex]::Matches($html, 'href="(https://staffjobsus\.kirkland\.com/jobs/\d[^"]+)"')
            foreach ($m in $linkMatches) {
                $link = $m.Groups[1].Value
                if ($jobs.ContainsKey($link)) { continue }

                # Find the surrounding div.row for title/location/date
                $idx   = $html.IndexOf($m.Value)
                $block = $html.Substring([Math]::Max(0, $idx - 100), [Math]::Min(800, $html.Length - [Math]::Max(0, $idx - 100)))

                $titleMatch = [regex]::Match($block, '>([^<]{5,120})</a>')
                $title      = if ($titleMatch.Success) { [System.Web.HttpUtility]::HtmlDecode($titleMatch.Groups[1].Value.Trim()) } else { "" }
                if (-not $title -or -not (Test-RelevantTitle $title)) { continue }

                $locMatch = [regex]::Match($block, '(?:New York|Chicago|Los Angeles|Washington|Houston|San Francisco|London|Dallas|Boston|Miami)[^<,\n]{0,30}')
                $location = if ($locMatch.Success) { $locMatch.Value.Trim() } else { "" }

                $dateMatch = [regex]::Match($block, '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}')
                $pubDate   = if ($dateMatch.Success) { $dateMatch.Value } else { "" }

                $jobs[$link] = New-JobObject -title $title -link $link -company "Kirkland & Ellis" `
                    -firmKey "Kirkland Ellis" -pubDate $pubDate -snippet "" `
                    -source "Kirkland Careers" -location $location
            }
        } catch {
            # silently skip on error
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

function Search-SkaddenWorkday {
    Write-Log "  [Skadden] Workday API ..."
    $jobs = [System.Collections.Generic.Dictionary[string,object]]::new()
    $terms = @("library", "research", "knowledge", "information services")

    foreach ($term in $terms) {
        try {
            $body    = "{`"appliedFacets`":{},`"limit`":20,`"offset`":0,`"searchText`":`"$term`"}"
            $headers = $WEB_HEADERS.Clone()
            $headers['Content-Type'] = 'application/json'
            $headers['Accept']       = 'application/json'

            $r        = Invoke-RestMethod -Method POST `
                -Uri "https://skadden.wd5.myworkdayjobs.com/wday/cxs/skadden/Skadden_Careers/jobs" `
                -Body $body -Headers $headers -TimeoutSec 20
            foreach ($posting in $r.jobPostings) {
                $title = $posting.title
                if (-not (Test-RelevantTitle $title)) { continue }
                $path = $posting.externalPath   # e.g. /job/Title_JR_1234
                $link = "https://skadden.wd5.myworkdayjobs.com/en-US/Skadden_Careers$path"
                if ($jobs.ContainsKey($link)) { continue }

                $jobs[$link] = New-JobObject -title $title -link $link -company "Skadden Arps" `
                    -firmKey "Skadden Arps" -pubDate $posting.postedOn -snippet "" `
                    -source "Skadden Careers" -location $posting.locationsText
            }
        } catch {
            # silently skip on error
        }
        Start-Sleep -Milliseconds 300
    }

    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

# Generic Workday API search — works for any firm on the Workday platform
function Search-WorkdayFirm {
    param(
        [string]$firmKey,
        [string]$tenant,
        [string]$instance,    # wd1 / wd3 / wd5 / wd12 etc.
        [string]$careerSite
    )
    $displayName = if ($FIRM_DISPLAY.ContainsKey($firmKey)) { $FIRM_DISPLAY[$firmKey] } else { $firmKey }
    Write-Log "  [$displayName] Workday ..."
    $jobs    = [System.Collections.Generic.Dictionary[string,object]]::new()
    $terms   = @("library", "research", "knowledge management", "information services")
    $baseUrl = "https://$tenant.$instance.myworkdayjobs.com"
    $apiUrl  = "$baseUrl/wday/cxs/$tenant/$careerSite/jobs"

    foreach ($term in $terms) {
        try {
            $body    = "{`"appliedFacets`":{},`"limit`":20,`"offset`":0,`"searchText`":`"$term`"}"
            $headers = $WEB_HEADERS.Clone()
            $headers['Content-Type'] = 'application/json'
            $headers['Accept']       = 'application/json'
            $r = Invoke-RestMethod -Method POST -Uri $apiUrl -Body $body -Headers $headers -TimeoutSec 20
            foreach ($posting in $r.jobPostings) {
                $title = $posting.title
                if (-not (Test-RelevantTitle $title)) { continue }
                $path = $posting.externalPath
                $link = "$baseUrl/en-US/$careerSite$path"
                if ($jobs.ContainsKey($link)) { continue }
                $jobs[$link] = New-JobObject -title $title -link $link -company $displayName `
                    -firmKey $firmKey -pubDate $posting.postedOn -snippet "" `
                    -source "Firm Careers" -location $posting.locationsText
            }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

# Generic iCIMS search — uses mobile=true endpoint which returns flat HTML with job links
function Search-ICIMSFirm {
    param(
        [string]$firmKey,
        [string]$subdomain    # e.g. "careers-sidley", "uscareers-willkie"
    )
    $displayName = if ($FIRM_DISPLAY.ContainsKey($firmKey)) { $FIRM_DISPLAY[$firmKey] } else { $firmKey }
    Write-Log "  [$displayName] iCIMS ..."
    $jobs = [System.Collections.Generic.Dictionary[string,object]]::new()

    try {
        # mobile=true bypasses the iframe wrapper and returns flat HTML with all job links
        $url  = "https://$subdomain.icims.com/jobs/search?ss=1&mobile=true&needsRedirect=false&hashed=-435739606"
        $r    = Invoke-WebRequest -Uri $url -Headers $WEB_HEADERS -TimeoutSec 20 -UseBasicParsing
        $html = $r.Content

        # Job links pattern: /jobs/1234/job-title-slug/job
        $linkMatches = [regex]::Matches($html, 'href="(/jobs/(\d+)/([^"]+)/job[^"]*)"')
        foreach ($m in $linkMatches) {
            $path = $m.Groups[1].Value
            $slug = $m.Groups[3].Value
            $link = "https://$subdomain.icims.com$path"
            if ($jobs.ContainsKey($link)) { continue }

            # Try to extract title from the anchor tag text
            $idx   = $html.IndexOf($m.Value)
            $block = $html.Substring([Math]::Max(0, $idx - 10), [Math]::Min(400, $html.Length - [Math]::Max(0, $idx - 10)))
            $titleMatch = [regex]::Match($block, '(?s)href="[^"]+"[^>]*>([^<]{5,120})<')
            $title = if ($titleMatch.Success) {
                [System.Web.HttpUtility]::HtmlDecode($titleMatch.Groups[1].Value.Trim())
            } else {
                # Fall back: derive title from URL slug
                (Get-Culture).TextInfo.ToTitleCase(([uri]::UnescapeDataString($slug) -replace '-', ' '))
            }
            if (-not $title -or $title.Length -lt 4) { continue }
            if (-not (Test-RelevantTitle $title)) { continue }

            $jobs[$link] = New-JobObject -title $title -link $link -company $displayName `
                -firmKey $firmKey -pubDate "" -snippet "" -source "Firm Careers"
        }
    } catch {
        Write-Log "    iCIMS error: $($_.Exception.Message.Split([char]10)[0])"
    }

    Write-Log "    Found $($jobs.Count) relevant result(s)"
    return $jobs.Values
}

function Search-IndeedRss {
    param($searchQuery)
    $encoded = [uri]::EscapeDataString($searchQuery)
    $url     = "https://www.indeed.com/rss?q=$encoded&fromage=$DAYS_BACK&sort=date"
    try {
        $headers = $WEB_HEADERS.Clone()
        $headers['Accept'] = 'application/rss+xml, application/xml, text/xml, */*'
        $r    = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 20 -UseBasicParsing
        [xml]$feed = $r.Content
        return $feed.rss.channel.item
    } catch {
        return @()
    }
}

# ---- AGGREGATE ALL SOURCES --------------------------------------------------

function Get-AllJobs {
    $allJobs = [System.Collections.Generic.Dictionary[string,object]]::new()

    # Helper to merge results into the master dict
    function Add-Jobs {
        param($newJobs)
        foreach ($j in $newJobs) {
            if ($j -and $j.Link -and -not $allJobs.ContainsKey($j.Link)) {
                $allJobs[$j.Link] = $j
            }
        }
    }

    Write-Log "--- LinkedIn ---"
    foreach ($query in $LINKEDIN_SEARCHES) {
        Add-Jobs (Search-LinkedIn $query)
        Start-Sleep -Milliseconds 1500
    }

    Write-Log "--- AALL Job Board ---"
    Add-Jobs (Search-AALL)

    Write-Log "--- Firm Career Pages ---"

    # Already-customized scrapers
    Add-Jobs (Search-KirklandCareers)
    Add-Jobs (Search-SkaddenWorkday)

    # Workday firms (generic API)
    Add-Jobs (Search-WorkdayFirm "Weil Gotshal"               "weil"         "wd1"  "work_at_weil")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "Simpson Thacher Bartlett"   "stblaw"       "wd1"  "careers")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "Morgan Lewis Bockius"       "morganlewis"  "wd5"  "morganlewis")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "DLA Piper"                  "dlapiper"     "wd1"  "dlapiper")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "Hogan Lovells"              "hoganlovells" "wd3"  "Search")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "Dechert"                    "dechert"      "wd12" "DechertCareers")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-WorkdayFirm "Sullivan Cromwell"          "cromwell"     "wd3"  "01")
    Start-Sleep -Milliseconds 500

    # iCIMS firms (generic mobile endpoint)
    Add-Jobs (Search-ICIMSFirm "Sidley Austin"                "careers-sidley")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-ICIMSFirm "Cleary Gottlieb"              "careers-clearygottlieb")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-ICIMSFirm "Willkie Farr Gallagher"       "uscareers-willkie")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-ICIMSFirm "Mayer Brown"                  "jobs3-mayerbrown")
    Start-Sleep -Milliseconds 500
    Add-Jobs (Search-ICIMSFirm "Milbank"                      "careers-milbank")

    Write-Log "--- Indeed (fallback) ---"
    $searchTerms = @("librarian", "library director", "research manager", "knowledge management")
    foreach ($firm in $LAW_FIRMS) {
        $displayName = if ($FIRM_DISPLAY.ContainsKey($firm)) { $FIRM_DISPLAY[$firm] } else { $firm }
        foreach ($term in $searchTerms) {
            $items = Search-IndeedRss -searchQuery "`"$firm`" `"$term`""
            foreach ($item in $items) {
                $rawTitle = if ($item.title)       { $item.title }       else { "" }
                $link     = if ($item.link)        { $item.link  }       else { "" }
                $rawDesc  = if ($item.description) { $item.description } else { "" }
                $pubDate  = if ($item.pubDate)     { $item.pubDate }     else { "" }
                $source   = if ($item.source -and $item.source.'#text') { $item.source.'#text' } else { $displayName }
                $title    = Remove-HtmlTags $rawTitle
                $desc     = Remove-HtmlTags $rawDesc

                if (-not $link -or $allJobs.ContainsKey($link)) { continue }
                if (-not (Test-RelevantTitle $title))            { continue }

                $snip = if ($desc.Length -gt 0) { $desc.Substring(0, [Math]::Min(350, $desc.Length)) } else { "" }
                $allJobs[$link] = New-JobObject -title $title -link $link -company $source `
                    -firmKey $firm -pubDate $pubDate -snippet $snip -source "Indeed"
            }
            Start-Sleep -Milliseconds 500
        }
    }

    return $allJobs.Values | Sort-Object FirmDisplay, Title
}

# ---- NEWSLETTER GENERATION --------------------------------------------------

# Source badge colors — used by Build-JobCard (must be top-level for scoping)
$SOURCE_COLORS = @{
    "LinkedIn"        = "#0077b5"
    "AALL"            = "#c0392b"
    "Kirkland Careers"= "#8b6914"
    "Skadden Careers" = "#1a237e"
    "Firm Careers"    = "#2e7d32"
    "Indeed"          = "#2164f3"
    "Other"           = "#555"
}

# Top-level so PowerShell 5 does not choke on a here-string inside a nested function
function Build-JobCard {
    param($j)
    $titleEsc   = [System.Web.HttpUtility]::HtmlEncode($j.Title)
    $linkEsc    = [System.Web.HttpUtility]::HtmlEncode($j.Link)
    $companyEsc = [System.Web.HttpUtility]::HtmlEncode($j.Company)
    $dateEsc    = [System.Web.HttpUtility]::HtmlEncode((Get-FriendlyDate $j.PubDate))
    $snippetEsc = [System.Web.HttpUtility]::HtmlEncode($j.Snippet)
    $locEsc     = [System.Web.HttpUtility]::HtmlEncode($j.Location)
    $srcColor   = if ($SOURCE_COLORS.ContainsKey($j.Source)) { $SOURCE_COLORS[$j.Source] } else { "#555" }
    $srcEsc     = [System.Web.HttpUtility]::HtmlEncode($j.Source)

    $salaryEsc  = [System.Web.HttpUtility]::HtmlEncode($j.Salary)

    $card = [System.Text.StringBuilder]::new()
    [void]$card.AppendLine('            <div class="job-card">')
    [void]$card.AppendLine("                <div class=`"job-title`"><a href=`"$linkEsc`" target=`"_blank`">$titleEsc</a></div>")
    [void]$card.Append('                <div class="job-meta">')
    [void]$card.Append("<span class=`"source-badge`" style=`"background:$srcColor`">$srcEsc</span> ")
    [void]$card.Append("<span>$companyEsc</span>")
    if ($dateEsc)    { [void]$card.Append(" &bull; <span>$dateEsc</span>") }
    if ($locEsc)     { [void]$card.Append(" &bull; &#128205; $locEsc") }
    [void]$card.AppendLine('</div>')
    if ($salaryEsc)  { [void]$card.AppendLine("                <div class=`"job-salary`">&#128176; $salaryEsc</div>") }
    if ($snippetEsc) { [void]$card.AppendLine("                <div class=`"job-snippet`">$snippetEsc</div>") }
    [void]$card.AppendLine("                <a class=`"view-link`" href=`"$linkEsc`" target=`"_blank`">View posting &#8594;</a>")
    [void]$card.AppendLine('            </div>')
    return $card.ToString()
}

function New-Newsletter {
    param($jobs, $date)

    $dateStr   = $date.ToString("dddd, MMMM dd, yyyy")
    $jobsArray = @($jobs)
    $jobCount  = $jobsArray.Count

    $firmNames  = ($FIRM_DISPLAY.Values | Sort-Object | ForEach-Object { [System.Web.HttpUtility]::HtmlEncode($_) })
    $firmFooter = $firmNames -join " &#124; "

    # Separate tracked-firm jobs from "Other" jobs
    $trackedJobs = $jobsArray | Where-Object { $_.FirmKey -ne "Other" }
    $otherJobs   = $jobsArray | Where-Object { $_.FirmKey -eq "Other" }

    # Group tracked jobs by firm display name
    $byFirm = @{}
    foreach ($j in $trackedJobs) {
        $key = $j.FirmDisplay
        if (-not $byFirm.ContainsKey($key)) { $byFirm[$key] = [System.Collections.Generic.List[object]]::new() }
        $byFirm[$key].Add($j)
    }

    # Build tracked-firm sections
    $sb = [System.Text.StringBuilder]::new()
    if ($byFirm.Count -eq 0 -and $otherJobs.Count -eq 0) {
        [void]$sb.AppendLine('        <div class="no-jobs">')
        [void]$sb.AppendLine('            <p>No new library or research positions were found at tracked firms in the past 7 days.</p>')
        [void]$sb.AppendLine('            <p style="margin-top:10px;font-size:13px;">Check back tomorrow, or visit each firm career page directly.</p>')
        [void]$sb.AppendLine('        </div>')
    } else {
        foreach ($firmName in ($byFirm.Keys | Sort-Object)) {
            $firmEsc = [System.Web.HttpUtility]::HtmlEncode($firmName)
            [void]$sb.AppendLine("        <div class=`"firm-section`">")
            [void]$sb.AppendLine("            <div class=`"firm-header`">$firmEsc</div>")
            foreach ($j in $byFirm[$firmName]) { [void]$sb.AppendLine((Build-JobCard $j)) }
            [void]$sb.AppendLine("        </div>")
        }

        # Other relevant jobs (title match but not a tracked firm)
        if ($otherJobs.Count -gt 0) {
            [void]$sb.AppendLine("        <div class=`"firm-section`">")
            [void]$sb.AppendLine("            <div class=`"firm-header`" style=`"color:#666`">Other Relevant Positions</div>")
            foreach ($j in ($otherJobs | Sort-Object Title)) { [void]$sb.AppendLine((Build-JobCard $j)) }
            [void]$sb.AppendLine("        </div>")
        }
    }
    $jobSections = $sb.ToString()

    # Collect active sources for summary line
    $activeSources = @($jobsArray | Select-Object -ExpandProperty Source -Unique | Sort-Object)
    $sourcesSummary = if ($activeSources.Count -gt 0) { $activeSources -join ", " } else { "none" }

    # Build HTML
    $html = [System.Text.StringBuilder]::new()
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html lang="en">')
    [void]$html.AppendLine('<head>')
    [void]$html.AppendLine('<meta charset="UTF-8">')
    [void]$html.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$html.AppendLine("<title>Law Firm Library &amp; Research Jobs &mdash; $dateStr</title>")
    [void]$html.AppendLine('<style>')
    [void]$html.AppendLine('* { box-sizing: border-box; margin: 0; padding: 0; }')
    [void]$html.AppendLine('body { font-family: Georgia, "Times New Roman", serif; background: #eef0f3; color: #1a1a2e; line-height: 1.6; }')
    [void]$html.AppendLine('a { color: #283593; }')
    [void]$html.AppendLine('.wrapper { max-width: 820px; margin: 32px auto; background: #fff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,.12); }')
    [void]$html.AppendLine('.header { background: linear-gradient(135deg, #1a237e 0%, #283593 100%); color: #fff; padding: 36px 48px; }')
    [void]$html.AppendLine('.header h1 { font-size: 26px; font-weight: normal; letter-spacing: .5px; }')
    [void]$html.AppendLine('.header .tagline { font-size: 13px; color: #9fa8da; margin-top: 6px; }')
    [void]$html.AppendLine('.header .date { font-size: 16px; color: #c5cae9; margin-top: 8px; }')
    [void]$html.AppendLine('.summary { background: #e8eaf6; padding: 12px 48px; font-size: 13px; color: #3949ab; border-bottom: 2px solid #c5cae9; }')
    [void]$html.AppendLine('.body { padding: 32px 48px; }')
    [void]$html.AppendLine('.no-jobs { text-align: center; padding: 48px 0; color: #666; font-style: italic; }')
    [void]$html.AppendLine('.firm-section { margin-bottom: 36px; }')
    [void]$html.AppendLine('.firm-header { font-size: 11px; font-family: Arial, sans-serif; font-weight: bold; color: #1a237e; text-transform: uppercase; letter-spacing: 2px; border-bottom: 2px solid #e8eaf6; padding-bottom: 8px; margin-bottom: 14px; }')
    [void]$html.AppendLine('.job-card { background: #f9f9fd; border: 1px solid #e0e0e0; border-left: 4px solid #3949ab; border-radius: 5px; padding: 16px 20px; margin-bottom: 12px; }')
    [void]$html.AppendLine('.job-title { font-size: 17px; margin-bottom: 6px; }')
    [void]$html.AppendLine('.job-title a { text-decoration: none; color: #1a237e; }')
    [void]$html.AppendLine('.job-title a:hover { text-decoration: underline; }')
    [void]$html.AppendLine('.job-meta { font-size: 12px; color: #777; margin-bottom: 8px; font-family: Arial, sans-serif; display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }')
    [void]$html.AppendLine('.source-badge { display: inline-block; font-size: 10px; font-weight: bold; color: #fff; padding: 2px 7px; border-radius: 10px; letter-spacing: .5px; text-transform: uppercase; }')
    [void]$html.AppendLine('.job-salary { font-size: 13px; font-family: Arial, sans-serif; color: #2e7d32; font-weight: bold; margin-bottom: 6px; }')
    [void]$html.AppendLine('.job-snippet { font-size: 14px; color: #555; line-height: 1.5; margin-bottom: 8px; }')
    [void]$html.AppendLine('.view-link { font-size: 13px; font-family: Arial, sans-serif; color: #3949ab; text-decoration: none; }')
    [void]$html.AppendLine('.view-link:hover { text-decoration: underline; }')
    [void]$html.AppendLine('.firm-list-section { border-top: 2px solid #e8eaf6; padding: 24px 48px; }')
    [void]$html.AppendLine('.firm-list-section h3 { font-size: 11px; font-family: Arial, sans-serif; font-weight: bold; color: #999; text-transform: uppercase; letter-spacing: 2px; margin-bottom: 10px; }')
    [void]$html.AppendLine('.firm-list-section p { font-size: 13px; color: #777; line-height: 2; font-family: Arial, sans-serif; }')
    [void]$html.AppendLine('.footer { background: #f5f5f5; padding: 16px 48px; font-size: 12px; color: #aaa; text-align: center; font-family: Arial, sans-serif; border-top: 1px solid #e0e0e0; }')
    [void]$html.AppendLine('</style>')
    [void]$html.AppendLine('</head><body>')
    [void]$html.AppendLine('<div class="wrapper">')
    [void]$html.AppendLine('  <div class="header">')
    [void]$html.AppendLine('    <h1>Law Firm Library &amp; Research Jobs</h1>')
    [void]$html.AppendLine('    <div class="tagline">Daily Digest &mdash; Research &amp; Library Positions at AmLaw Peer Firms</div>')
    [void]$html.AppendLine("    <div class=`"date`">$dateStr</div>")
    [void]$html.AppendLine('  </div>')
    [void]$html.AppendLine("  <div class=`"summary`">Tracking <strong>$($LAW_FIRMS.Count) firms</strong> &nbsp;&bull;&nbsp; <strong>$jobCount position(s)</strong> found in the past $DAYS_BACK days &nbsp;&bull;&nbsp; Sources: $sourcesSummary</div>")
    [void]$html.AppendLine('  <div class="body">')
    [void]$html.AppendLine($jobSections)
    [void]$html.AppendLine('  </div>')
    [void]$html.AppendLine('  <div class="firm-list-section"><h3>Tracked Firms</h3>')
    [void]$html.AppendLine("    <p>$firmFooter</p></div>")
    [void]$html.AppendLine("  <div class=`"footer`">Generated $dateStr &bull; Law Firm Library &amp; Research Job Tracker<br>Sources: LinkedIn, AALL, Firm Career Pages. Verify availability on each firm's career page.</div>")
    [void]$html.AppendLine('</div></body></html>')

    return $html.ToString()
}

# ---- EMAIL ------------------------------------------------------------------

function Send-Newsletter {
    param($htmlPath)

    if (-not $GMAIL_ADDRESS -or $GMAIL_ADDRESS -eq "your.email@gmail.com") {
        Write-Log "Email skipped — edit config.ps1 with your Gmail address and App Password."
        return
    }
    if (-not $GMAIL_APP_PASSWORD -or $GMAIL_APP_PASSWORD -eq "xxxx xxxx xxxx xxxx") {
        Write-Log "Email skipped — no App Password set in config.ps1."
        return
    }

    Write-Log "Sending newsletter to $GMAIL_ADDRESS ..."

    try {
        $body = Get-Content -Path $htmlPath -Raw -Encoding UTF8

        $msg                 = [System.Net.Mail.MailMessage]::new()
        $msg.From            = [System.Net.Mail.MailAddress]::new($GMAIL_ADDRESS, "Law Firm Job Tracker")
        $msg.To.Add($GMAIL_ADDRESS)
        $msg.Subject         = "Law Firm Job Newsletter"
        $msg.Body            = $body
        $msg.IsBodyHtml      = $true
        $msg.BodyEncoding    = [System.Text.Encoding]::UTF8
        $msg.SubjectEncoding = [System.Text.Encoding]::UTF8

        $appPwd  = $GMAIL_APP_PASSWORD -replace '\s', ''
        $smtp    = [System.Net.Mail.SmtpClient]::new("smtp.gmail.com", 587)
        $smtp.EnableSsl      = $true
        $smtp.Credentials    = [System.Net.NetworkCredential]::new($GMAIL_ADDRESS, $appPwd)
        $smtp.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network
        $smtp.Timeout        = 30000

        $smtp.Send($msg)
        Write-Log "Email sent successfully to $GMAIL_ADDRESS"
    } catch {
        Write-Log "Email failed: $($_.Exception.Message)"
    } finally {
        if ($msg)  { $msg.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

# ---- MAIN -------------------------------------------------------------------

function Main {
    $today = Get-Date

    Write-Log "====================================================="
    Write-Log "Law Firm Library & Research Job Tracker"
    Write-Log "Date: $($today.ToString('MMMM dd, yyyy'))"
    Write-Log "Sources: LinkedIn, AALL, Firm Career Pages, Indeed"
    Write-Log "====================================================="

    if (-not (Test-Path $OUTPUT_DIR)) { New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null }

    Write-Log "Starting job search..."
    $jobs    = Get-AllJobs
    $jobList = @($jobs)
    Write-Log "Total unique jobs found: $($jobList.Count)"

    $html     = New-Newsletter -jobs $jobList -date $today
    $datePart = $today.ToString('yyyy-MM-dd')
    $filename = "law_firm_jobs_$datePart.html"
    $outPath  = Join-Path $OUTPUT_DIR $filename

    $html | Out-File -FilePath $outPath -Encoding UTF8
    Write-Log "Newsletter saved: $outPath"

    if (-not (Test-Path $LOG_FILE)) {
        "Date,Title,Company,Firm,Source,Link" | Out-File $LOG_FILE -Encoding UTF8
    }
    foreach ($j in $jobList) {
        $t = $j.Title       -replace ','
        $c = $j.Company     -replace ','
        $f = $j.FirmDisplay -replace ','
        "$datePart,$t,$c,$f,$($j.Source),$($j.Link)" | Add-Content $LOG_FILE -Encoding UTF8
    }
    Write-Log "Job history log updated"

    Send-Newsletter -htmlPath $outPath

    Start-Process $outPath
    Write-Log "Newsletter opened in browser."
    Write-Log "Done!"
}

Main
