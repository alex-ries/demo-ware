param (
    [parameter(Position = 0)]
    [string]$BasePath
)

function main {
    param (
        [parameter(Position = 0)]
        [string]$basePath
    )
    if (!(Test-Path alias:nuget)) {
        Get-LatestNuget
    }
    $tempPath = "$PSScriptRoot\temp\"
    if (!(Test-Path $tempPath)) {
        mkdir $tempPath
    }
    if (!($basePath)) {
        $basePath = "$PSScriptRoot\tools\"
    }
    Write-Debug $tempPath
    Write-Debug $basePath
    Get-CoreTools $tempPath $basePath

}

function Get-LatestNuget {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $sourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    $targetNugetExe = "$PSScriptRoot\nuget.exe"
    Invoke-WebRequest $sourceNugetExe -OutFile $targetNugetExe
    Set-Alias nuget $targetNugetExe -Scope Script -Verbose
}

function Get-CoreTools {
    param (
        [parameter(Position = 0)]
        [string]$tempPath,
        [parameter(Position = 1)]
        [string]$basePath
    )
    Write-Verbose "Installing Microsoft.CrmSdk.CoreTools with NuGet"
    nuget install  Microsoft.CrmSdk.CoreTools -O $tempPath
    $coreToolsFolder = Get-ChildItem $tempPath | Where-Object {$_.Name -match "Microsoft.CrmSdk.CoreTools."}
    Write-Verbose "Source Path: $tempPath\$coreToolsFolder\content\bin\coretools\*.*"
    Write-Verbose "Target Path: $basePath"
    move-item -Path "$($tempPath)$($coreToolsFolder)\content\bin\coretools\" -Destination "$basePath" -Force
    Remove-Item "$tempPath" -Force -Recurse
}

$ErrorActionPreference = "Stop"
main $BasePath