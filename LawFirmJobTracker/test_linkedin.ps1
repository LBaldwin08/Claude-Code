# Test LinkedIn parsing - extract all job fields
$url = 'https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords=law+firm+research&location=United+States&geoId=103644278&f_TPR=r604800&start=0&count=25'
$headers = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36'
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'en-US,en;q=0.9'
    'Referer'         = 'https://www.linkedin.com/'
}

$r = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 20 -UseBasicParsing
$html = $r.Content

# Extract job titles
$titles    = [regex]::Matches($html, '(?s)<h3[^>]*base-search-card__title[^>]*>\s*(.*?)\s*</h3>') | ForEach-Object { $_.Groups[1].Value.Trim() }
# Extract companies
$companies = [regex]::Matches($html, '(?s)<h4[^>]*base-search-card__subtitle[^>]*>.*?<a[^>]*>(.*?)</a>') | ForEach-Object { $_.Groups[1].Value.Trim() }
# Extract locations
$locations = [regex]::Matches($html, '(?s)<span[^>]*job-search-card__location[^>]*>\s*(.*?)\s*</span>') | ForEach-Object { $_.Groups[1].Value.Trim() }
# Extract dates
$dates     = [regex]::Matches($html, '<time[^>]*datetime="([^"]+)"') | ForEach-Object { $_.Groups[1].Value.Trim() }
# Extract links
$links     = [regex]::Matches($html, 'href="(https://www\.linkedin\.com/jobs/view/[^"?]+)') | ForEach-Object { $_.Groups[1].Value.Trim() }

Write-Host "Found $($titles.Count) jobs"
Write-Host ""
for ($i = 0; $i -lt $titles.Count; $i++) {
    Write-Host "[$($i+1)] $($titles[$i])"
    Write-Host "     Company:  $($companies[$i])"
    Write-Host "     Location: $($locations[$i])"
    Write-Host "     Date:     $($dates[$i])"
    Write-Host "     Link:     $($links[$i])"
    Write-Host ""
}
