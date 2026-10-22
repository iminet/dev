#Requires -Version 5.1
<#
.SYNOPSIS
    Upload JPG, JPEG, and PNG files to ImgBB sequentially.
.DESCRIPTION
    Uses the official HTTPS API without external module dependencies. Files are
    streamed through the pipeline without a configured file-count limit.
    Requests are spaced 3-6 seconds apart by default. Transient failures get at most three
    retries with exponential backoff and jitter; Retry-After is respected.
    Exhausted transient failures stop the run to avoid sustained server load.
    Automation is not disguised and service-side limits still apply.
    Console colors: green for success, cyan for status/dry run, yellow for
    retries/skips, and red for errors. Text labels remain readable without color.
.PARAMETER DirectoryPath
    An existing directory. Treated as a literal path, including brackets.
.PARAMETER ApiKey
    ImgBB API key. A nonblank value overrides IMGBB_API_KEY. Prefer the environment
    variable to avoid saving a key in shell history. The key is sent in the POST
    body, never in the URL or script-generated messages.
.PARAMETER Recurse
    Include subdirectories. Disabled by default. Hidden files are not included.
.PARAMETER WaitTime
    Random (default) enables a random 3-6 second pause between requests.
    Only Off disables this ordinary pause. Omitted, empty, or unrecognized
    values retain random waiting. Values are case-insensitive. Retry backoff
    and server Retry-After waits remain enabled even with Off.
.PARAMETER Silent
    Show errors only; suppress file status, retry notices, and summaries.
    Errors are plain messages on standard error, without PowerShell error blocks.
.PARAMETER DryRun
    Enumerate, validate size/readability, and Base64-encode files without any
    network requests or delays. Requires a key but cannot validate it remotely.
    Honors Recurse and Silent. Does not validate actual image contents.
.EXAMPLE
    $env:IMGBB_API_KEY = 'YOUR_API_KEY'
    .\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images'
.EXAMPLE
    .\Upload-ImagesToImgBB.ps1 -DirectoryPath './images' -ApiKey $key -Recurse
.EXAMPLE
    .\Upload-ImagesToImgBB.ps1 -DirectoryPath './images' -Recurse -DryRun
.EXAMPLE
    .\Upload-ImagesToImgBB.ps1 -DirectoryPath './images' -Silent
.EXAMPLE
    .\Upload-ImagesToImgBB.ps1 -DirectoryPath './images' -WaitTime Off
    Disables ordinary request delays while retaining retry waits.
.NOTES
    Intended for Windows PowerShell 5.1 and PowerShell 7.
    Exit codes: 0 = success (including no matching files); 1 = any failure.
    A run stopped early reports only files processed before the stop.
    No automatic expiration is requested. No files are modified locally.
    Re-running uploads files again. A lost response followed by a retry can also
    create a duplicate: the API does not provide an idempotency key here.
    Do not publish real keys, private images, or transcripts containing secrets.
.LINK
    https://api.imgbb.com/
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Upload-ImagesToImgBB contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DirectoryPath,

    [string]$ApiKey,
    [AllowNull()]
    [AllowEmptyString()]
    [string]$WaitTime = 'Random',
    [switch]$Recurse,
    [switch]$Silent,
    [switch]$DryRun
)

function Write-Status {
    param (
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    if (-not $Silent) { Write-Host $Message -ForegroundColor $Color }
}

function Write-UploadError {
    param (
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Red
    )
    # Do not print raw exceptions, request bodies, or server response bodies.
    # Preserve standard error and plain messages without PowerShell error blocks.
    # Redirected errors receive no color sequences; unsupported hosts use plain text.
    $restoreColor = $false
    try {
        if (-not [Console]::IsErrorRedirected) {
            $previousColor = [Console]::ForegroundColor
            [Console]::ForegroundColor = $Color
            $restoreColor = $true
        }
    }
    catch { }
    try {
        [Console]::Error.WriteLine("[ERROR] $Message")
    }
    finally {
        if ($restoreColor) {
            try { [Console]::ForegroundColor = $previousColor }
            catch { }
        }
    }
}

function Get-RetryAfterSeconds {
    param ($HttpResponse)
    if ($null -eq $HttpResponse) { return 0.0 }
    try {
        # Both WebHeaderCollection (5.1) and HttpResponseHeaders (7) support this.
        $headerValues = @($HttpResponse.Headers.GetValues('Retry-After'))
        if ($headerValues.Count -eq 0) { return 0.0 }
        $header = [string]$headerValues[0]
        $seconds = 0L
        if ([long]::TryParse($header, [ref]$seconds) -and $seconds -ge 0) {
            return [double]$seconds
        }
        $date = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($header,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
            return [Math]::Max(0, [Math]::Ceiling(($date - [DateTimeOffset]::UtcNow).TotalSeconds))
        }
    }
    catch { } # Missing/malformed headers fall back to exponential backoff.
    return 0.0
}

function Wait-UploadDelay {
    param ([double]$Seconds)
    # Chunk long Retry-After values without shortening the requested wait.
    while ($Seconds -gt 0) {
        $chunk = [int][Math]::Min(60, [Math]::Ceiling($Seconds))
        Start-Sleep -Seconds $chunk
        $Seconds -= $chunk
    }
}

$finalApiKey = if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $env:IMGBB_API_KEY
}
else { $ApiKey }

if ([string]::IsNullOrWhiteSpace($finalApiKey)) {
    Write-UploadError 'API key missing. Use -ApiKey or set IMGBB_API_KEY.'
    exit 1
}

$processed = 0L
$succeeded = 0L
$failed = 0L
$runFailed = $false
$requestSent = $false
# Deliberately avoid ValidateSet: unknown values must fall back to random waits.
$useRandomWait = $WaitTime -ine 'Off'
$maxAttempts = 4 # One initial request plus three retries.
$transientStatusCodes = @(408, 429, 500, 502, 503, 504)
$endpoint = 'https://api.imgbb.com/1/upload'
$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    $directory = Get-Item -LiteralPath $DirectoryPath -ErrorAction Stop
    if (-not $directory.PSIsContainer -or $directory.PSProvider.Name -ne 'FileSystem') {
        throw 'A filesystem directory is required.'
    }

    if (-not $DryRun -and $PSVersionTable.PSVersion.Major -eq 5) {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    $mode = if ($DryRun) { 'Dry run' } else { 'Upload' }
    Write-Status "$mode started. Recursive search: $([bool]$Recurse)."
    if (-not $DryRun) {
        $waitMode = if ($useRandomWait) { 'Random (3-6 seconds)' } else { 'Off (retry waits still apply)' }
        Write-Status "Request delay: $waitMode."
    }

    Get-ChildItem -LiteralPath $directory.FullName -File -Recurse:$Recurse -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png') } |
        ForEach-Object {
            $image = $_
            $processed++
            $base64Image = $null
            try {
                # Check again after reading in case a file changed during enumeration.
                if ($image.Length -eq 0 -or $image.Length -gt 32MB) {
                    $failed++
                    Write-UploadError "[SKIP] '$($image.FullName)': size $($image.Length) bytes; allowed range is 1 byte to 32 MiB." -Color Yellow
                    return
                }
                $fileBytes = [IO.File]::ReadAllBytes($image.FullName)
                if ($fileBytes.Length -eq 0 -or $fileBytes.Length -gt 32MB) {
                    $failed++
                    Write-UploadError "[SKIP] '$($image.FullName)': size after reading is $($fileBytes.Length) bytes; allowed range is 1 byte to 32 MiB." -Color Yellow
                    return
                }
                $base64Image = [Convert]::ToBase64String($fileBytes)
            }
            catch {
                $failed++
                $reason = $_.Exception.GetBaseException().GetType().Name
                Write-UploadError "[SKIP] '$($image.FullName)': cannot read or encode the file ($reason)." -Color Yellow
                return # Skip this pipeline item; continue with the next file.
            }
            finally { $fileBytes = $null }

            if ($DryRun) {
                $succeeded++
                Write-Status "[DRY RUN] Would upload: $($image.FullName)"
                $base64Image = $null
                return
            }

            $body = @{ key = $finalApiKey; image = $base64Image; name = $image.BaseName }
            try {
                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    if ($requestSent -and $useRandomWait) {
                        Wait-UploadDelay -Seconds (Get-Random -Minimum 3 -Maximum 7)
                    }
                    Write-Status "[UPLOAD $attempt/$maxAttempts] $($image.FullName)" -Color White
                    $statusCode = 0
                    $retryAfter = 0.0
                    $requestSent = $true
                    try {
                        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body `
                            -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 60 `
                            -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop -Verbose:$false -Debug:$false
                        if ($response.success -eq $true) {
                            $succeeded++
                            Write-Status "[SUCCESS] $($image.FullName) -> $($response.data.url)" -Color Green
                            break
                        }
                        # An unsuccessful HTTP 2xx response must also terminate or retry.
                        if ($null -ne $response.status) {
                            $parsedStatus = 0
                            if ([int]::TryParse([string]$response.status, [ref]$parsedStatus)) {
                                $statusCode = $parsedStatus
                            }
                        }
                        if ($statusCode -eq 0) { $statusCode = 400 }
                    }
                    catch {
                        $httpResponse = $_.Exception.Response
                        if ($null -ne $httpResponse) {
                            $statusCode = [int]$httpResponse.StatusCode
                            $retryAfter = Get-RetryAfterSeconds -HttpResponse $httpResponse
                        }
                        # Status 0 represents a transport failure with no HTTP response.
                    }

                    $transient = $statusCode -eq 0 -or $statusCode -in $transientStatusCodes
                    $label = if ($statusCode -eq 0) { 'transport failure' } else { "HTTP/API $statusCode" }
                    Write-UploadError "Attempt $attempt/$maxAttempts failed for '$($image.FullName)' ($label)."

                    if ($transient -and $attempt -lt $maxAttempts) {
                        $backoff = 5 * [Math]::Pow(2, $attempt - 1) + (Get-Random -Minimum 0 -Maximum 4)
                        $wait = [Math]::Max($backoff, $retryAfter)
                        Write-Status "[RETRY] Waiting at least $wait seconds." -Color Yellow
                        Wait-UploadDelay -Seconds $wait
                        continue
                    }

                    $failed++
                    if ($statusCode -in @(401, 403) -or $transient) {
                        throw 'Authentication/access failure or exhausted transient retries.'
                    }
                    # A permanent per-file rejection should not retry unchanged input.
                    break
                }
            }
            finally {
                $body.Clear()
                $base64Image = $null
                $response = $null
            }
        }
}
catch {
    $runFailed = $true
    Write-UploadError 'Run stopped. Check the directory and its permissions; if requests failed, check the API key, connection, or service availability before restarting.'
}
finally {
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    }
    $finalApiKey = $null
}

if ($DryRun) {
    Write-Status "Dry run finished. Processed: $processed; ready: $succeeded; failed: $failed."
}
else {
    Write-Status "Upload finished. Processed: $processed; uploaded: $succeeded; failed: $failed."
}
if ($runFailed -or $failed -gt 0) { exit 1 }
exit 0
