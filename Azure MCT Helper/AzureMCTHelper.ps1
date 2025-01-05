<#
.Synopsis
    PowerShell script with WPF GUI for easy usage of Azure tasks during training.
    Author   Rolf McLaughlin
    Company  TheCloud42 (https://TheCloud42.com)
    Source   https://github.com/RolfCloud42/AzureMCTHelper/
.Description
    Deployment at your fingertips no matter if it is a azuredeploy.json, a powershell or a bash script. 
    All in one place without learning Azure DevOps and pipelines or other sophisticated deployment methods. 
    Snippets of code ready for showing stuff during training.
.EXAMPLE
    Download all files from the above mentioned Github repository.
    Place the script and its subfolders in any folder on your system. Make sure that the execution 
    of PowerShell scripts is allowed for the account you are using. There are no administrative rights 
    needed to run the script, although the installation of the PowerShell module Az is required. 
    The script will not work as intended without it. Optionally the installation of the Azure CLI module 
    is required in case the unit contains shell files.
#>

Clear-Host
Add-Type -AssemblyName PresentationCore,PresentationFramework # needed when starting the script from the command line and not from the ISE
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Debugging: Print the coordinate values
Write-Host "X: $($SliderPoint2Screen.X), Y: $($SliderPoint2Screen.Y)"

# Set cursor position
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($SliderPoint2Screen.X, $SliderPoint2Screen.Y)
#Requires -Version 5

#region Generic_values

    [bool]$script:UseSettingsJSON = $true
    $script:PreGUIMessages = @()

    $script:AzResourceTag = @{CreatedBy="MCTHelper"} 
    $script:sliderValueBefore = $null
    
    $script:AzModuleStatus = "not verified"
    
    $script:tenants = $null
    $script:SelectedTenantName = $null
    $script:SelectedTenantID = $null
    
    $script:subscriptions = $null
    $script:SelectedSubscriptionName = $null
    $script:SelectedSubscriptionID = $null
    
    $script:regions = $null
    $script:SelectedRegionName = $null
    $script:SelectedRegionDisplayName = $null
    
    $script:ResourceGroups = $null
    $script:SelectedRecourcegroupName = $null
    $script:SelectedRecourcegroupRegion = $null
    
    $script:SelectedUnit = $null
    $script:SelectedUnitFolder = $null
    
    $script:azuredeployjson = $null
    $script:azuredeployparameter = $null
    [bool]$script:GitHubDeploymentJson = $false
    [bool]$script:GitHubDeploymentParameter = $false

    [bool]$script:AzModuleInstalled = $false
    [bool]$script:logedin = $false
    [bool]$script:CliLogin = $false
    $script:CliLoginType = "CR"
    [bool]$script:UnitParameterChanged = $false
    
    $script:cred = $null

#endregion Generic_values

#region Settings
    # all of these values can be configured within $Script:ScriptFolder\Resources\settings.json
    if ($false -eq $script:UseSettingsJSON)
    {
        $script:formCaption = 'Azure MCT Helper v1.1'
        $script:workdir = "$Script:ScriptFolder\Units"
        $script:SkipAzModuleStatus = $false
        $script:DefaultTenant = ""
        $script:DefaultSubscription = ""
        $script:DefaultRegion = "northeurope"
        $script:DefaultRegionLong = "North Europe"
        $script:DefaultResourceGroup = "AzClass"
        $script:DefaultAccount = ""
        $script:DefaultEditor = "code"

        Write-Output "Settings loaded from script and tenants.csv..."
        $script:PreGUIMessages += "Settings loaded from script and tenants.csv..."
    }
#endregion Settings

#region Functions

function Add-LogEntry {
    Param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [array]$LogEntry,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Error", "Warning", "Info")]
        $Severity
    )

    If ([Array]$script:OldLogEntry -ne [Array]$LogEntry)
    {
        Foreach ($line in $LogEntry)
        {
            switch ($Severity)
            {
                'Error' {$line = "[Error] $line"}
                'Warning' {$line = "[Warning] $line"}
                'Info' {$line = "[Info] $line"}
            }
                $pLogging = New-Object -TypeName System.Windows.Documents.Paragraph
                $pLogging.Inlines.Add($line)
                $fdLogging.Blocks.Add($pLogging)
        }
        [Array]$script:OldLogEntry = [Array]$LogEntry
    }
} # end function Add-LogEntry

function Add-Output {
    If ($script:AzureOutput) {
    $script:MaxNameLength = 0

    $script:AzureOutput.PSObject.Properties | ForEach-Object {
            If ((($_.Name).ToString()).Length -gt $script:MaxNameLength)
            {
                $script:MaxNameLength = (($_.Name).ToString()).Length
            }
        }
    $OutputSeparator = "`r`n--------------------------------------------------------`r`n"
            $pOutput = New-Object -TypeName System.Windows.Documents.Paragraph
            $pOutput.Inlines.Add($OutputSeparator)
            $fdOutput.Blocks.Add($pOutput)

    $script:AzureOutput.PSObject.Properties | ForEach-Object {
            $pOutput = New-Object -TypeName System.Windows.Documents.Paragraph
            $PadName = (($_.Name).ToString()).PadRight($script:MaxNameLength," ")
            $pOutput.Inlines.Add("$PadName : $($_.Value)")
            $fdOutput.Blocks.Add($pOutput)
        }
    }
} # end function Add-Output

function Get-ScriptDirectory {
    if ($psise)
    {
        $dir = Split-Path $psise.CurrentFile.FullPath
    }
    else
    {
        $dir = $PSScriptRoot
    }
    return $dir
} # end function Get-ScriptDirectory

function RefreshUI {
    $AMH.Dispatcher.Invoke("Render", [Windows.Input.InputEventHandler]{$AMH.UpdateLayout()},$Null,$Null)
} # end function RefreshUI

function Add-Module ($module) {
    if (($script:AzModuleStatus -eq "not verified") -or ($btnAzureModule.Content -eq "verifying..."))
    {
        $Modulestate = $false
        if (Get-Module -Name $module) { # If module is imported do nothing
            $Modulestate = $true 
            $logstring = "Module $module loaded"
            Add-LogEntry -LogEntry $logstring -Severity Info
        }
        else {
            $btnAzureModule.IsEnabled = $false
            RefreshUI
            if ((Get-Module -ListAvailable).Name -eq $module) { # If module is not imported, but available on disk then import
                $lblAzureModuleStatus.Content = "importing module..."
                RefreshUI
                Import-Module -Name $module
                $Modulestate = $true
                $logstring = "Module $module imported"
                Add-LogEntry -LogEntry $logstring -Severity Info
            }
            else { # If module is not imported, not available on disk, but is in online gallery then install and import
                if (Find-Module -Name $module) {
                    $logstring = "Module $module is not imported, not available on disk, but is in the online gallery. Installation and import will take a while"
                    Add-LogEntry -LogEntry $logstring -Severity Warning

                    $lblAzureModuleStatus.Content = "installing module..."
                    RefreshUI
                    Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber -Confirm:$False
                    $lblAzureModuleStatus.Content = "importing module..."
                    RefreshUI
                    Import-Module -name $module
                    $Modulestate = $true
                    $logstring = "Module $module installed and imported"
                    Add-LogEntry -LogEntry $logstring -Severity Info
                }
                else {# If module is not imported, not available and not in online gallery then abort
                    $logstring = "Module $module not imported, not available and not in online gallery, exiting advised."
                    Add-LogEntry -LogEntry $logstring -Severity Error
                }
            }
        }
        $btnAzureModule.IsEnabled = $true
        RefreshUI
    }
    If ($true -eq $Modulestate)
    {
        $script:AzModuleInstalled = $true
    }
    else
    {
        $script:AzModuleInstalled = $false
    }
} # end function Add-Module

function Find-AzureCLI {
    New-PSDrive -PSProvider registry -Root HKEY_CLASSES_ROOT -Name HKCR | Out-Null
    $script:AzCliIsInstalled = $null
    #$script:AzCliIsInstalled = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$_.DisplayName -Match "Microsoft Azure CLI"}
    $script:AzCliIsInstalled = Get-ItemProperty HKCR:\Installer\Products\* | Where-Object {$_.ProductName -Match "Microsoft Azure CLI"}

    If ($script:AzCliIsInstalled) 
    {
        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
        $imgAzCLIBulb.Tooltip = "Select the icon to login with Azure CLI."
    }
    else
    {
        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbred.png"
        $imgAzCLIBulb.Tooltip = "Azure CLI not installed!"

    }
    Remove-PSDrive -Name HKCR | Out-Null
} # end function Find-AzureCLI 

function GetAMHSettings {
    if ($true -eq $script:UseSettingsJSON)
    {
        try
        {
            if (Test-Path -Path "$Script:ScriptFolder\Resources\settings.json") {
                $script:settings = Get-Content -Path $Script:ScriptFolder\Resources\settings.json | ConvertFrom-Json
                Write-Output "Settings loaded from JSON..."
                $script:PreGUIMessages += "Settings loaded from JSON..."
            }
            else {
                Write-Output "The settings file cannot be found. Reverting back to tenants.csv... " -BackgroundColor Red -ForegroundColor White
                $script:UseSettingsJSON = $false
                GetAMHSettings
            } 
        }
        catch
        {
            Write-Output " Error locating and loading the settings. Closing... " -BackgroundColor Red -ForegroundColor White
            Exit 1
        }

        $script:formCaption = $script:Settings.defaults.formCaption
        $script:workdir = Join-Path -path $Script:scriptfolder -ChildPath $script:Settings.defaults.workdir
        $script:SkipAzModuleStatus = $script:Settings.defaults.SkipAzModuleStatus
        $script:DefaultTenant = $script:Settings.defaults.DefaultTenant
        $script:DefaultSubscription = $script:Settings.defaults.DefaultSubscription
        $script:DefaultRegion = $script:Settings.defaults.DefaultRegion
        $script:DefaultRegionLong = $script:Settings.defaults.DefaultRegionLong
        $script:DefaultResourceGroup = $script:Settings.defaults.DefaultResourceGroup
        $script:DefaultAccount = $script:Settings.accounts[$script:Settings.defaults.DefaultAccount]
        $script:DefaultEditor = $script:Settings.editors[$script:Settings.defaults.DefaultEditor]
    }
} # end function GetAMHSettings

function CreateUnitScriptBlock ($UnitName,$UnitFolder) {
$UBlock =
@"
    ActivateActionPane -UnitName $UnitName -UnitFolder "$UnitFolder"
"@

    $scriptBlock = [scriptblock]::Create($UBlock)
    return $scriptBlock
} # end CreateUnitScriptBlock

function FillTenantCB {
    $logstring = "filling tenant list"
    Add-LogEntry -LogEntry $logstring -Severity Info

    $script:tenants = $null
    $cbTenant.Items.Clear()
    
    if ($true -eq $script:UseSettingsJSON)
    {
        $script:tenants = $script:settings.tenants
    }
    else
    {
        $script:tenants = Import-CSV -LiteralPath $Script:ScriptFolder\Resources\tenants.csv -Header Name,Tag
    }

    Foreach ($tenant in $script:tenants)
    {
        $TenantNewListBoxItem = New-Object -TypeName System.Windows.Controls.ListBoxItem
        If (($tenant -ne "") -and ($null -ne $tenant))
        {
            $TenantNewListBoxItem.Content = $tenant.Name
            $TenantNewListBoxItem.Tag = $tenant.ID
            $cbTenant.Items.Add($TenantNewListBoxItem) | Out-Null
        }

        If ($TenantNewListBoxItem.Content -eq $script:DefaultTenant)
        {
            $cbTenant.SelectedItem = $TenantNewListBoxItem
        }
    }
    $script:SelectedTenantName = $cbTenant.SelectedItem.Content
    $script:SelectedTenantID = $cbTenant.SelectedItem.Tag
} # end function FillTenantCB

function FillSubscriptionCB {
    $logstring = "filling subscription list"
    Add-LogEntry -LogEntry $logstring -Severity Info
    $script:subscriptions = $null
    $script:SelectedSubscriptionName = $null
    $script:SelectedSubscriptionID = $null
    $cbSubscription.Items.Clear()
    $cbSubscription.Text = ""
    $script:subscriptions = Get-AzSubscription -TenantId $script:SelectedTenantID

    $btnRGCreate.IsEnabled = $false
    RefreshUI

    If ($null -ne $script:subscriptions)
    {
        $cbSubscription.IsEnabled = $true
        Foreach ($subscription in $script:subscriptions)
        {
            $SubscriptionNewListBoxItem = New-Object -TypeName System.Windows.Controls.ListBoxItem
            
            If (($subscription -ne "") -and ($null -ne $subscription))
            {
                $SubscriptionNewListBoxItem.Content = $subscription.Name
                $SubscriptionNewListBoxItem.Tag = $subscription.Id
                $cbSubscription.Items.Add($SubscriptionNewListBoxItem) | Out-Null
            }
            If ($SubscriptionNewListBoxItem.Content -eq $script:DefaultSubscription)
            {
                $cbSubscription.SelectedItem = $SubscriptionNewListBoxItem
            }
        }
        $script:SelectedSubscriptionName = $cbSubscription.SelectedItem.Content
        $script:SelectedSubscriptionID = $cbSubscription.SelectedItem.Tag
        FillResourceGroupCB
    }
    else
    {
        $cbSubscription.IsEnabled = $false
        $script:SelectedSubscriptionName = $null
        $script:SelectedSubscriptionID = $null
        $logstring = "No subscriptions found in selected tenant"
        Add-LogEntry -LogEntry $logstring -Severity Info
        $cbResourceGroup.IsEnabled = $false
        $script:SelectedRecourcegroupName = $null
        $cbResourceGroup.Text = "(New) Resource group"
    }
    RefreshUI
} # end function FillSubscriptionCB

function FillRegionCB {
    $logstring = "filling regions list"
    Add-LogEntry -LogEntry $logstring -Severity Info
    $script:regions = $null
    $script:SelectedRegionName = $null
    $script:SelectedRegionDisplayName = $null
    $cbRegion.Items.Clear()
    $script:regions = Get-AzLocation | Sort-Object -Property DisplayName #Select-Object Location,DisplayName | 
    $cbRegion.IsEnabled = $true
    $btnRGCreate.IsEnabled = $false
    RefreshUI

    Foreach ($region in $script:regions)
    {
        $RegionNewListBoxItem = New-Object -TypeName System.Windows.Controls.ListBoxItem
        
        If (($region -ne "") -and ($null -ne $region))
        {
            $RegionNewListBoxItem.Name = $region.Location
            $RegionNewListBoxItem.Content = $region.DisplayName
            $RegionNewListBoxItem.Tag = $region.Location
            $cbRegion.Items.Add($RegionNewListBoxItem) | Out-Null
        }
        If ($RegionNewListBoxItem.Name -eq $script:DefaultRegion)
        {
            $cbRegion.SelectedItem = $RegionNewListBoxItem
        }
    }
} # end function FillRegionCB

function FillResourceGroupCB {
    $logstring = "filling resource group list"
    Add-LogEntry -LogEntry $logstring -Severity Info
    $script:ResourceGroups = $null
    $script:SelectedRecourcegroupName = $null
    $script:SelectedRecourcegroupRegion = $null
    $cbResourceGroup.Items.Clear()
    $cbResourceGroup.Text = ""
    $script:ResourceGroups = Get-AzResourceGroup | Sort-Object -Property ResourceGroupName         
    RefreshUI

    If ($null -ne $script:ResourceGroups)
    {
        $cbResourceGroup.IsEnabled = $true
        Foreach ($resourcegroup in $script:ResourceGroups)
        {
            $ResourceGroupsNewListBoxItem = New-Object -TypeName System.Windows.Controls.ListBoxItem
            
            If (($resourcegroup -ne "") -and ($null -ne $resourcegroup))
            {
                $ResourceGroupsNewListBoxItem.Content = $resourcegroup.ResourceGroupName
                $ResourceGroupsNewListBoxItem.Tag = $resourcegroup.Location
                $cbResourceGroup.Items.Add($ResourceGroupsNewListBoxItem) | Out-Null
            }
        }
        $cbResourceGroup.SelectedIndex = 0
        $script:SelectedRecourcegroupName = $cbResourceGroup.SelectedItem.Content
    }
    else
    {
        $logstring = "No resource group(s) found in selected subscription"
        Add-LogEntry -LogEntry $logstring -Severity Info
        $script:SelectedRecourcegroupName = $null
        $cbResourceGroup.Text = "(New) Resource group"
        RefreshUI
    }
} # end function FillResourceGroupCB 

function FillUnitLB {
    If ($lbUnits.Items)
    {
        $logstring = "refreshing unit buttons in list"
        Add-LogEntry -LogEntry $logstring -Severity Info
        $lbUnits.Items.Clear()
        RefreshUI
        Start-Sleep -Seconds 1 # just to give a visual representation that something is happening when the refresh button is clicked
    }
    else
    {
        $logstring = "adding unit buttons to list"
        Add-LogEntry -LogEntry $logstring -Severity Info    
    }

    $UnitList = Get-ChildItem -Path $script:workdir
    $script:UnitBtnSource = [System.Collections.Generic.List[System.Windows.Controls.Button]]::new()

    for ($UnitCount = 0;$UnitCount -le $UnitList.Count - 1;$UnitCount++) {
        $UnitNewListBoxItem = New-Object -TypeName System.Windows.Controls.Button
        $UnitNewListBoxItem.Name = "btnUnit$($UnitCount + 1)"
        $ButtonName = $UnitNewListBoxItem.Name
        $UnitNewListBoxItem.Content = $UnitList[$UnitCount].Name
        $UnitNewListBoxItem.Tag = $UnitList[$UnitCount].FullName
        $btnUnitScriptblock = CreateUnitScriptBlock -UnitName $ButtonName -UnitFolder "$($UnitNewListBoxItem.Tag)"
        $UnitNewListBoxItem.Add_Click($btnUnitScriptblock)

        $script:UnitBtnSource.Add($UnitNewListBoxItem)
        $script:AllControls.Add($UnitNewListBoxItem)
    }
    $lbUnits.ItemsSource = $script:UnitBtnSource
    $script:UnitBtnFilteredSource = [System.Collections.Generic.List[System.Windows.Controls.Button]]::new()
} # end function FillUnitLB

function FillUnitInfo {
    if (Test-Path -Path $script:UnitFileInfo) {
        $tbUnitInfo.Text = Get-Content -Path $script:UnitFileInfo
    }
    else {
        $tbUnitInfo.Text = "No file with the name info.txt found in unit folder"
    }
} # end function FillInitInfo

function FillUnitTemplate {
    $fdTemplate.Blocks.Clear()
    $script:azuredeployjson = $null
    $script:GitHubDeploymentJson = $false
    if ($null -ne $script:UnitFileDeploy)
    {
        if (Test-Path -Path $script:UnitFileDeploy)
        {
            $script:azuredeployjson = Get-Content -Path $script:UnitFileDeploy
            If ($script:UnitFileDeploy -match 'github.txt')
            {
                $RemoteJsonURL = (($script:azuredeployjson) -replace 'github.com','raw.githubusercontent.com') -replace 'blob/',''
                $script:azuredeployjson = (New-Object System.Net.WebClient).DownloadString($RemoteJsonURL)
                $script:GitHubDeploymentJson = $true
            }
        }
        else
        {
            $script:azuredeployjson = "No file to deploy with found in unit folder"
        }
        Foreach ($line in $script:azuredeployjson)
        {
            $pTemplate = New-Object -TypeName System.Windows.Documents.Paragraph
            $pTemplate.Inlines.Add($line)
            $fdTemplate.Blocks.Add($pTemplate)
        }
    }
} # end function FillUnitTemplate

function FillUnitTemplateParameter {
    $fdParameter.Blocks.Clear()
    $script:azuredeployparameter = $null
    $script:GitHubDeploymentParameter = $false
    if ($null -ne $script:UnitFileParameter)
    {
        if (Test-Path -Path $script:UnitFileParameter)
        {
            $script:azuredeployparameter = Get-Content -Path $script:UnitFileParameter
            If ($script:UnitFileParameter -match 'github.txt')
            {
                $RemoteParameterJsonURL = (($script:azuredeployparameter) -replace 'github.com','raw.githubusercontent.com') -replace 'blob/',''
                $script:azuredeployparameter = (New-Object System.Net.WebClient).DownloadString($RemoteParameterJsonURL)
                $script:GitHubDeploymentParameter = $true
            }
        }
        else
        {
            $script:azuredeployparameter = "No file with parameters found in unit folder"
        }
        Foreach ($line in $script:azuredeployparameter)
        {
            $pParameter = New-Object -TypeName System.Windows.Documents.Paragraph
            $pParameter.Inlines.Add($line)
            $fdParameter.Blocks.Add($pParameter)
        }
    }
} # end function FillUnitTemplateParameter

function ReplaceScriptVariables ($script2replace) {
    $script:script2return = $script2replace
    If ($null -ne $script:regions)
    {
        Foreach ($AzLocation in $script:Regions) {
            If ($script2replace -match $AzLocation.DisplayName)
            {
                $script:script2return = $script2replace.replace($AzLocation.DisplayName, $script:DefaultRegionLong)
                break
            }
        }

        Foreach ($AzLocation in $script:Regions) {
            If ($script2replace -match $AzLocation.Location)
            {
                $script:script2return = $script2replace.replace($AzLocation.Location, $script:DefaultRegion)
                break
            }
        }    
    }
    else
    {
        $logstring = "Region list is not yet ready. Log in first."
        Add-LogEntry -LogEntry $logstring -Severity Warning
    }
    return $script:script2return
} # end function ReplaceScriptVariables

function FillUnitPowerShell {
    $fdPowerShell.Blocks.Clear()
    if ($null -ne $script:UnitFilePSScript)
    {
        if (Test-Path -Path $script:UnitFilePSScript)
        {
            $azurescript = Get-Content -Path $script:UnitFilePSScript
            ToggleReplaceVarCbx -tabname PS
        }
        else
        {
            $azurescript = "No file with the name azurescript.ps1 found in unit folder"
        }

        if ($cbxVariableReplacement.IsChecked)
        {
            $azurescript = ReplaceScriptVariables -script2replace $azurescript
        }
        Foreach ($line in $azurescript)
        {
            $pScript = New-Object -TypeName System.Windows.Documents.Paragraph
            $pScript.Inlines.Add($line)
            $fdPowerShell.Blocks.Add($pScript)
        }
    }
} # end function FillUnitPowerShell

function FillUnitAzureCLI {
    $fdAzureCLI.Blocks.Clear()
    if ($null -ne $script:UnitFileAZScript)
    {
        if (Test-Path -Path $script:UnitFileAZScript)
        {
            $azurescript = Get-Content -Path $script:UnitFileAZScript
            ToggleReplaceVarCbx -tabname CLI
        }
        else
        {
            $azurescript = "No file with the name azurescript.sh found in unit folder"
        }

        if ($cbxVariableReplacement.IsChecked)
        {
            $azurescript = ReplaceScriptVariables -script2replace $azurescript
        }
        Foreach ($line in $azurescript)
        {
            $aScript = New-Object -TypeName System.Windows.Documents.Paragraph
            $aScript.Inlines.Add($line)
            $fdAzureCLI.Blocks.Add($aScript)
        }
    }
} # end function FillUnitAzureCLI 

function ActivateActionPane ($UnitName,$UnitFolder) {
    $script:SelectedUnit = $UnitName
    $script:SelectedUnitFolder = $UnitFolder
    $script:UnitFileInfo = "$script:SelectedUnitFolder\info.txt"

    If (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.json")
    {
        $script:UnitFileDeploy = "$script:SelectedUnitFolder\azuredeploy.json"
    }
    elseif (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.json.github.txt")
    {
        $script:UnitFileDeploy = "$script:SelectedUnitFolder\azuredeploy.json.github.txt"
    }
    else
    {
        $script:UnitFileDeploy = $null
    }

    if (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.parameters.json")
    {
        $script:UnitFileParameter = "$script:SelectedUnitFolder\azuredeploy.parameters.json"
    }
    elseif (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.parameters.json.github.txt")
    {
        $script:UnitFileParameter = "$script:SelectedUnitFolder\azuredeploy.parameters.json.github.txt"
    }
    else
    {
        $script:UnitFileParameter = $null
    }
    
    if (Test-path -Path "$script:SelectedUnitFolder\azurescript.ps1")
    {
        $script:UnitFilePSScript = "$script:SelectedUnitFolder\azurescript.ps1"
    }
    else
    {
        $script:UnitFilePSScript = $null
    }
    
    if (Test-path -Path "$script:SelectedUnitFolder\azurescript.sh")
    {
        $script:UnitFileAZScript = "$script:SelectedUnitFolder\azurescript.sh"
    }
    else
    {
        $script:UnitFileAZScript = $null
    }
    
    FillUnitInfo
    FillUnitTemplate
    FillUnitTemplateParameter
    FillUnitPowerShell
    FillUnitAzureCLI
    ToggleDeployButtons
} # end function ActivateActionPane

function DeployScript ($UnitScript) {
        $logstring = "Deploying with script: $UnitScript"
        Add-LogEntry -LogEntry $logstring -Severity Info

        $Script = Get-Content $UnitScript
        if ($true -eq $cbxVariableReplacement.IsChecked)
        {
            $Script = ReplaceScriptVariables -line2replace $Script
        }
        $UnitScriptBlock = [scriptblock]::Create($Script)
        $script:AzureOutput = Invoke-Command -ScriptBlock $UnitScriptBlock -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Add-Output
    }

function ToggleReplaceVarCbx ($tabname) {
    switch ($tabname)
    {
    'PS' {
            if (($null -ne $script:SelectedUnit) -and (Test-Path -Path $script:UnitFilePSScript))
            {
                $cbxVariableReplacement.IsEnabled = $true
                $cbxVariableReplacement.Visibility = "Visible"
                $lblVariableReplacement.Visibility = "Visible"
            }
            else
            {
                $cbxVariableReplacement.Visibility = "Hidden"
                $lblVariableReplacement.Visibility = "Hidden"
                $cbxVariableReplacement.IsEnabled = $false
            }
        }
    'CLI' {
            if (($null -ne $script:SelectedUnit) -and (Test-Path -Path $script:UnitFileAZScript))
            {
                $cbxVariableReplacement.IsEnabled = $true
                $cbxVariableReplacement.Visibility = "Visible"
                $lblVariableReplacement.Visibility = "Visible"
            }
            else
            {
                $cbxVariableReplacement.Visibility = "Hidden"
                $lblVariableReplacement.Visibility = "Hidden"
                $cbxVariableReplacement.IsEnabled = $false
            }
        }
    }
} # end function ToggleReplaceVarCbx

function ToggleDeployButtons ($Toggle) {
    If ($Toggle -eq "off")
    {
        $imgDeployActive.Visibility = "Hidden"
        $imgDeployInactive.Visibility = "Hidden"
        $imgScriptActive.Visibility = "Hidden"
        $imgScriptInactive.Visibility = "Hidden"
    }

    if ($null -ne $script:UnitFileDeploy)
    {
        if (($null -ne $script:SelectedUnit) -and (Test-Path -Path $script:UnitFileDeploy))
        {
            if ($true -eq $script:logedin)
            {
                $imgDeployActive.Visibility = "Visible"
                $imgDeployInactive.Visibility = "Hidden"
            }
            else
            {
                $imgDeployActive.Visibility = "Hidden"
                $imgDeployInactive.Visibility = "Visible"
            }
        }
        else
        {
            $imgDeployActive.Visibility = "Hidden"
            $imgDeployInactive.Visibility = "Hidden"
        }
    }

    if (($null -ne $script:UnitFilePSScript) -or ($null -ne $script:UnitFileAZScript))
    {
        if ($null -ne $script:SelectedUnit) 
        {
            if ($true -eq $script:logedin)
            {
                $imgScriptActive.Visibility = "Visible"
                $imgScriptInactive.Visibility = "Hidden"
            }
            else
            {
                $imgScriptActive.Visibility = "Hidden"
                $imgScriptInactive.Visibility = "Visible"
            }
        }
        else
        {
            $imgScriptActive.Visibility = "Hidden"
            $imgScriptInactive.Visibility = "Hidden"
        }
    }
    RefreshUI
} # end function ToggleDeployButtons

function ToggleAzCliExpander ($expander) {
    switch ($expander.Name)
    {
    'exAzCliCred'  {
                    $exAzCliSP.IsExpanded = $false
                    $exAzCliMI.IsExpanded = $false
                    $rbAzCliCR.IsChecked = $true
                    $rbAzCliSP.IsChecked = $false
                    $rbAzCliMI.IsChecked = $false
                    $script:CliLoginType = "CR"
                    break
                   }
    'exAzCliSP'    {
                    $exAzCliCred.IsExpanded = $false
                    $exAzCliMI.IsExpanded = $false
                    $rbAzCliCR.IsChecked = $false
                    $rbAzCliSP.IsChecked = $true
                    $rbAzCliMI.IsChecked = $false
                    $script:CliLoginType = "SP"
                    break
                   }
    'exAzCliMI'    {
                    $exAzCliCred.IsExpanded = $false
                    $exAzCliSP.IsExpanded = $false
                    $rbAzCliCR.IsChecked = $false
                    $rbAzCliSP.IsChecked = $false
                    $rbAzCliMI.IsChecked = $true
                    $script:CliLoginType = "MI"
                    break
                   }
    }
} # end function ToggleAzCliExpander 

function FormResize ($SelectedSize) {
    $position = $sliderSize.TransformToAncestor($spSlider).Transform([System.Windows.Point]::new(0, 0))
    If ($script:sliderValueBefore -lt $SelectedSize) {
        for ($step = $script:sliderValueBefore + 1 ; $step -le $SelectedSize; $step++) {
            $script:multiplier = $step/100
       
            $AMHWindow.Width = $script:StartupWidth * $script:multiplier
            $AMHWindow.Height = $script:StartupHeight * $script:multiplier
            
            Foreach ($control in $script:AllControls)
            {
                if ($control.FontSize) {
                    if ($control.Name -ne "lblFilterUnitsClear") {$control.FontSize = $script:StartupFontSize * $script:multiplier}
                }
            }
        RefreshUI
        $SliderPoint2Screen = $sliderSize.PointToScreen($position)
        $SliderPoint2Screen.x = $($SliderPoint2Screen.x + $sliderSize.ActualWidth - 10)
        $SliderPoint2Screen.y = $SliderPoint2Screen.y + 12
    }
    } elseif ($script:sliderValueBefore -gt $SelectedSize) {
        for ($step = $script:sliderValueBefore - 1 ; $step -ge $SelectedSize; $step--) {
            $script:multiplier = $step/100
        
            $AMHWindow.Width = $script:StartupWidth * $script:multiplier
            $AMHWindow.Height = $script:StartupHeight * $script:multiplier
            
            Foreach ($control in $script:AllControls)
            {
                if ($control.FontSize) {
                    if ($control.Name -ne "lblFilterUnitsClear") {$control.FontSize = $script:StartupFontSize * $script:multiplier}
                }
            }
        RefreshUI
        $SliderPoint2Screen = $sliderSize.PointToScreen($position)
        $SliderPoint2Screen.x = $SliderPoint2Screen.x + 10
        $SliderPoint2Screen.y = $SliderPoint2Screen.y + 12
        }
    }
    # get the new position of the slider control
    #position the cursor to the new point
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($SliderPoint2Screen.X, $SliderPoint2Screen.Y)
    $script:sliderValueBefore = $sliderSize.Value
} # end function FormResize

function FormAzCliResize {
    $script:AzCliLogin.Width = $script:StartupWidth * $script:multiplier
    $script:AzCliLogin.Height = $script:StartupHeight * $script:multiplier
    
    Foreach ($AzClicontrol in $script:AllAzCliControls)
    {
        if ($AzClicontrol.FontSize) {
            $AzClicontrol.FontSize = $script:StartupFontSize * $script:multiplier
        }
    }
    RefreshUI
} # end function FormResize

function LogoutAzCli {
    if ($true -eq $script:CliLogin) 
    {
        Az Logout
        $script:CliLogin = $false
        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
        $imgAzCLIBulbCR.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
        $imgAzCLIBulbSP.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
        $imgAzCLIBulbMI.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
    }

} # end function LogoutAzCli

function LogoutCleanup {
        $logstring = "So long and thank you for the fish."
        Add-LogEntry -LogEntry $logstring -Severity Info
        Add-LogEntry -LogEntry "--------------------------------------------------------" -Severity Info
        $script:cred = $null
        $script:logedin = $false
        #$tbsbiCenter2.Text = ""
        $script:subscriptions = $null
        $cbSubscription.Items.Clear()
        $cbSubscription.IsEnabled = $false
        $script:SelectedSubscriptionName = $null
        $script:SelectedSubscriptionID = $null
        $script:regions = $null
        $cbRegion.Items.Clear()
        $cbRegion.IsEnabled = $false
        $script:SelectedRegionName = $null
        $script:SelectedRegionDisplayName = $null
        $cbResourceGroup.Items.Clear()
        $cbResourceGroup.IsEnabled = $false
        $cbResourceGroup.Text = "(New) Resource group"
        $btnRGCreate.IsEnabled = $false
        $script:ResourceGroups = $null
        $script:SelectedRecourcegroupName = $null
        $script:SelectedRecourcegroupRegion = $null
        $cbxVariableReplacement.IsEnabled = $false
        $cbxVariableReplacement.Visibility = "Hidden"
        $lblVariableReplacement.Visibility = "Hidden"
        if ($true -eq $script:CliLogin) 
        {
            Az Logout
        }
        Disconnect-AzAccount

        $btnLogin.Content = "login"
        ToggleDeployButtons -Toggle "off"
        Set-Location -Path $Script:ScriptFolder
    } # end function LogoutCleanup

function InitializeAzCliForm {
    try
    {
        # Test-Path will return true or false and that does not trigger an error if the file is not there
        if (Test-Path -Path "$Script:ScriptFolder\Resources\AzCliLogin.xaml")
        {
            [XML]$script:AzCliXAML = (Get-Content $Script:ScriptFolder\Resources\AzCliLogin.xaml) -replace 'Page','Window'
        }
        else
        {
            Write-Output " The form cannot be found. Closing... " -BackgroundColor Red -ForegroundColor White
            Exit 1
        } 
    }
    catch
    {
        Write-Output " Error locating and loading the form. Closing... " -BackgroundColor Red -ForegroundColor White
        Exit 1
    }

    $script:AzCliXAML.Window.RemoveAttribute("x:Class") #removing attributes which are coming from the editor 
    $script:AzCliXAML.Window.RemoveAttribute("xmlns:mc")
    $script:AzCliXAML.Window.RemoveAttribute("mc:Ignorable")

    $AzCliReader = New-Object System.Xml.XmlNodeReader $script:AzCliXAML
    $script:AzCliLogin = [Windows.Markup.XamlReader]::Load($AzCliReader)
} # end function InitializeAzCliForm 

function GenerateAzCliForm {
    $script:AllAzCliControls = [System.Collections.Generic.List[PSObject]]::new()
    $script:AzCliXAML.SelectNodes("//*[@Name]") | ForEach-Object {
            New-Variable -Name ($_.Name) -Value $script:AzCliLogin.FindName($_.Name) -PassThru | ForEach-Object {
                $script:AllAzCliControls.Add($_.Value)
            }
        }
    
    $script:StartupAzCliWidth = $script:AzCliLogin.Width
    $script:StartupAzCliHeight = $script:AzCliLogin.Height

    $btnAzCliCancel.Add_Click($btnAzCliCancel_Click)
    $btnAzCliLogin.Add_Click($btnAzCliLogin_Click)

    $exAzCliCred.Add_Expanded($exAzCliCred_Expanded)
    $exAzCliSP.Add_Expanded($exAzCliSP_Expanded)
    $exAzCliMI.Add_Expanded($exAzCliMI_Expanded)

    $imgAzCLIBulbCR.Add_MouseLeftButtonDown($imgAzCLIBulbCR_MouseLeftButtonDown)
    $imgAzCLIBulbSP.Add_MouseLeftButtonDown($imgAzCLIBulbSP_MouseLeftButtonDown)
    $imgAzCLIBulbMI.Add_MouseLeftButtonDown($imgAzCLIBulbMI_MouseLeftButtonDown)

    $txtUsernameCred.Text = $tbLoginUser.Text
    $txtSPTenantName.Text = $script:SelectedTenantID
    $imgAzCLIBulbCR.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
    $imgAzCLIBulbSP.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
    $imgAzCLIBulbMI.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"

    if ($true -eq $script:CliLogin)
    {
        switch ($script:CliLoginType) {
        'CR' {$imgAzCLIBulbCR.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"}
        'SP' {$imgAzCLIBulbSP.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"}
        'MI' {$imgAzCLIBulbMI.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"}
        }
    }
    
    FormAzCliResize

    $script:AzCliLogin.ShowDialog() | Out-Null

} # end function GenerateAzCliForm

function InitializeForm {
    $Script:ScriptFolder = Get-ScriptDirectory
    $script:workdir = "$Script:ScriptFolder\Units" # now with an actual value and not just generic
    Set-Location -Path $script:workdir

    try
    {
        # Test-Path will return true or false and that does not trigger an error if the file is not there
        if (Test-Path -Path "$Script:ScriptFolder\Resources\MainWindow.xaml")
        {
            [XML]$script:XAML = (Get-Content $Script:ScriptFolder\Resources\MainWindow.xaml) -replace 'Page','Window'
        }
        else
        {
            Write-Output " The form cannot be found. Closing... " -BackgroundColor Red -ForegroundColor White
            Exit 1
        } 
    }
    catch
    {
        Write-Output " Error locating and loading the form. Closing... " -BackgroundColor Red -ForegroundColor White
        Exit 1
    }

    $script:XAML.Window.RemoveAttribute("x:Class") #removing attributes which are coming from the editor 
    $script:XAML.Window.RemoveAttribute("xmlns:mc")
    $script:XAML.Window.RemoveAttribute("mc:Ignorable")

    $Reader = New-Object System.Xml.XmlNodeReader $script:XAML
    $script:AMH = [Windows.Markup.XamlReader]::Load($Reader)
} # end function InitializeForm

function GenerateForm {
    
    $script:AllControls = [System.Collections.Generic.List[PSObject]]::new()

    $script:XAML.SelectNodes("//*[@Name]") | ForEach-Object {
        New-Variable -Name ($_.Name) -Value $script:AMH.FindName($_.Name) -PassThru | ForEach-Object {
            $script:AllControls.Add($_.Value)
        }
    }
    
    GetAMHSettings

    $AMHWindow.Add_Closing($AMHWindow_Closing)
    $btnAzureModule.Add_Click($btnAzureModule_Click)

    $btnLogin.Add_Click($btnLogin_Click)

    $exContextOpen.Add_MouseEnter($exContextOpen_MouseEnter)
    $exContextOpen.Add_MouseLeave($exContextOpen_MouseLeave)
    
    $cbTenant.Add_DropDownClosed($cbTenant_DropDownClosed)
    $cbSubscription.Add_DropDownClosed($cbSubscription_DropDownClosed)
    $cbSubscription.Add_SelectionChanged($cbSubscription_DropDownClosed)
    $cbRegion.Add_DropDownClosed($cbRegion_DropDownClosed)
    $cbResourceGroup.Add_DropDownClosed($cbResourceGroup_DropDownClosed)
    $cbResourceGroup.Add_GotFocus($cbResourceGroup_GotFocus)
    $cbResourceGroup.Add_LostFocus($cbResourceGroup_LostFocus)
    $btnRGCreate.Add_Click($btnRGCreate_Click)
    
    $imgDeployActive.Add_MouseLeftButtonDown($deploytemplate)
    $imgScriptActive.Add_MouseLeftButtonDown($DeployUnitScript)
    
    $sliderSize.Add_ValueChanged($sizeValueChanged)
    $cbxVariableReplacement.Add_Unchecked($cbxVariableReplacement_Unchecked)
    $cbxVariableReplacement.Add_Checked($cbxVariableReplacement_Checked)

    $script:DropdownShaddow = $imgRefreshUnits.Effect
    $imgRefreshUnits.Add_MouseLeftButtonDown($refreshUnitsList_MouseLeftButtonDown)
    $imgRefreshUnits.Add_MouseLeftButtonUp($refreshUnitsList_MouseLeftButtonUp)
    $imgRefreshScripts.Add_MouseLeftButtonDown($refreshScripts_MouseLeftButtonDown)
    $imgRefreshScripts.Add_MouseLeftButtonUp($refreshScripts_MouseLeftButtonUp)

    $lblRefreshUnits.Add_MouseEnter($lblRefreshUnits_MouseEnter)
    $lblRefreshUnits.Add_MouseLeave($lblRefreshUnits_MouseLeave)
    $lblRefreshUnits.Add_MouseLeftButtonDown($refreshUnitsList_MouseLeftButtonDown)
    $tbFilterUnits.Add_TextChanged($tbFilterUnits_TextChanged)
    $lblFilterUnitsClear.Add_MouseLeftButtonDown($lblFilterUnitsClear_MouseLeftButtonDown)

    $tabPowerShell.Add_GotFocus($tabPowerShell_GotFocus)
    $tabAzureCLI.Add_GotFocus($tabAzureCLI_GotFocus)
    $imgAzCLIBulb.Add_MouseLeftButtonDown($imgAzCLIBulb_MouseLeftButtonDown)

    $lblRefreshScripts.Add_MouseEnter($lblRefreshScripts_MouseEnter)
    $lblRefreshScripts.Add_MouseLeave($lblRefreshScripts_MouseLeave)
    $lblRefreshScripts.Add_MouseLeftButtonDown($refreshScripts_MouseLeftButtonDown)

    $rtfTemplate.Add_MouseDoubleClick($rtfTemplate_MouseDoubleClick)
    $rtfParameter.Add_MouseDoubleClick($rtfParameter_MouseDoubleClick)
    $rtfPowerShell.Add_MouseDoubleClick($rtfPowerShell_MouseDoubleClick)
    $rtfAzureCLI.Add_MouseDoubleClick($rtfAzureCLI_MouseDoubleClick)
    
    $script:AMH.Title = $script:formCaption
    $script:StartupWidth = $AMHWindow.Width
    $script:StartupHeight = $AMHWindow.Height
    $script:StartupFontSize = $AMHWindow.FontSize
    $script:multiplier = $sliderSize.Value/100
    $script:sliderValueBefore = $sliderSize.Value

    $imgDeployActive.Source = "$Script:ScriptFolder\Resources\DeployActive.png"
    $imgDeployInactive.Source = "$Script:ScriptFolder\Resources\DeployInactive.png"
    $imgScriptActive.Source = "$Script:ScriptFolder\Resources\ScriptActive.png"
    $imgScriptInactive.Source = "$Script:ScriptFolder\Resources\ScriptInactive.png"
    $imgRefreshUnits.Source = "$Script:ScriptFolder\Resources\btnRefresh.png"
    $imgRefreshScripts.Source = "$Script:ScriptFolder\Resources\btnRefresh.png"
    $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbred.png"

    $script:SelectedTenantName = $cbTenant.SelectedItem.Content
    $script:SelectedTenantID = $cbTenant.SelectedItem.Tag
  
    Add-LogEntry -LogEntry "Azure MCT Helper tool started: $(Get-Date)" -Severity Info
    
    if ($false -eq $script:SkipAzModuleStatus) {
        $lblAzureModuleStatus.Content = $script:AzModuleStatus
    }
    elseif ($true -eq $script:SkipAzModuleStatus) {
        $lblAzureModuleStatus.Content = "skipped"
        $script:AzModuleInstalled = $true
        Add-Module -module Az
        $btnAzureModule.IsEnabled = $false
        $cbTenant.IsEnabled = $true
        $btnLogin.IsEnabled = $true
    }

    Find-AzureCLI

    Add-LogEntry -LogEntry $script:PreGUIMessages -Severity Info
    $tbLoginUser.Text = $script:DefaultAccount
    FillTenantCB
    FillUnitLB
    Clear-Host

    $script:AMH.ShowDialog() | Out-Null
} #end function GenerateForm

#endregion Functions

#region Eventhandling

    $exContextOpen_MouseEnter = {
        If ($false -eq $exContextOpen.IsExpanded)
        {
             $exContextOpen.IsExpanded = $true
        }
    }

    $exContextOpen_MouseLeave = {
        If ($true -eq $exContextOpen.IsExpanded)
        {
             $exContextOpen.IsExpanded = $false
        }
    }

    $btnAzureModule_Click = {
        If ($false -eq $script:SkipAzModuleStatus)
        {
            $logstring = "verifying Azure module installation status"
            Add-LogEntry -LogEntry $logstring -Severity Info
            $btnAzureModule.Content = "verifying..."
            RefreshUI
            $logstring = "Installing Azure module"
            Add-LogEntry -LogEntry $logstring -Severity Info
            Add-Module -module Az
            if ($true -eq $script:AzModuleInstalled)
            {
                $lblAzureModuleStatus.Content = "installed"
                $btnAzureModule.Content = "Verify"
                $btnAzureModule.IsEnabled = $false
                $cbTenant.IsEnabled = $true
                $btnLogin.IsEnabled = $true
                RefreshUI
            }
            else
            {   
                $logstring = "Azure module not installed"
                Add-LogEntry -LogEntry $logstring -Severity Warning
                $lblAzureModuleStatus.Content = "not installed"}
            }
        elseif ($true -eq $script:SkipAzModuleStatus)
        {
            $logstring = "Azure module installation status skipped"
            Add-LogEntry -LogEntry $logstring -Severity Info
            $script:AzModuleInstalled = $true
            $lblAzureModuleStatus.Content = "skipped"
            $btnAzureModule.Content = "Verify"
            $btnAzureModule.IsEnabled = $false
            $cbTenant.IsEnabled = $true
            $btnLogin.IsEnabled = $true
            RefreshUI
        }
        RefreshUI
    }

    $btnLogin_Click = {
        if ($btnLogin.Content -eq "login")
        {
            if ($tbLoginUser.Text -eq "")
            {
                $logstring = "Please provide a valid account for the Azure login"
                Add-LogEntry -LogEntry $logstring -Severity Warning
            }
            else
            {
                if (($tbLoginUser.Text -match "@outlook.") -or ($tbLoginUser.Text -match "@live.") -or ($tbLoginUser.Text -match "@xbox.") -or ($tbLoginUser.Text -match "@hotmail.")) 
                {
                    $error.Clear()
                    try
                    {
                        $logstring = "Connecting MSA account $($tbLoginUser.Text)"
                        Add-LogEntry -LogEntry $logstring -Severity Info
                        Connect-AzAccount -Tenant $script:SelectedTenantID -SkipContextPopulation -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    }
                    catch
                    {
                        $logstring = "Cannot log in with MSA account $($tbLoginUser.Text)"
                        Add-LogEntry -LogEntry $logstring -Severity Error
                    }
                }
                else
                {
                    $script:cred = Get-Credential -UserName $tbLoginUser.Text -Message "Login credentials for the selected Azure tenant"
                    $error.Clear()
                    try
                    {
                        $logstring = "Connecting work or school account $($tbLoginUser.Text)"
                        Add-LogEntry -LogEntry $logstring -Severity Info
                        Connect-AzAccount -Tenant $script:SelectedTenantID -Credential $script:cred -SkipContextPopulation -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    }
                    catch
                    {
                        $logstring = "Cannot log in with work or school account $($tbLoginUser.Text)"
                        Add-LogEntry -LogEntry $logstring -Severity Error
                    }
                }
                If ($error.Count -eq 0)
                {
                    $script:logedin = $true
                    #$tbsbiCenter2.Text = $tbLoginUser.Text
                    $btnLogin.Content = "logout"
                    FillSubscriptionCB
                    If ($null -ne $script:SelectedSubscriptionID)
                    {
                        $logstring = "Context: $script:SelectedTenantName and $script:SelectedSubscriptionName"
                        Add-LogEntry -LogEntry $logstring -Severity Info
                        Set-AzContext -Tenant $script:SelectedTenantID -Subscription $script:SelectedSubscriptionID
                        FillRegionCB
                    }
                    else
                    {
                        $logstring = "No accessible subscription for user $($tbLoginUser.Text) in $script:SelectedTenantName"
                        Add-LogEntry -LogEntry $logstring -Severity Error
                    }
                    RefreshUI
                }
                else
                {
                    $script:logedin = $false
                    $logstring = "Error while logging in $($tbLoginUser.Text) to $script:SelectedTenantName"
                    Add-LogEntry -LogEntry $logstring -Severity Error
                }
            }
            ToggleDeployButtons -Toggle off
            RefreshUI
        }
        else
        { 
            LogoutCleanup 
        }
    }

    $cbTenant_DropDownClosed = {
        $script:SelectedTenantName = $cbTenant.SelectedItem.Content
        $script:SelectedTenantID = $cbTenant.SelectedItem.Tag
        If ($true -eq $script:logedin)
        {
            $cbSubscription.IsEnabled = $false
            FillSubscriptionCB
        }
        RefreshUI
    }

    $cbSubscription_DropDownClosed = {
        If ($true -eq $script:logedin)
        {
            $script:SelectedSubscriptionName = $cbSubscription.SelectedItem.Content
            $script:SelectedSubscriptionID = $cbSubscription.SelectedItem.Tag
            If ($null -ne $script:SelectedSubscriptionName) {
                $logstring = "Context: $script:SelectedTenantName and $script:SelectedSubscriptionName"
                Add-LogEntry -LogEntry $logstring -Severity Info
                Set-AzContext -Tenant $script:SelectedTenantID -Subscription $script:SelectedSubscriptionID
                FillResourceGroupCB
            }
            else
            {
                $cbResourceGroup.IsEnabled = $false
                $script:SelectedRecourcegroupName = $null
                $cbResourceGroup.Text = "(New) Resource group"
            }
        }
        RefreshUI
    }

    $cbRegion_DropDownClosed = {
        if ($true -eq $script:logedin)
        { 
            $script:SelectedRegionName = $cbRegion.SelectedItem.Name
            $script:SelectedRegionDisplayName = $cbRegion.SelectedItem.Content
        }
        RefreshUI
    }

    $cbResourceGroup_DropDownClosed = {
        $script:NewRecourcegroupName = $null
        $script:SelectedRecourcegroupName = $cbResourceGroup.SelectedItem.Content
        $script:SelectedRecourcegroupRegion = $cbRegion.SelectedItem.Tag
        RefreshUI 
    }

    $cbResourceGroup_GotFocus = {
        $script:NewRecourcegroupName = $null
        $script:SelectedRecourcegroupName = $cbResourceGroup.SelectedItem.Content
        $script:SelectedRecourcegroupRegion = $cbRegion.SelectedItem.Tag
        $script:NewRecourcegroupName = $cbResourceGroup.Text
        $btnRGCreate.IsEnabled = $true
        RefreshUI
    }

    $cbResourceGroup_LostFocus = {
        $script:SelectedRecourcegroupName = $cbResourceGroup.SelectedItem.Content
        $script:SelectedRecourcegroupRegion = $cbRegion.SelectedItem.Tag
        $script:NewRecourcegroupName = $cbResourceGroup.Text
    }

    $btnRGCreate_Click = {
        If ($script:NewRecourcegroupName)
        {
            $logstring = "New RG $script:NewRecourcegroupName in $script:SelectedRecourcegroupRegion"
            Add-LogEntry -LogEntry $logstring -Severity Info
            New-AzResourceGroup -Name $script:NewRecourcegroupName -Location $script:SelectedRecourcegroupRegion -Tag $script:AzResourceTag -Force
            $btnRGCreate.IsEnabled = $false
            FillResourceGroupCB
        }
    }

    $tbFilterUnits_TextChanged = {
        $lbUnits.ItemsSource = $null
        $script:UnitBtnFilteredSource.Clear()

        ForEach ($UnitBtn in $script:UnitBtnSource) 
        {
            If ($UnitBtn.Content -match $tbFilterUnits.Text) 
            {
                $script:UnitBtnFilteredSource.Add($UnitBtn)
            }
        }

        If ([string]::IsNullOrEmpty($tbFilterUnits.Text))
        {
            $lbUnits.ItemsSource = $script:UnitBtnSource
        }
        else
        {
            $lbUnits.ItemsSource = $script:UnitBtnFilteredSource
        }
    }

    $lblFilterUnitsClear_MouseLeftButtonDown = {
        $tbFilterUnits.Text = ""
        RefreshUI
    }

    $refreshUnitsList_MouseLeftButtonDown = {
        $imgRefreshUnits.Effect = $null
        $tbFilterUnits.Text = ""
        FillUnitLB
    }

    $refreshUnitsList_MouseLeftButtonUp = {
        $imgRefreshUnits.Effect = $script:DropdownShaddow
    }

    $lblRefreshUnits_MouseEnter = {
        If ($lblRefreshUnits.Background.Color -ne '#FFD3D3D3')  #"LightGray"
        {
            $lblRefreshUnits.Background = '#FFD3D3D3' #"LightGray"
        }
    }

    $lblRefreshUnits_MouseLeave = {
        If ($lblRefreshUnits.Background.Color -eq '#FFD3D3D3')  #"LightGray"
        {
            $lblRefreshUnits.Background = '#00FFFFFF'
        }
    }

    $lblRefreshScripts_MouseEnter = {
        If ($lblRefreshScripts.Background.Color -ne '#FFD3D3D3')  #"LightGray"
        {
            $lblRefreshScripts.Background = '#FFD3D3D3' #"LightGray"
        }
    }

    $lblRefreshScripts_MouseLeave = {
        If ($lblRefreshScripts.Background.Color -eq '#FFD3D3D3')  #"LightGray"
        {
            $lblRefreshScripts.Background = '#00FFFFFF'
        }
    }

    $refreshScripts_MouseLeftButtonDown = {
        $imgRefreshScripts.Effect = $null
        if ($null -ne $script:SelectedUnit)
        {
            $logstring = "refreshing deployment scripts"
            Add-LogEntry -LogEntry $logstring -Severity Info
        
            $tbUnitInfo.Text = ""
            $fdTemplate.Blocks.Clear()
            $fdParameter.Blocks.Clear()
            $fdPowerShell.Blocks.Clear()
            RefreshUI
            Start-Sleep -Seconds 1 # just to give a visual representation that something is happening when the refresh button is clicked

            FillUnitInfo
            FillUnitTemplate
            FillUnitTemplateParameter
            FillUnitPowerShell
            FillUnitAzureCLI
            $imgRefreshScripts.Effect = $script:DropdownShaddow
        }
    }

    $refreshScripts_MouseLeftButtonUp = {
        $imgRefreshScripts.Effect = $script:DropdownShaddow
    }

    $tabPowerShell_GotFocus = {
        FillUnitPowerShell
    }

    $tabAzureCLI_GotFocus = {
        FillUnitAzureCLI
    }

    $cbxVariableReplacement_Checked = {
        FillUnitPowerShell
        FillUnitAzureCLI
    }

    $cbxVariableReplacement_Unchecked = {
        FillUnitPowerShell
        FillUnitAzureCLI
    }

    $rtfTemplate_MouseDoubleClick = {
        & $script:DefaultEditor $script:UnitFileDeploy
    }

    $rtfParameter_MouseDoubleClick = {
        & $script:DefaultEditor $script:UnitFileParameter
    }

    $rtfPowerShell_MouseDoubleClick = {
        & $script:DefaultEditor $script:UnitFilePSScript
    }

    $rtfAzureCLI_MouseDoubleClick = {
        & $script:DefaultEditor $script:UnitFileAZScript
    }

    $deploytemplate = {
        $logstring = "Deploying with script: $script:UnitFileDeploy"
        Add-LogEntry -LogEntry $logstring -Severity Info
        
        if ($psversiontable.psversion.major -eq 5) # because ConvertFrom-Json added the parameter -AsHashtable later only local files will be used
        { # -TemplateFile & -TemplateParameterFile
            if ($false -eq $script:GitHubDeploymentJson)
            {
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateFile $script:UnitFileDeploy -TemplateParameterFile $script:UnitFileParameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            else
            {
                $logstring = "Cannot deploy GitHub scripts with this version of PowerShell"
                Add-LogEntry -LogEntry $logstring -Severity Error
            }
        }
        elseif ($psversiontable.psversion.major -gt 5)
        { # -TemplateObject & -TemplateParameterObject
            if (($true -eq $script:GitHubDeploymentJson) -and ($true -eq $script:GitHubDeploymentParameter))
            {
                $script:azuredeployjson = $script:azuredeployjson | ConvertFrom-Json -AsHashtable
                $script:azuredeployparameter = $script:azuredeployparameter | ConvertFrom-Json -AsHashtable
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateObject $script:azuredeployjson -TemplateParameterObject $script:azuredeployparameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            elseif (($true -eq $script:GitHubDeploymentJson) -and ($false -eq $script:GitHubDeploymentParameter))
            {
                $script:azuredeployjson = $script:azuredeployjson | ConvertFrom-Json -AsHashtable
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateObject $script:azuredeployjson -TemplateParameterFile $script:UnitFileParameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            elseif (($false -eq $script:GitHubDeploymentJson) -and ($true -eq $script:GitHubDeploymentParameter))
            {
                $script:azuredeployparameter = $script:azuredeployparameter | ConvertFrom-Json -AsHashtable
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateFile $script:UnitFileDeploy -TemplateParameterObject $script:azuredeployparameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue            
            }
            else
            { # reverting back to -TemplateFile & -TemplateParameterFile because the script is running on PS 7.x but with local files
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateFile $script:UnitFileDeploy -TemplateParameterFile $script:UnitFileParameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
        }
        Add-Output
    }

    $DeployUnitScript = {
        If ($true -eq $tabPowerShell.IsSelected)
        {
            DeployScript -UnitScript $script:UnitFilePSScript
        }
        If ($true -eq $tabAzureCLI.IsSelected)
        {
            DeployScript -UnitScript $script:UnitFileAZScript
        }
    }

    $sizeValueChanged = {
        FormResize -SelectedSize $sliderSize.Value
    }

    $AMHWindow_Closing = { 
        LogoutCleanup 
    }

    $exAzCliCred_Expanded = {
        ToggleAzCliExpander -expander $exAzCliCred
    }

    $exAzCliSP_Expanded = {
        ToggleAzCliExpander -expander $exAzCliSP
    }

    $exAzCliMI_Expanded = {
        ToggleAzCliExpander -expander $exAzCliMI
    }

    $btnAzCliCancel_Click = {
        Add-LogEntry -LogEntry "Azure Cli login is cancelled" -Severity Info
        $script:AzCliLogin.Close()
    }

    $btnAzCliLogin_Click = {
        $error.Clear()
        switch ($script:CliLoginType)
        {
        'CR'{
                If (($null -ne $txtUsernameCred.text) -and ($null -ne $pwbUserPassword.Password))
                {
                    try
                    {
                        $AzCliLogin = az login -u $($txtUsernameCred.text) -p $($pwbUserPassword.Password) | ConvertFrom-Json
                    }
                    catch [NativeCommandError]
                    {
                        Clear-Host
                        $script:CliLogin = $false
                        $logstring = $Error[0].Exception.Message
                        $logstring += "Login with credentials NOT successful"
                        Add-LogEntry -LogEntry $logstring -Severity Warning
                        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                        $imgAzCLIBulbCR.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                    }
                    catch
                    {
                        $script:CliLogin = $false
                    }
                }
                if (($error.Count -eq 0) -and ($AzCliLogin))
                {
                    $script:CliLogin = $true
                    Add-LogEntry -LogEntry "Azure Cli login with credentials successful" -Severity Info
                    $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                    $imgAzCLIBulbCR.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                }
                break
            }
        'SP'{
                If (($null -ne $txtSPnameCred.text) -and ($null -ne $pwbSPPassword.Password))
                {                        
                    try
                    {
                        $AzCliLogin = az login --service-principal -u $txtSPnameCred.text -p $pwbSPPassword.Password --tenant $txtSPTenantName.text
                    }
                    catch [NativeCommandError]
                    {
                        $script:CliLogin = $false
                        $logstring = $Error[0].Exception.Message
                        $logstring += "Login with service principal NOT successful"
                        Add-LogEntry -LogEntry $logstring -Severity Warning
                        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                        $imgAzCLIBulbSP.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                    }
                    catch
                    {
                        $script:CliLogin = $false
                        Add-LogEntry -LogEntry "Azure Cli login with service principal NOT successful" -Severity Warning
                        $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                    }
                }
                if (($error.Count -eq 0) -and ($AzCliLogin))
                {
                    $script:CliLogin = $true
                    Add-LogEntry -LogEntry "Azure Cli login with service principal successful" -Severity Info
                    $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                    $imgAzCLIBulbSP.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                }
                break
            }
        'MI'{
                If ($null -ne $txtMIDName.text)
                {          
                    try
                    {
                        $script:MITest = $null
                        $uri = "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
                        $script:MITest = Invoke-RestMethod -Method GET -Uri $uri -Headers @{"Metadata"="True"} -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                    catch [WebCmdletWebResponseException]
                    {
                        $logstring = "Azure Instance Metadata Service cannot be reached. Login with a managed identity is not possible."
                        Add-LogEntry -LogEntry $logstring -Severity Info
                    }
                    If ($script:MITest.compute.azEnvironment -eq "AzurePublicCloud") 
                    {
                        try
                        {
                            $AzCliLogin = az login --identity --username $txtMIDName.text
                        }
                        catch [NativeCommandError]
                        {
                            Clear-Host
                            $script:CliLogin = $false
                            $logstring = $Error[0].Exception.Message
                            $logstring += "Login with managed identity NOT successful"
                            Add-LogEntry -LogEntry $logstring -Severity Warning
                            $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                            $imgAzCLIBulbMI.Source = "$Script:ScriptFolder\Resources\bulbyellow.png"
                        }
                        catch
                        {
                            $script:CliLogin = $false
                        }
                    }
                    else
                    {
                        $logstring = "Login with a managed identity is not possible."
                        Add-LogEntry -LogEntry $logstring -Severity Info
                    }
                }
                if (($error.Count -eq 0) -and ($AzCliLogin))
                {
                    $script:CliLogin = $true
                    Add-LogEntry -LogEntry "Azure Cli login with managed identity successful" -Severity Info
                    $imgAzCLIBulb.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                    $imgAzCLIBulbMI.Source = "$Script:ScriptFolder\Resources\bulbgreen.png"
                }
                break
            }
        }
    }

    $imgAzCLIBulbCR_MouseLeftButtonDown = {
        LogoutAzCli
    }

    $imgAzCLIBulbSP_MouseLeftButtonDown = {
        LogoutAzCli
    }

    $imgAzCLIBulbMI_MouseLeftButtonDown = {
        LogoutAzCli
    }

    $imgAzCLIBulb_MouseLeftButtonDown = {
        InitializeAzCliForm
        GenerateAzCliForm
    }

#endregion Eventhandling

InitializeForm
GenerateForm