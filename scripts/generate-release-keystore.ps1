# Generate Release Keystore for Play Store
# Run this script from the project root directory
# PowerShell script for Windows

param(
    [SecureString]$KeystorePassword,
    [string]$KeyAlias = "upload",
    [string]$OutputDir = "../android"
)

# Change to the script directory (project root)
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AndroidDir = Join-Path $ProjectRoot "android"
$KeystoreFile = Join-Path $AndroidDir "upload-keystore.jks"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Release Keystore Generator for Play Store" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for keystore password if not provided
$plainPassword = ""
if ($null -ne $KeystorePassword) {
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KeystorePassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
} else {
    $securePassword = Read-Host "Enter a strong password for your keystore (min 6 characters)" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

if ([string]::IsNullOrEmpty($plainPassword) -or $plainPassword.Length -lt 6) {
    Write-Host "Error: Password must be at least 6 characters long." -ForegroundColor Red
    exit 1
}

# Prompt for distinguished name details
Write-Host ""
Write-Host "Enter your details for the certificate (press Enter to use defaults):" -ForegroundColor Yellow
$cn = Read-Host "  Your Full Name [TryOn Clothes AI]"
if ([string]::IsNullOrEmpty($cn)) { $cn = "TryOn Clothes AI" }

$ou = Read-Host "  Organizational Unit [Development]"
if ([string]::IsNullOrEmpty($ou)) { $ou = "Development" }

$o = Read-Host "  Organization [TryOn Clothes AI]"
if ([string]::IsNullOrEmpty($o)) { $o = "TryOn Clothes AI" }

$l = Read-Host "  City/Locality [City]"
if ([string]::IsNullOrEmpty($l)) { $l = "City" }

$st = Read-Host "  State/Province [State]"
if ([string]::IsNullOrEmpty($st)) { $st = "State" }

$c = Read-Host "  Country Code (2 letters) [IN]"
if ([string]::IsNullOrEmpty($c)) { $c = "IN" }

$dname = "CN=$cn, OU=$ou, O=$o, L=$l, ST=$st, C=$c"

Write-Host ""
Write-Host "Generating keystore..." -ForegroundColor Green

# Remove existing keystore if present
if (Test-Path $KeystoreFile) {
    Remove-Item $KeystoreFile -Force
}

# Generate keystore using keytool
$keytool = "keytool"
$genKeyArgs = @(
    "-genkey", "-v",
    "-keystore", $KeystoreFile,
    "-keyalg", "RSA",
    "-keysize", "2048",
    "-validity", "10000",
    "-alias", $KeyAlias,
    "-storepass", $plainPassword,
    "-keypass", $plainPassword,
    "-dname", $dname
)

try {
    & $keytool $genKeyArgs 2>&1 | Out-Null
    Write-Host "  Keystore created at: $KeystoreFile" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to generate keystore. Make sure Java's keytool is installed." -ForegroundColor Red
    Write-Host "Java is typically installed at: C:\Program Files\Java\jdk-*\bin\keytool.exe" -ForegroundColor Red
    exit 1
}

# Extract SHA-1 fingerprint
Write-Host ""
Write-Host "Extracting SHA-1 fingerprint..." -ForegroundColor Yellow

$sha1Output = & $keytool -list -v -keystore $KeystoreFile -alias $KeyAlias -storepass $plainPassword -keypass $plainPassword 2>&1
$sha1Line = $sha1Output | Select-String "SHA1:" | ForEach-Object { $_.ToString().Trim() }
$sha1ColonFormat = $sha1Line -replace "SHA1:\s*", ""

# Also extract SHA-256 for Google Play / OAuth signing
$sha256Line = $sha1Output | Select-String "SHA256:" | ForEach-Object { $_.ToString().Trim() }
$sha256ColonFormat = $sha256Line -replace "SHA256:\s*", ""

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SHA-1 & SHA-256 Fingerprints" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SHA-1:   $sha1ColonFormat" -ForegroundColor White
Write-Host "  SHA-256: $sha256ColonFormat" -ForegroundColor White
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan

# Create key.properties file
$KeyPropertiesFile = Join-Path $AndroidDir "key.properties"
$keyPropertiesContent = @"
storeFile=upload-keystore.jks
keyAlias=$KeyAlias
storePassword=$plainPassword
keyPassword=$plainPassword
"@

Set-Content -Path $KeyPropertiesFile -Value $keyPropertiesContent -Force
Write-Host ""
Write-Host "key.properties created at: $KeyPropertiesFile" -ForegroundColor Green
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  NEXT STEPS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Build your release APK/AAB:" -ForegroundColor Yellow
Write-Host "   flutter build appbundle --release" -ForegroundColor Yellow
Write-Host "   or" -ForegroundColor Yellow
Write-Host "   flutter build apk --release" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Upload your AAB to Google Play Console (Release > Setup > App Integrity)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Security: Clear the password variable
$plainPassword = ""
if ($null -ne $KeystorePassword) {
    $KeystorePassword.Dispose()
}
