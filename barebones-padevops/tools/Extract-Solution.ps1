param(
    [Parameter (Position = 0)]
        [string]$SolutionName,
        [Parameter (Position = 1)]
        [string]$TargetFolder,
        [Parameter (Position = 2)]
        [String]$ToolPath,
        [Parameter (Position = 3)]
        [int]$Timeout = 9000
    )

function main {
    param(
    [Parameter (
        Position = 0)]
        [string]$solutionName,
        [Parameter (Position = 1)]
        [string]$targetFolder,
        [Parameter (Position = 2)]
        [String]$toolPath,
        [Parameter (Position = 3)]
        [int]$timeout = 9000
    )
    $ErrorActionPreference = "Stop"

    if (-not (Get-Module -ListAvailable -Name "Microsoft.Xrm.Tooling.CrmConnector.Powershell")){
        Write-Verbose "CRM Connector Powershell module not installed. Installing..."
        Install-Module "Microsoft.Xrm.Tooling.CrmConnector.Powershell" -Repository PSGallery -Force
    }
    if (-not (Get-Module -ListAvailable -Name "Microsoft.Xrm.Data.Powershell")){
        Write-Verbose "Xrm Data Powershell module not installed. Installing..."
        Install-Module "Microsoft.Xrm.Data.Powershell" -AllowClobber -Repository PSGallery -Force
    }
    
    Import-Module "Microsoft.Xrm.Tooling.CrmConnector.Powershell"
    Import-Module "Microsoft.Xrm.Data.Powershell"

    if ($null -eq $toolPath -or $toolPath -eq ''){
        $solPackagerPath = "$PSScriptRoot\tools\SolutionPackager.exe"
    }
    else {
        $solPackagerPath = "$toolPath\SolutionPackager.exe"
    }

    if ($null -eq $targetFolder -or $targetFolder -eq '') {
        $targetFolder = "$PSScriptRoot\solutions\"
    }
    #Create base folder if not exists
    if(!(Test-Path -path $targetFolder)){
        New-Item -ItemType Directory -Path $targetFolder
    }

    Set-Alias sol-packager $solPackagerPath -Scope Script
    
    connect-crmwithtimeoutinteractive
    
    Write-Verbose "Trying to set timeout to: $timeout"
    Set-CrmConnectionTimeout -conn $conn -TimeoutInSeconds $timeout
    
    ##########
    ## debug because the debugger plays with the connection timeout
    ##########
    Write-Verbose "Connection timeout is: $($conn.OrganizationWebProxyClient.ChannelFactory.Endpoint.Binding.SendTimeout)"
    Write-Verbose "Receive Timeout is $($conn.OrganizationWebProxyClient.ChannelFactory.Endpoint.Binding.ReceiveTimeout)"

    $user = Invoke-CrmWhoAmI -conn $conn
    
    Write-Verbose ("UserId "+$user.UserId.Guid)
    Write-Verbose ("BusinessUnitId "+$user.BusinessUnitId.Guid)

    # Publish Solution
    Write-Verbose "Publishing Customizations..."
    Publish-CrmAllCustomization -conn $conn

    Write-Verbose "Downloading Solution: $solutionName"
    $solutionNames = Get-Solution -conn $conn -uniqueSolutionName $solutionName

    Write-Verbose "Extracting Solution: $solutionName"
    Expand-Solution -uniqueSolutionName $solutionName -targetFolder $targetFolder -managedSolutionName $solutionNames[3] -unmanagedSolutionName $solutionNames[2]

    $conn = $null;
}

function connect-crmwithtimeoutinteractive{
    $global:conn = Get-CrmConnection -InteractiveMode -Verbose -MaxCrmConnectionTimeOutMinutes 120
    Write-Verbose "You are now connected and may run any of the CRM Commands."
    return $global:conn
}
function Expand-Solution{
    param(
        [Parameter(Mandatory=$true)]
        [string]$uniqueSolutionName,
        [Parameter(Mandatory=$true)]
        [string]$targetFolder,
        [Parameter(Mandatory=$true)]
        [string]$unmanagedSolutionName,
        [Parameter(Mandatory=$true)]
        [string]$managedSolutionName
    )
    $extractFolder = join-path -Path $targetFolder -ChildPath $uniqueSolutionName
    # Extract Both manged and unmanaged
    sol-packager /a:extract /z: (Join-Path -Path $targetFolder -ChildPath $unmanagedSolutionName) /p:both /f: $extractFolder  /e:verbose /l:unpack.log /aw:yes /ad:yes /src
    
    # Replace en-US with template RESX
    if ( Test-Path $extractFolder+'Resources\en-US\resources.en-US.resx'){
        Write-Verbose "Removing en-US resource file..."
        Remove-Item -Path ($extractFolder+'Resources\en-US\resources.en-US.resx')
        Write-Verbose "Copying template to en-US..."
        Copy-Item -Path ($extractFolder+'Resources\template_resources.resx') -Destination ($extractFolder+'Resources\en-US\resources.en-US.resx')
    }
    
    # Delete zip files
    Remove-Item -Force -Confirm:$false -Path $(Join-Path -Path $targetFolder -ChildPath $unmanagedSolutionName)
    Remove-Item -Force -Confirm:$false -Path $(Join-Path -Path $targetFolder -ChildPath $managedSolutionName)
    #git add -A
    #git commit -m "Automatically added all files"
    #git push origin master
}
function Get-Solution{
    param(
        [parameter(Mandatory=$true)]
        [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$conn, 
        [Parameter(Mandatory=$true)]
        [string]$uniqueSolutionName
    )
    
    Write-Verbose "Getting Solution Data"
    $targetSolutions = Get-CrmRecords -conn $conn -EntityLogicalName 'solution' -FilterAttribute 'uniquename' -FilterOperator 'eq' -FilterValue $uniqueSolutionName -Fields @('solutionid', 'uniquename', 'friendlyname', 'ismanaged', 'version')
    
    Write-Verbose ("Target Solution: "+$targetSolutions.CrmRecords[0].uniquename+" v"+$targetSolutions.CrmRecords[0].version+" ("+$targetSolutions.CrmRecords[0].friendlyname+")")
    
    $unmanagedSolutionName = ($targetSolutions.CrmRecords[0].uniquename, ($targetSolutions.CrmRecords[0].version -replace "\.", "_") -join "_")+".zip"
    $managedSolutionName = ($targetSolutions.CrmRecords[0].uniquename, ($targetSolutions.CrmRecords[0].version -replace "\.", "_"), "managed" -join "_")+".zip"

    Write-Verbose ("Unmanaged Path: $(Join-Path -Path $targetFolder -ChildPath $unmanagedSolutionName)")
    Write-Verbose ("Managed Path: $(Join-Path -Path $targetFolder -ChildPath $managedSolutionName)")
    
    if ((Test-Path -LiteralPath ($targetFolder + $unmanagedSolutionName)) -And (Test-Path -LiteralPath ($targetFolder + $managedSolutionName))  ) {
        if (Test-Path -LiteralPath ($targetFolder+$unmanagedSolutionName)) {
            Remove-Item ($targetFolder+$unmanagedSolutionName) -Recurse -Force -Confirm:$false
        }
        if (Test-Path -LiteralPath ($targetFolder+$managedSolutionName)) {
            Remove-Item ($targetFolder+$managedSolutionName) -Recurse -Force -Confirm:$false
        }
    }

    # Export Unmanaged/managed
    Write-Verbose ("Exporting "+$targetSolutions.CrmRecords[0].uniquename+" (unmanaged)...")
    Export-CrmSolution -conn $conn $targetSolutions.CrmRecords[0].uniquename -SolutionFilePath $targetFolder -SolutionZipFileName $unmanagedSolutionName
    Write-Verbose "Done"
    Write-Verbose ("Exporting "+$targetSolutions.CrmRecords[0].uniquename+" (managed)...")
    Export-CrmSolution -conn $conn $targetSolutions.CrmRecords[0].uniquename -SolutionFilePath $targetFolder -SolutionZipFileName $managedSolutionName -Managed
    Write-Verbose "Done getting files from server"

    return $unmanagedSolutionName, $managedSolutionName
}


$VerbosePreference="Continue"
main $SolutionName $TargetFolder $ToolPath $Timeout
