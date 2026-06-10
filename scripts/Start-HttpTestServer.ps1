# ==============================================================================
# Start-HttpTestServer.ps1
# Lab 2 — Exercise C: Cleartext Credential Capture (HTTP)
#
# PURPOSE:
#   Launches a minimal HTTP server on localhost:8080 that serves a login form.
#   Submit the form with test credentials while Wireshark is capturing on the
#   loopback interface to observe plaintext username/password in an HTTP POST.
#
# USAGE:
#   Run from an elevated PowerShell session:
#     .\Start-HttpTestServer.ps1
#
#   Then in Wireshark:
#     - Capture on "Loopback: lo" (Mac/Linux) or "Adapter for loopback traffic
#       capture" (Windows Npcap loopback adapter)
#     - Filter: http.request.method == POST
#
#   To stop the server: press Ctrl+C in this terminal window.
#
# SECURITY NOTE:
#   This server is intentionally insecure — it has no TLS, no authentication,
#   and no input validation. It exists only to generate observable HTTP POST
#   traffic for educational packet capture analysis. Never expose port 8080
#   to a production network.
# ==============================================================================

$port     = 8080
$url      = "http://localhost:$port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($url)

# HTML login form served on GET /
$loginPage = @"
<!DOCTYPE html>
<html>
<head>
  <title>Test Login — HTTP Only</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 400px; margin: 80px auto; }
    input { display: block; width: 100%; margin: 8px 0; padding: 8px; font-size: 14px; }
    button { padding: 10px 20px; background: #0078d4; color: white; border: none;
             font-size: 14px; cursor: pointer; width: 100%; }
    .notice { background: #fff3cd; border: 1px solid #ffc107; padding: 10px;
              margin-bottom: 16px; font-size: 13px; }
  </style>
</head>
<body>
  <h2>Test Login Form (HTTP)</h2>
  <div class="notice">
    ⚠ This form transmits credentials in plaintext over HTTP.<br>
    Capture on loopback in Wireshark to observe the POST body.
  </div>
  <form method="POST" action="/login">
    <label>Username</label>
    <input type="text" name="username" placeholder="testuser" />
    <label>Password</label>
    <input type="text" name="password" placeholder="TestPassword123"
           style="font-family:monospace;" />
    <button type="submit">Submit (HTTP POST)</button>
  </form>
</body>
</html>
"@

# Response page served after form submission
$responsePage = @"
<!DOCTYPE html>
<html>
<body style="font-family:Arial;max-width:400px;margin:80px auto;">
  <h2>POST received</h2>
  <p>Credentials were submitted over HTTP. Check Wireshark for the plaintext POST body.</p>
  <p><a href="/">Submit again</a></p>
</body>
</html>
"@

try {
    $listener.Start()
    Write-Host ""
    Write-Host "HTTP test server running at $url" -ForegroundColor Green
    Write-Host "Open a browser and navigate to: $url" -ForegroundColor Cyan
    Write-Host "In Wireshark, capture on the loopback interface." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop the server." -ForegroundColor Yellow
    Write-Host ""

    while ($listener.IsListening) {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        $method = $request.HttpMethod
        $path   = $request.Url.AbsolutePath

        Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] $method $path"

        if ($method -eq "POST" -and $path -eq "/login") {
            # Read the raw POST body — this is what Wireshark will capture in plaintext
            $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
            $body   = $reader.ReadToEnd()
            $reader.Close()

            Write-Host "  POST body: $body" -ForegroundColor Magenta

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responsePage)
            $response.ContentType   = "text/html; charset=utf-8"
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($loginPage)
            $response.ContentType   = "text/html; charset=utf-8"
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }

        $response.Close()
    }
} catch [System.Net.HttpListenerException] {
    # Normal on Ctrl+C
} finally {
    $listener.Stop()
    Write-Host "`nServer stopped." -ForegroundColor Yellow
}
