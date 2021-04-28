[CmdLetBinding()]
param(
    [Parameter (Position = 0)]
    [string]$SolutionName,
    [Parameter (Position = 1)]
    [string]$SourceFolder,
    [Parameter (Position = 2)]
    [String]$TargetPath,
    [Parameter (Position = 3)]
    [String]$ToolPath
)

function main{
    param(
        [Parameter (Position = 0)]
        [string]$solutionName,
        [Parameter (Position = 1)]
        [string]$sourceFolder,
        [Parameter (Position = 2)]
        [string]$targetPath,
        [Parameter (Position = 3)]
        [String]$toolPath
    )
    
    Write-Verbose "Packaging Solution $solutionName"

    if ($null -eq $toolPath -or $toolPath -eq ''){
        $solPackagerPath = "$PSScriptRoot\tools\SolutionPackager.exe"
    }
    else {
        $solPackagerPath = "$toolPath\SolutionPackager.exe"
    }

    if ($null -eq $sourceFolder -or $sourceFolder -eq '') {
        $sourceFolder = "$PSScriptRoot\solutions\"
    }

    Write-Verbose "Source path: $sourceFolder"
    Write-Verbose "Target Path: $targetPath"
    Write-Verbose "Toolpath: $toolPath"
    
    Set-Alias sol-packager $solPackagerPath -Scope Script
    
    $solutionPath = Join-Path -Path $sourceFolder -ChildPath $solutionName
    if(-Not (Test-Path $solutionPath)){
        Write-Error "Path for Solution: $solutionName does not exist at $solutionPath"
        return 
    }
    Write-Debug "Working with solution: $solutionName"

    $solutionInfo = Get-SolutionVersion $solutionPath

    #Set Solution Name
    $unmanagedSolutionName = ($solutionInfo.uniqueSolutionName, ($solutionInfo.solutionVersion -replace "\.", "_") -join "_")+".zip"
    $managedSolutionName = ($solutionInfo.uniqueSolutionName, ($solutionInfo.solutionVersion -replace "\.", "_"), 'managed' -join '_')+"zip"

    sol-packager /a:pack /z: (Join-Path -Path $targetPath -ChildPath $unmanagedSolutionName) /p:both /f: $solutionPath  /e:verbose /l:pack.log /src /loc
    
    [hashtable]$result = @{
        "ManagedSolutionPath" = (Join-Path -Path $targetPath -ChildPath $managedSolutionName)
        "UnmanagedSolutionPath" = (Join-Path -Path $targetPath -ChildPath $unmanagedSolutionName)
    }
    return $result
}

function Get-SolutionVersion{
    param(
        [Parameter (Mandatory, Position = 0)]
        [string]$solutionPath
    )
    [hashtable]$return = @{}

    [XML]$solutionXml = Get-Content -Path (Join-Path -Path $solutionPath -ChildPath "Other\Solution.xml")
    $return.uniqueSolutionName = ($solutionXml | Select-Xml -XPath "/ImportExportXml/SolutionManifest/UniqueName").Node.'#text'
    $return.solutionVersion = ($solutionXml | Select-Xml -XPath "/ImportExportXml/SolutionManifest/Version").Node.'#text'
    return $return
}

$ErrorActionPreference = "Stop"
main $SolutionName $SourceFolder $TargetPath $ToolPath
