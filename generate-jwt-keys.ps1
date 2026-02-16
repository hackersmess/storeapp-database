# Script PowerShell per generare chiavi RSA per JWT
Add-Type -AssemblyName System.Security

# Crea RSA 2048-bit
$rsa = [System.Security.Cryptography.RSA]::Create(2048)

# Esporta chiave privata in formato PKCS#8 (PEM)
$privateKeyBytes = $rsa.ExportPkcs8PrivateKey()
$privateKeyBase64 = [Convert]::ToBase64String($privateKeyBytes)
$privateKeyPem = "-----BEGIN PRIVATE KEY-----`n"
for ($i = 0; $i -lt $privateKeyBase64.Length; $i += 64) {
    $line = $privateKeyBase64.Substring($i, [Math]::Min(64, $privateKeyBase64.Length - $i))
    $privateKeyPem += "$line`n"
}
$privateKeyPem += "-----END PRIVATE KEY-----`n"

# Esporta chiave pubblica in formato X.509 (PEM)
$publicKeyBytes = $rsa.ExportSubjectPublicKeyInfo()
$publicKeyBase64 = [Convert]::ToBase64String($publicKeyBytes)
$publicKeyPem = "-----BEGIN PUBLIC KEY-----`n"
for ($i = 0; $i -lt $publicKeyBase64.Length; $i += 64) {
    $line = $publicKeyBase64.Substring($i, [Math]::Min(64, $publicKeyBase64.Length - $i))
    $publicKeyPem += "$line`n"
}
$publicKeyPem += "-----END PUBLIC KEY-----`n"

# Salva i file
$resourcesPath = "src\main\resources"
Set-Content -Path "$resourcesPath\jwt-private-key.pem" -Value $privateKeyPem -NoNewline
Set-Content -Path "$resourcesPath\jwt-public-key.pem" -Value $publicKeyPem -NoNewline

Write-Host "✅ Chiavi JWT generate con successo!" -ForegroundColor Green
Write-Host "📁 Salvate in: $resourcesPath" -ForegroundColor Cyan
