# Stop script execution when a non-terminating error occurs
$ErrorActionPreference = "Stop"


$channel = "$Env:CHANNEL"
If ([string]::IsNullOrEmpty($channel)) { $channel = "unstable" }

$product = "$Env:PRODUCT"
If ([string]::IsNullOrEmpty($product)) { $product = "chef" }

$version = "$Env:VERSION"
If ([string]::IsNullOrEmpty($version)) { $version = "latest" }

Write-Output "--- Installing $channel $product $version"
$package_file = $(C:\opscode\omnibus-toolchain\bin\install-omnibus-product.ps1 -Product "$product" -Channel "$channel" -Version "$version" | Select-Object -Last 1)

Write-Output "--- Verifying omnibus package is signed"
C:\opscode\omnibus-toolchain\bin\check-omnibus-package-signed.ps1 "$package_file"

Write-Output "--- Running verification for $channel $product $version"

# We don't want to add the embedded bin dir to the main PATH as this
# could mask issues in our binstub shebangs.
$embedded_bin_dir = "C:\opscode\$product\embedded\bin"

# Set TEMP and TMP environment variables to a short path because buildkite-agent user's default path is so long it causes tests to fail
$Env:TEMP = "C:\cheftest"
$Env:TMP = "C:\cheftest"
Remove-Item -Recurse -Force $Env:TEMP -ErrorAction SilentlyContinue
New-Item -ItemType directory -Path $Env:TEMP

# FIXME: we should really use Bundler.with_unbundled_env in the caller instead of re-inventing it here
Remove-Item Env:_ORIGINAL_GEM_PATH -ErrorAction SilentlyContinue
Remove-Item Env:BUNDLE_BIN_PATH -ErrorAction SilentlyContinue
Remove-Item Env:BUNDLE_GEMFILE -ErrorAction SilentlyContinue
Remove-Item Env:GEM_HOME -ErrorAction SilentlyContinue
Remove-Item Env:GEM_PATH -ErrorAction SilentlyContinue
Remove-Item Env:GEM_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:RUBYLIB -ErrorAction SilentlyContinue
Remove-Item Env:RUBYOPT -ErrorAction SilentlyContinue
Remove-Item Env:RUBY_ENGINE -ErrorAction SilentlyContinue
Remove-Item Env:RUBY_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:RUBY_VERSION -ErrorAction SilentlyContinue
Remove-Item Env:BUNDLER_VERSION -ErrorAction SilentlyContinue

$Env:PATH = "C:\opscode\$product\bin;$Env:PATH"

chef-client --version

# Exercise various packaged tools to validate binstub shebangs
& $embedded_bin_dir\ruby --version
& $embedded_bin_dir\gem.bat --version
& $embedded_bin_dir\bundle.bat --version
& $embedded_bin_dir\rspec.bat --version

$Env:PATH = "C:\opscode\$product\bin;C:\opscode\$product\embedded\bin;$Env:PATH"

# Test against the vendored chef gem (cd into the output of "gem which chef")
$chefdir = gem which chef
$chefdir = Split-Path -Path "$chefdir" -Parent
$chefdir = Split-Path -Path "$chefdir" -Parent
Set-Location -Path $chefdir

Get-Location

# ffi-yajl must run in c-extension mode for perf, so force it so we don't accidentally fall back to ffi
$Env:FORCE_FFI_YAJL = "ext"

# accept license
$Env:CHEF_LICENSE = "accept-no-persist"

bundle
If ($lastexitcode -ne 0) { Exit $lastexitcode }

# buildkite changes the casing of the Path variable to PATH
# It is not clear how or where that happens, but it breaks the choco
# tests. Removing the PATH and resetting it with the expected casing
$p = $env:PATH
$env:PATH = $null
$env:Path = $p

# Running the specs separately fixes an edge case on 2012R2-i386 where the desktop heap's
# allocated limit is hit and any test's attempt to create a new process is met with
# exit code -1073741502 (STATUS_DLL_INIT_FAILED). after much research and troubleshooting,
# desktop heap exhaustion seems likely (https://docs.microsoft.com/en-us/archive/blogs/ntdebugging/desktop-heap-overview)
$exit = 0

Get-ChildItem Env:

(Get-Counter '\Process(*)\% Processor Time').CounterSamples | Where-Object {$_.CookedValue -gt 5}

bundle exec rspec -f progress --profile -- ./spec/unit/provider/systemd_unit_spec.rb
If ($lastexitcode -ne 0) { $exit = 1 }

Exit $exit
