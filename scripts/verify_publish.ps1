param([string]$ReferenceRoot='')
$ErrorActionPreference='Stop'
$webRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $webRoot 'slide_simple_renesas_isp_tool\scripts\verify_publish.ps1'))
if($ReferenceRoot) { $arguments+=@('-ReferenceRoot',$ReferenceRoot) }
& powershell.exe @arguments
if($LASTEXITCODE) { throw 'Shared device/Tool publication checks failed.' }
