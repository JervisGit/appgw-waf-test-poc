# Setup Script for Test VM
# Run this script on the test VM after deployment to install certificate and configure hosts file

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$CertificateName,
    
    [Parameter(Mandatory=$true)]
    [string]$AppGatewayIP,
    
    [Parameter(Mandatory=$true)]
    [string]$SynapseFQDN
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Application Gateway WAF POC - VM Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 1: Download and install certificate
Write-Host "`n[1/3] Downloading certificate from Key Vault..." -ForegroundColor Yellow

try {
    # Download certificate as PFX
    $certPath = "$env:TEMP\appgw-cert.cer"
    az keyvault certificate download --vault-name $KeyVaultName --name $CertificateName --file $certPath --encoding DER
    
    Write-Host "Certificate downloaded to: $certPath" -ForegroundColor Green
    
    # Import certificate to Trusted Root Certification Authorities
    Write-Host "`n[2/3] Installing certificate to Trusted Root..." -ForegroundColor Yellow
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $store.Add($cert)
    $store.Close()
    
    Write-Host "✓ Certificate installed successfully!" -ForegroundColor Green
    Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
    
} catch {
    Write-Host "✗ Failed to install certificate: $_" -ForegroundColor Red
    Write-Host "`nMake sure you're logged in with 'az login' and have access to Key Vault" -ForegroundColor Yellow
    exit 1
}

# Step 3: Configure hosts file
Write-Host "`n[3/3] Configuring hosts file..." -ForegroundColor Yellow

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$hostsEntry = "$AppGatewayIP  $SynapseFQDN"

# Check if entry already exists
$hostsContent = Get-Content $hostsPath
if ($hostsContent -match [regex]::Escape($SynapseFQDN)) {
    Write-Host "⚠ Hosts entry already exists, updating..." -ForegroundColor Yellow
    $hostsContent = $hostsContent | Where-Object { $_ -notmatch [regex]::Escape($SynapseFQDN) }
    $hostsContent | Set-Content $hostsPath
}

# Add new entry
Add-Content -Path $hostsPath -Value "`n$hostsEntry"
Write-Host "✓ Hosts file updated!" -ForegroundColor Green
Write-Host "  Entry: $hostsEntry" -ForegroundColor Gray

# Verify
Write-Host "`n[Verification] Testing DNS resolution..." -ForegroundColor Yellow
$resolved = Resolve-DnsName $SynapseFQDN -Type A -DnsOnly -ErrorAction SilentlyContinue
if ($resolved) {
    Write-Host "✓ DNS resolves to: $($resolved.IPAddress)" -ForegroundColor Green
} else {
    Write-Host "⚠ Could not verify DNS resolution (this is OK, hosts file overrides DNS)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nYou can now test in browser:" -ForegroundColor White
Write-Host "  https://$SynapseFQDN" -ForegroundColor Cyan
Write-Host "`nThe certificate should now be trusted and browser won't show warnings." -ForegroundColor White
