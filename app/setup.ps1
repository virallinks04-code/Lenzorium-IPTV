# Windows PowerShell version of setup.sh
Set-Location $PSScriptRoot
flutter create . --org com.lenzorium --project-name lenzorium_player --platforms=android,windows
flutter pub get
Write-Host "Done. Try: flutter run -d windows"
