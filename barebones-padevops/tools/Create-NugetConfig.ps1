[CmdLetBinding()]
param(
    [Parameter (Position = 0)]
    [string]$SolutionName,
    [Parameter (Position = 1)]
    [string]$PackageFolder,
    [Parameter (Position = 2)]
    [string]$SolutionPath
)

function main {
    param(
        [Parameter (Position = 0)]
        [string]$solutionName,
        [Parameter (Position = 1)]
        [string]$packageFolder,
        [Parameter (Position = 2)]
        [string]$solutionPath
    )
    Write-Verbose "Creating Package For: $solutionName"
    $solutionData = Get-SolutionVersion $solutionPath
    Write-Verbose "Solution version: $($solutionData.solutionVersion)"
    
    #Create our nuspec file
    $nuspecContent = New-Nuspec $solutionName $($solutionData.solutionVersion)
    $nuspecFilePath = "$packageFolder\$solutionName.nuspec"

    Write-Verbose "Created NuSpec File: $nuspecFilePath"
    Set-Content -path $nuspecFilePath -Value $nuspecContent
}

function New-Nuspec {
    param(
        [Parameter (Mandatory, Position = 0)]
        [string]$solutionName,
        [Parameter (Mandatory, Position = 1)]
        [string]$version
    )
    $version = $version
    $nuspecXml = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
    <metadata>
        <id>$solutionName</id>
        <version>$version</version>
        <description>Managed and unmanaged Dynamics solution files for: $solutionName</description>
        <authors>Alex Ries</authors>
    </metadata>
</package>
"@

    return $nuspecXml
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

main $SolutionName $PackageFolder $SolutionPath