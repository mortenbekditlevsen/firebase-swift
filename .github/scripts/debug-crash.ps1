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
# exceptions it throws and of the crash or exit.
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

Get-ChildItem $bin.DirectoryName -Filter *.pdb | Sort-Object Length -Descending |
  Select-Object -First 5 | Format-Table Name, Length | Out-String | Write-Host

$cdb = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe"
if (-not (Test-Path $cdb)) { Write-Host "No cdb at $cdb"; exit 0 }
# Logs each C++ throw and goes on; stops at a crash, or at the exit. (The
# binary's .xctest extension keeps it from running straight from PowerShell,
# which would hand it to the shell.)
$commands = 'sxe -c "kn 40; g" eh; bp ntdll!RtlExitUserProcess; g; .lastevent; .exr -1; ' +
  '!sym noisy; kn 80; lm m firebase*; q'
& $cdb -lines -G -y "$($bin.DirectoryName);srv*" -c $commands $bin.FullName $Test
