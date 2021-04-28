[CmdLetBinding()]
param(
    [Parameter (Position = 0)]
    [ValidateSet('Managed', 'Unmanaged')]
    [string]$SolutionType,
    [Parameter (Position = 1)]
    [string]$SolutionName,
    [Parameter (Position = 2)]
    [string]$SolutionPath,
    [Parameter (Position = 3)]
    [string]$AppID,
    [Parameter (Position = 4)]
    [string]$AppSecret,
    [Parameter (Position = 5)]
    [string]$TargetUri,
    [Parameter (Position = 6)]
    [string]$ToolingPath
)

#TODO Address Patch solutions (needs to be addressed first in the artifact)
function main {
    param(
        [Parameter (Position = 0)]
        [ValidateSet('Managed', 'Unmanaged')]
        [string]$solutionType,
        [Parameter (Position = 1)]
        [string]$solutionName,
        [Parameter (Position = 2)]
        [string]$solutionPath,
        [Parameter (Position = 3)]
        [string]$appID,
        [Parameter (Position = 4)]
        [string]$appSecret,
        [Parameter (Position = 5)]
        [string]$targetUri,
        [Parameter (Position = 6)]
        [string]$toolingPath
    )


    if (-not (Get-Module -ListAvailable -Name "Microsoft.Xrm.Tooling.CrmConnector.Powershell")){
        Write-Verbose "CRM Connector Powershell module not installed"
        Install-Module "Microsoft.Xrm.Tooling.CrmConnector.Powershell" -Repository PSGallery -Force
    }
    if (-not (Get-Module -ListAvailable -Name "Microsoft.Xrm.Data.Powershell")){
        Write-Verbose "Xrm Data Powershell module not installed"
        Install-Module "Microsoft.Xrm.Data.Powershell" -AllowClobber -Repository PSGallery -Force
    }

    Import-Module "Microsoft.Xrm.Tooling.CrmConnector.Powershell"
    Import-Module "Microsoft.Xrm.Data.Powershell"

    $connectorPath = join-path -path $toolingPath -childpath 'Microsoft.Xrm.Tooling.Connector.dll'
    Write-Verbose "Connector dll loading from: $connectorPath"
    [System.Reflection.Assembly]::LoadFrom($connectorPath)

    [System.Uri]$myUri = [System.Uri]$targetUri
    [string]$clientId = $appID
    [string]$clientSecret = $appSecret
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]::MaxConnectionTimeout = $(New-TimeSpan -Minutes 30)
    Write-Verbose "Connecting to target environment ."
    Write-Verbose "URL $myUri"
    Write-Verbose "AppId $clientId"
    Write-Verbose "Secret $clientSecret"

    #AuthType=ClientSecret;url=https://devopstest-prd.crm.dynamics.com;ClientId=da3030ad-3992-41ba-a4be-dd42a6c7f5ca;ClientSecret=4myEoz3IgqO5vx-C6jQ0DxTI_-.364_Xo3
    $connectionString = "AuthType=ClientSecret;url=$($myUri);ClientId=$($clientId);ClientSecret=$($clientSecret)"
    Write-Verbose $connectionString

    $global:conn = New-Object -TypeName 'Microsoft.Xrm.Tooling.Connector.CrmServiceClient' -ArgumentList($connectionString)

    Write-Verbose "Uploading Solution $solutionName"

    $uploadFile = if ($uploadType -eq 'Unmanaged') {
        (Get-ChildItem $solutionPath | Where-Object { $_.Name -like "$($solutionName)_*.zip" -and $_.Name -notlike '*_managed.zip' }).FullName
    } Else {
        (Get-ChildItem $solutionPath | Where-Object { $_.Name -like "$($solutionName)*_managed.zip" }).FullName
    }
    
    Write-Verbose "Checking for existing solutions with $solutionName"
    $solutions = Get-CrmRecords -conn $conn solution uniquename "eq" "$solutionName" uniquename,friendlyname -AllRows

    $importAsHolding = $true
    
    if ($solutions.Count -eq 0)
    {
        Write-Verbose "Solution was not imported before, skipping upgrade step later"
        $importAsHolding = $false
    }

    Write-Verbose "Starting Solution Import"
    $solutionImportResult = Import-CrmSolutionAsync -conn $conn -SolutionFilePath $uploadFile -ActivateWorkflows:$true -OverwriteUnManagedCustomizations:$true -ImportAsHoldingSolution:$importAsHolding -MaxWaitTimeInSeconds 0 -Verbose
    $importId = $solutionImportResult.AsyncJobId.Guid

    Write-Verbose "Import Id: $importId"

    $isProcessing = $true
    $importTimedOut = $false
    $importTimeElapsed = [System.Diagnostics.Stopwatch]::StartNew()
    while ($isProcessing -eq $true -and $importTimedOut -ne $true) {
        Start-Sleep -Seconds 10
        $importProgress = Get-CrmRecord -conn $conn -EntityLogicalName asyncoperation -Id $importId -Fields statuscode,completedon,friendlymessage
        $statuscode = $importProgress.statuscode_Property.Value.Value
        if($statuscode -lt 30){
            
            Write-Verbose "Status: $($importProgress.statuscode) ($statuscode) Elapsed: $($importTimeElapsed.Elapsed.ToString())"
            if ($importTimeElapsed.Elapsed.TotalMinutes -ge 30) 
            {
                $importTimedOut = $true
                Write-Error "Internal operation timed out after 30 minutes passed"
            }
        }
        elseif($statuscode -eq 31 -or $statuscode -eq 32 ){
            $isProcessing = $false
            Write-Error "Status: $($importProgress.statuscode) ($statuscode) | Operation has been either cancelled or has failed for Async Operation {$importId}.`n$($importProgress.friendlymessage)"
            break; 
        }
        elseif($statuscode -eq 30){
            $isProcessing = $false
            Write-Verbose "Processing Completed at: $($importProgress.completedon)"
            if ($importAsHolding -eq $true) {
                Write-Verbose "Upgrading Solution"
                $UpgradeSolutionRequest = New-Object Microsoft.Crm.Sdk.Messages.DeleteAndPromoteRequest
                $UpgradeSolutionRequest.UniqueName = $solutionName
                $upgradeResponse= $conn.ExecuteCrmOrganizationRequest($UpgradeSolutionRequest)
                Write-Verbose "Upgraded Solution Id: $($upgradeResponse.SolutionId)"
            }
            break; 
        }
    }
}

$ErrorActionPreference = "Stop"
main $SolutionType $SolutionName $SolutionPath $AppId $AppSecret $TargetUri $ToolingPath