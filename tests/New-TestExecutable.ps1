# Compile a harmless native-command stand-in using the Windows .NET Framework.
param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$sourcePath = [IO.Path]::ChangeExtension($Path, '.cs')
[IO.File]::WriteAllText($sourcePath, $Source)
& $compiler /nologo /target:exe "/out:$Path" $sourcePath
if ($LASTEXITCODE -ne 0) { throw "Fixture compilation failed for $Path (exit $LASTEXITCODE)." }
