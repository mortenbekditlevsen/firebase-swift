# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runs one XCTest test straight from the built test binary under cdb, as
# `swift test` hides how the process ended: prints the stacks of the C++
# exceptions it throws and of the crash or exit. The binary's debug info is
# DWARF, which cdb can't read, so llvm-symbolizer then names the test
# binary's frames.
#
#   pwsh -File .github/scripts/debug-crash.ps1 <Module.Class/testMethod>

param([Parameter(Mandatory)][string]$Test)

$bin = Get-ChildItem .build -Recurse -Filter 'firebase-swiftPackageTests.xctest' | Select-Object -First 1
if (-not $bin) { Write-Host "No test binary under .build"; exit 1 }

# XCTest.dll and Testing.dll, which `swift test` puts on the path: somewhere
# in the Swift installation, five levels above
# ...\Toolchains\<version>\usr\bin\swift.exe.
$swiftRoot = (Get-Command swift).Source
foreach ($i in 1..5) { $swiftRoot = Split-Path $swiftRoot }
$dirs = Get-ChildItem $swiftRoot -Recurse -Include XCTest.dll, Testing.dll -ErrorAction SilentlyContinue |
  Where-Object { $_.DirectoryName -match 'bin64$' } | ForEach-Object DirectoryName | Sort-Object -Unique
Write-Host "Test libraries: $dirs"
$env:Path = ((@($dirs) + $bin.DirectoryName) -join ';') + ';' + $env:Path

$cdb = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe"
if (-not (Test-Path $cdb)) { Write-Host "No cdb at $cdb"; exit 0 }
# Logs each C++ throw and goes on; stops at a crash, or at the exit. (The
# binary's .xctest extension keeps it from running straight from PowerShell,
# which would hand it to the shell.)
$commands = 'sxe -c "kn 40; g" eh; bp ntdll!RtlExitUserProcess; g; .lastevent; .exr -1; ' +
  'kn 80; lm m firebase*; q'
$output = & $cdb -G -c $commands $bin.FullName $Test
$output | Write-Host

# The return addresses in the test binary on the last stack (the crash's or
# the exit's), as offsets from where it loaded.
$last = @($output | Select-String '^Last event:')
if (-not $last) { exit 0 }
$stack = $output | Select-Object -Skip $last[-1].LineNumber
$module = $output | Select-String '^([0-9a-f`]+) ([0-9a-f`]+)\s+firebase_swiftPackageTests' | Select-Object -Last 1
if (-not $module) { exit 0 }
$start = [UInt64]::Parse($module.Matches[0].Groups[1].Value.Replace('`', ''), 'HexNumber')
$end = [UInt64]::Parse($module.Matches[0].Groups[2].Value.Replace('`', ''), 'HexNumber')
$offsets = foreach ($frame in $stack | Select-String '^[0-9a-f]{2} [0-9a-f`]+ ([0-9a-f`]+) ') {
  $address = [UInt64]::Parse($frame.Matches[0].Groups[1].Value.Replace('`', ''), 'HexNumber')
  # One byte back, into the call.
  if ($address -gt $start -and $address -lt $end) { '0x{0:x}' -f [UInt64]($address - $start - 1) }
}
$symbolizer = Get-Command llvm-symbolizer -ErrorAction SilentlyContinue
if (-not $symbolizer) { Write-Host "No llvm-symbolizer; offsets: $offsets"; exit 0 }
Write-Host "The test binary's frames, innermost first:"
& $symbolizer.Source --obj=$($bin.FullName) --relative-address --pretty-print --demangle @offsets | Write-Host
