param(
    [string]$ParameterName = "/lab-commit/ca-certificate",
    [string]$Region = "",
    [string]$PemPath = ""
)

$ErrorActionPreference = "Stop"

function Get-InstanceRegion {
    $token = Invoke-RestMethod -Method Put -Uri "http://169.254.169.254/latest/api/token" -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" }
    Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -Headers @{ "X-aws-ec2-metadata-token" = $token }
}

$certFile = Join-Path $env:TEMP "lab-commit-ca.cer"

if ($PemPath) {
    Copy-Item -Path $PemPath -Destination $certFile -Force
} else {
    if (-not $Region) {
        $Region = Get-InstanceRegion
    }
    Import-Module AWS.Tools.SimpleSystemsManagement -ErrorAction SilentlyContinue
    $pem = (Get-SSMParameter -Name $ParameterName -Region $Region).Value
    Set-Content -Path $certFile -Value $pem -Encoding ascii
}

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)
$existing = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }

if ($existing) {
    Write-Output "Already trusted: $($cert.Subject) $($cert.Thumbprint)"
} else {
    Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Output "Imported into Trusted Root: $($cert.Subject) $($cert.Thumbprint)"
}

Remove-Item -Path $certFile -Force
