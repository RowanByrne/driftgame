<#
.SYNOPSIS
  Serves one folder read-only over http on the loopback address, for the Studio MCP upload_image tool,
  then stops itself (docs/workflow/ART-PIPELINE.md "Images", step 5).

.DESCRIPTION
  upload_image takes http URLs, not file paths. This listens on 127.0.0.1 only (never another
  interface), answers GET/HEAD for files inside -Root (no directory listings, no paths outside it),
  prints a URL per image, and stops after -Minutes, after -MaxRequests, or on a request for /__stop.
  Run it in the background, upload, then stop it:  curl http://127.0.0.1:<port>/__stop
  Default port 0 picks a free port and prints it.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\serve-assets.ps1 -Root docs\ui\assets\hud-xp -Minutes 10
#>
param(
	[Parameter(Mandatory = $true)][string]$Root,
	[int]$Port = 0,
	[double]$Minutes = 15,
	[int]$MaxRequests = 0,
	[switch]$Recurse
)
$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
$types = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.webp' = 'image/webp'; '.bmp' = 'image/bmp'; '.tga' = 'image/x-tga' }

$listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), $Port
$listener.Start()
$port = $listener.LocalEndpoint.Port
$base = "http://127.0.0.1:$port"
Write-Output "serve-assets: $rootPath on $base (stops after $Minutes min$(if ($MaxRequests) { " or $MaxRequests requests" }), or GET $base/__stop)"
$opt = @{ LiteralPath = $rootPath; File = $true }
if ($Recurse) { $opt.Recurse = $true }
Get-ChildItem @opt | Where-Object { $types.ContainsKey($_.Extension.ToLowerInvariant()) } | Sort-Object FullName | ForEach-Object {
	$rel = $_.FullName.Substring($rootPath.Length) -replace '\\', '/'
	Write-Output ("  $base/" + (($rel -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'))
}
[Console]::Out.Flush()

function Send($stream, [int]$code, [string]$reason, [string]$type, [byte[]]$body, [bool]$headOnly) {
	$len = if ($body) { $body.Length } else { 0 }
	$head = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $len`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
	$hb = [Text.Encoding]::ASCII.GetBytes($head)
	$stream.Write($hb, 0, $hb.Length)
	if ($body -and -not $headOnly) { $stream.Write($body, 0, $body.Length) }
}

$deadline = (Get-Date).AddMinutes($Minutes)
$served = 0
$stop = $false
try {
	while (-not $stop -and (Get-Date) -lt $deadline) {
		if (-not $listener.Pending()) { Start-Sleep -Milliseconds 50; continue }
		$client = $listener.AcceptTcpClient()
		try {
			$client.ReceiveTimeout = 5000
			$stream = $client.GetStream()
			$buf = New-Object byte[] 8192
			$req = ''
			while ($req -notmatch "`r`n`r`n") {
				$n = $stream.Read($buf, 0, $buf.Length)
				if ($n -le 0) { break }
				$req += [Text.Encoding]::ASCII.GetString($buf, 0, $n)
				if ($req.Length -gt 65536) { break }
			}
			$line = ($req -split "`r`n")[0]
			if ($line -notmatch '^(GET|HEAD) (\S+) HTTP/1\.[01]$') { Send $stream 405 'Method Not Allowed' 'text/plain' ([Text.Encoding]::ASCII.GetBytes('GET or HEAD only')) $false; continue }
			$method = $Matches[1]
			$path = [Uri]::UnescapeDataString(($Matches[2] -split '\?')[0])
			if ($path -eq '/__stop') { Send $stream 200 'OK' 'text/plain' ([Text.Encoding]::ASCII.GetBytes('stopping')) $false; $stop = $true; continue }
			$full = [IO.Path]::GetFullPath((Join-Path $rootPath ($path.TrimStart('/') -replace '/', '\')))
			$ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
			$inside = $full.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)
			$nested = $full.Substring([Math]::Min($full.Length, $rootPath.Length)).Contains('\')
			if (-not $inside -or ($nested -and -not $Recurse) -or -not $types.ContainsKey($ext) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
				Send $stream 404 'Not Found' 'text/plain' ([Text.Encoding]::ASCII.GetBytes('not found')) $false
				Write-Output "  404 $path"
				continue
			}
			Send $stream 200 'OK' $types[$ext] ([IO.File]::ReadAllBytes($full)) ($method -eq 'HEAD')
			$served++
			Write-Output "  $method 200 $path"
			if ($MaxRequests -gt 0 -and $served -ge $MaxRequests) { $stop = $true }
		} catch {
			Write-Output "  error: $($_.Exception.Message)"
		} finally {
			[Console]::Out.Flush()
			$client.Close()
		}
	}
} finally {
	$listener.Stop()
	Write-Output "serve-assets: stopped after $served file(s)."
}
