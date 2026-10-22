# Upload Images to ImgBB

A small PowerShell hobby script for uploading JPG, JPEG, and PNG files from a local directory to ImgBB through its HTTPS API.

Uploads run sequentially, with random delays enabled by default and bounded retries to reduce server load. Ordinary delays can be disabled explicitly; retry waits remain enabled. There is no configured limit on the number of files in a run. Service limits, available memory, network conditions, and processing time still apply.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7. The implementation targets both versions; runtime compatibility testing has not yet been completed.
- A readable local filesystem directory containing images.
- An ImgBB API key, including for dry runs.
- Internet access to `https://api.imgbb.com/1/upload` for actual uploads.

No external PowerShell modules, administrator privileges, or package installation are required by the script. Your environment's script execution policy still applies.

Official API documentation and API-key information: <https://api.imgbb.com/>.

## Quick start

Save `Upload-ImagesToImgBB.ps1` and this README in the same directory. Open PowerShell there.

Set the API key for the current session, replacing the placeholder:

```powershell
$env:IMGBB_API_KEY = 'YOUR_API_KEY'
```

First check the files without uploading:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -DryRun
```

Then upload:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images'
```

The examples use placeholders, not working credentials. Typing a real key into a command may save it in shell history. For routine use, provision the environment variable through your preferred secure local mechanism. Environment variables are not a secret vault.

## Parameters

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `-DirectoryPath` | String | Required | Existing filesystem directory, interpreted literally. Relative paths are resolved from the current working directory. |
| `-ApiKey` | String | Unset | A nonblank value takes precedence over `IMGBB_API_KEY`. |
| `-Recurse` | Switch | Off | Include subdirectories. |
| `-WaitTime` | String | `Random` | Only `Off` disables the ordinary 3–6 second request delay. Missing, empty, or unrecognized values retain random waiting. Case-insensitive. Retry waits remain enabled. |
| `-Silent` | Switch | Off | Print errors and skips only. Suppress progress, success URLs, retry notices, and the summary. |
| `-DryRun` | Switch | Off | Perform local preparation without sending requests or waiting between files. |

Switches can be combined. For example, `-Recurse -Silent -DryRun` checks the directory tree and displays only problems.

`-WaitTime` intentionally accepts arbitrary string values and falls back to `Random` unless the value is exactly `Off`, ignoring letter case. Thus `-WaitTime 'invalid'`, `-WaitTime ''`, and omitting the parameter all keep random waiting. Supply a value when writing `-WaitTime`; a bare parameter without a value remains a PowerShell argument-binding error. A misspelled parameter name is also a binding error.

If `-ApiKey` is omitted, empty, or whitespace, the script uses `IMGBB_API_KEY`. If neither supplies a nonblank key, the script exits with an error before scanning files.

The standard PowerShell common parameters are also available, but `-WhatIf` and `-Confirm` are not implemented. Use `-DryRun` for a preview. `-Silent` controls ordinary status messages; it does not hide PowerShell parameter-binding or startup errors.

## Examples

Include subdirectories:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -Recurse
```

Supply a key already stored in a variable:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -ApiKey $key
```

Display only errors and skipped files:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -Recurse -Silent
```

Preview recursive processing:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -Recurse -DryRun
```

Use a relative path in PowerShell 7 on Linux or macOS:

```powershell
./Upload-ImagesToImgBB.ps1 -DirectoryPath './images' -DryRun
```

Disable ordinary request delays explicitly:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -WaitTime Off
```

Keep random waiting explicitly, or let an unrecognized value fall back to it:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -WaitTime Random
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -WaitTime 'invalid'
```

These are real uploads unless `-DryRun` is also supplied. `-WaitTime Off` works with `-Recurse` and `-Silent`. In dry-run mode, no waits occur regardless of `-WaitTime`.

Show built-in help:

```powershell
Get-Help .\Upload-ImagesToImgBB.ps1 -Full
```

## File selection and preparation

- Matches `.jpg`, `.jpeg`, and `.png` extensions, case-insensitively.
- Processes only the selected directory unless `-Recurse` is present.
- Does not request hidden files through `-Force`.
- Accepts brackets and other wildcard characters in directory names as literal characters.
- Requires a nonempty file no larger than **32 MiB (33,554,432 bytes)**. This is the script's local check; it does not guarantee that the service accepts a file.
- Checks size before and after reading, then converts the file to Base64.
- Does not decode images or verify that file contents match their extensions.
- Does not modify, move, resize, recompress, or delete local images.

Files are passed through a pipeline rather than collected into a complete image list. Each file is still read fully into memory. Base64 encoding and request construction require additional memory beyond the original file size. Directory enumeration order is not explicitly sorted.

## Dry-run behavior

`-DryRun` performs file discovery, size checks, reading, and Base64 conversion. For each valid file it prints `[DRY RUN] Would upload: ...`, unless `-Silent` is enabled.

It sends **no network requests** and performs no upload delays or retry waits. It still requires a nonblank API key to check the same configuration path as a real run.

A successful dry run confirms local preparation only. It cannot verify API-key validity, network access, account permissions, server-side image validation, or current service limits.

## Upload behavior and server load

- Uses one upload request at a time; there are no parallel uploads.
- Sends the key and Base64 image in a form-encoded POST body to the fixed HTTPS endpoint. The filename without its extension is supplied as the image name.
- By default, waits a random whole number of seconds from **3 through 6** before every request after the first, including retry requests. Only `-WaitTime Off` disables this ordinary delay. The effective setting is shown at startup unless `-Silent` is enabled.
- Uses a request timeout setting of 60 seconds and disables redirects.
- Makes at most **four attempts per file**: the initial request plus three retries.
- Retries transport failures without an HTTP response and statuses `408`, `429`, `500`, `502`, `503`, and `504`.
- Adds retry backoff of **5, 10, and 20 seconds**, respectively, plus 0–3 seconds of random jitter. The ordinary 3–6 second request delay also applies before the next attempt unless disabled with `-WaitTime Off`. Backoff itself is never disabled by this parameter.
- Uses the larger of the backoff and a valid `Retry-After` value. Both delay-seconds and HTTP-date forms are handled. Missing or unparseable values fall back to backoff.
- Stops the entire run when transient retries are exhausted, or when status `401` or `403` is received.

Other unsuccessful responses are treated as permanent per-file failures and processing continues. The current implementation does not inspect server error text: a credential problem reported under another status, such as `400`, may therefore be handled as a per-file rejection.

There is no guaranteed request rate that prevents a service from flagging automation. This script does not disguise automation or bypass limits. If the service rejects requests, investigate before restarting or reducing delays.

With the default random waiting, 1,000 files involve roughly 75 minutes of ordinary inter-request waiting alone, plus upload time and any retries. There is no resume state or deduplication. Re-running uploads the files again; retrying after a lost response can also create duplicates.

No automatic expiration is requested. Retention remains subject to the service's behavior and policies.

## Output and colors

| Output | Color | Meaning |
| --- | --- | --- |
| Start, summary, `[DRY RUN]` | Cyan | Status or local preview |
| `[UPLOAD n/4]` | White | Upload attempt |
| `[SUCCESS]` | Green | Successful upload, followed by its returned image URL |
| `[RETRY]` | Yellow | Waiting before another attempt |
| `[ERROR] [SKIP]` | Yellow | Local file preparation failed; continue with the next file |
| `[ERROR]` | Red | Request failure, configuration problem, or stopped run |

Ordinary messages use `Write-Host`. Error and skip messages use plain .NET standard error rather than PowerShell error records, so there are no script-generated error blocks with source lines. Colors depend on the terminal; redirected standard error receives no added color codes. Text labels remain usable without color.

`-Silent` leaves error and skip messages visible, including failed attempts that later succeed. It suppresses the success URLs and final summary. The script does not return structured result objects or write a results file.

## Failures, summaries, and exit codes

An empty, oversized, unreadable, or unencodable image produces a skip message. The file counts as failed, and processing continues. Size failures report the byte count; other preparation failures report the underlying exception type without dumping the exception or image contents.

A missing/inaccessible directory, enumeration failure, access-denied API status, or exhausted transient retries stops the run. A recursive scan can stop if it encounters an inaccessible directory. Files already uploaded remain uploaded.

The normal summary contains `processed`, `uploaded`, and `failed` counts. In dry-run mode, `ready` replaces `uploaded`. A stopped run counts only files reached before the stop; it does not count the unvisited remainder. Some configuration failures occur before a summary can be printed.

| Exit code | Meaning |
| --- | --- |
| `0` | No failed files or run-level failure, including when no matching images exist. |
| `1` | One or more failed/skipped files, missing API key, or a run-level failure. |

Check the exit code immediately after execution:

```powershell
.\Upload-ImagesToImgBB.ps1 -DirectoryPath 'C:\Images' -DryRun
$LASTEXITCODE
```

Invoke the script normally or in a separate PowerShell process; do not dot-source it, because it uses `exit`. Use `Ctrl+C` to interrupt. Cancellation is not a normal completed run and does not guarantee the documented completion summary or exit code.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| API key missing | Set `IMGBB_API_KEY` in the same session or provide `-ApiKey`. Dry runs also require a key. |
| No matching files | Check the path, extensions, hidden attributes, and whether `-Recurse` is needed. |
| Size skip | Confirm the file is nonempty and at or below the script's 32 MiB threshold. |
| Cannot read or encode | Check the reported exception type, file permissions, availability, locks, and memory. |
| `401` or `403` | Check key validity and service/account access before restarting. |
| `429` | Allow the requested wait. If retries are exhausted, investigate service limits before restarting. |
| Transport failure or server errors | Check connectivity, DNS, proxy settings, and service availability. |
| No success URLs | Remove `-Silent`. URLs are displayed only; there is no result export. |
| Script execution blocked | Inspect local execution policy and the downloaded file's trust status. Review the script before using environment-appropriate remedies; no global policy change is required by this project. |

Do not paste real API keys or request bodies into bug reports. A useful report includes the PowerShell version (`$PSVersionTable.PSVersion`), operating system, sanitized command, error message, file size, and whether dry run reproduces the issue.

## Security and privacy

The source contains no real credentials. The script does not intentionally print keys, raw request bodies, or raw server error bodies. Paths and returned image URLs do appear in normal output; review logs before sharing them.

Uploads transmit original file contents to a third-party service. The script does not strip EXIF or other embedded metadata. Upload only images you intend to share and are entitled to upload. An uploaded image is not a private backup merely because its URL has not been shared.

The environment variable and caller-supplied key variable are not cleared by the script. To remove the session environment variable afterward:

```powershell
Remove-Item Env:IMGBB_API_KEY -ErrorAction SilentlyContinue
```

On Windows PowerShell 5.1, the script temporarily enables TLS 1.2 alongside the existing protocol settings and restores the original setting in its cleanup block.

## Development and validation

This is a hobby utility. The current version has received static review, but has not been runtime-tested in the authoring environment because PowerShell was unavailable. End-to-end uploads and cross-version compatibility remain to be verified.

Before relying on it for a large batch:

1. Run a dry run on a small directory, including an empty file and a nested directory.
2. Confirm that `-Recurse`, `-Silent`, skip messages, colors, and exit codes behave as expected in your terminal. In a mocked upload test, verify that `-WaitTime Off` skips only ordinary delays, while omitted/invalid values retain them and retry waits remain active.
3. Upload a small, non-sensitive test image and check the returned URL.
4. Validate retry and failure paths using mocks or a controlled test harness rather than deliberately overloading the live service.

Keep contributions readable and limited in scope. Include behavior changes in the built-in help and this README. Never commit real keys, private images, or sensitive logs.

## License

The script is licensed under the **MIT License** and contains its full license text and SPDX identifier. Preserve the copyright and permission notice when redistributing it. For a repository, the same license text can also be placed in a top-level `LICENSE` file.

This hobby project is not affiliated with or endorsed by ImgBB. The software license does not replace the service's terms or the rights attached to uploaded images.
