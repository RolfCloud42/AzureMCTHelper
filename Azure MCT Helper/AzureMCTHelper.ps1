Clear-Host
Add-Type -AssemblyName PresentationFramework # needed when starting the script from the command line and not from the ISE
#Add-Type -AssemblyName System

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
    [bool]$script:UnitParameterChanged = $false
    
    $script:cred = $null

#endregion Generic_values

#region Settings
    # all of these values can be configured within $ScriptFolder\Resources\settings.json
    if ($script:UseSettingsJSON -eq $false)
    {
        $script:formCaption = 'Azure MCT Helper v0.7'
        $script:workdir = "$ScriptFolder\Units"
        $script:SkipAzModuleStatus = $true
        $script:DefaultTenant = ""
        $script:DefaultSubscription = ""
        $script:DefaultRegion = "northeurope"
        $script:DefaultRegionLong = "North Europe"
        $script:DefaultResourceGroup = "AzClass"
        $script:DefaultAccount = ""

        Write-Host "Settings loaded from script and tenants.csv..."
        $script:PreGUIMessages += "Settings loaded from script and tenants.csv..."
    }
#endregion Settings

#region functions

function Add-LogEntry {
    Param (
        [ValidateNotNullOrEmpty()]
        [string]$StatusMessage,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [array]$LogEntry,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Error", "Warning", "Info")]
        $Severity
    )

    $tbStatusMessage.Text = $StatusMessage

    If ([Array]$script:OldLogEntry -ne [Array]$LogEntry) {
    
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
    if ($script:AzModuleInstalled -eq $false)
    {
        $Modulstate = $false
        # If module is imported do nothing
        if (Get-Module -Name $module) {
            $Modulstate = $true 
            $logstring = "Module $module loaded"
            Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
        }
        else {
            # If module is not imported, but available on disk then import
            if ((Get-Module -ListAvailable).Name -eq $module) {
                Import-Module -Name $module
                $Modulstate = $true
                $logstring = "Module $module imported"
                Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
            }
            else {
                # If module is not imported, not available on disk, but is in online gallery then install and import
                if (Find-Module -Name $module) {
                    $logstring = "Module $module is not imported, not available on disk, but is in the online gallery. Installation and import will take a while"
                    Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Warning

                    Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber -Confirm:$False
                    Import-Module $module
                    $Modulstate = $true
                    $logstring = "Module $module installed and imported"
                    Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
                    
                }
                else {
                    # If module is not imported, not available and not in online gallery then abort
                    $logstring = "Module $module not imported, not available and not in online gallery, exiting advised."
                    Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
                }
            }
        }
    }
    If ($Modulstate -eq $true)
    {
        $script:AzModuleInstalled = $true
    }
    else
    {
        $script:AzModuleInstalled = $false
    }
} # end function Add-Module

function GetAMHSettings {
    if ($script:UseSettingsJSON -eq $true)
    {
        try
        {
            if(Test-Path -Path "$ScriptFolder\Resources\settings.json") {
                $script:settings = Get-Content -Path $ScriptFolder\Resources\settings.json | ConvertFrom-Json
                Write-Host "Settings loaded from JSON..."
                $script:PreGUIMessages += "Settings loaded from JSON..."
            }
            else {
                Write-Host "The settings file cannot be found. Reverting back to tenants.csv... " -BackgroundColor Red -ForegroundColor White
                $script:UseSettingsJSON = $false
                GetAMHSettings
            } 
        }
        catch
        {
            Write-Host " Error locating and loading the settings. Closing... " -BackgroundColor Red -ForegroundColor White
            Exit 1
        }

        $script:formCaption = $script:Settings.defaults.formCaption
        $script:workdir = Join-Path -path $scriptfolder -ChildPath $script:Settings.defaults.workdir
        $script:SkipAzModuleStatus = $script:Settings.defaults.SkipAzModuleStatus
        $script:DefaultTenant = $script:Settings.defaults.DefaultTenant
        $script:DefaultSubscription = $script:Settings.defaults.DefaultSubscription
        $script:DefaultRegion = $script:Settings.defaults.DefaultRegion
        $script:DefaultRegionLong = $script:Settings.defaults.DefaultRegionLong
        $script:DefaultResourceGroup = $script:Settings.defaults.DefaultResourceGroup
        $script:DefaultAccount = $script:Settings.accounts[$script:Settings.defaults.DefaultAccount]
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
    
    if ($script:UseSettingsJSON -eq $true)
    {
        $script:tenants = $script:settings.tenants
    }
    else
    {
        $script:tenants = Import-CSV -LiteralPath $ScriptFolder\Resources\tenants.csv -Header Name,Tag
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
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
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
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
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

    Get-ChildItem -Path $script:workdir | ForEach-Object {
        $UnitNewListBoxItem = New-Object -TypeName System.Windows.Controls.Button
        $UnitNewListBoxItem.Name = "btnUnit$(($_.Name).Split("-")[0])"
        $ButtonName = $UnitNewListBoxItem.Name
        $UnitNewListBoxItem.Content = "$(($_.Name).Split("-")[1])"
        $UnitNewListBoxItem.MinWidth = "200"
        $UnitNewListBoxItem.MinHeight = "30"
        $UnitNewListBoxItem.Padding = "5,1,5,2"
        $UnitNewListBoxItem.Margin = "0,5,0,3"
        $UnitNewListBoxItem.HorizontalAlignment = "Stretch"
        $UnitNewListBoxItem.Tag = $_.FullName

        $btnUnitScriptblock = CreateUnitScriptBlock -UnitName $ButtonName -UnitFolder "$($UnitNewListBoxItem.Tag)"

        $lbUnits.Items.Add($UnitNewListBoxItem) | Out-Null
        $UnitNewListBoxItem.Add_Click($btnUnitScriptblock)

        $script:AllControls.Add($UnitNewListBoxItem)
    } 
} # end function FillUnitLB

function FillUnitInfo {
    if(Test-Path -Path $script:UnitFileInfo) {
        $tbUnitInfo.Text = Get-Content -Path $script:UnitFileInfo
    }
    else {
        $tbUnitInfo.Text = "No file with the name info.txt found in unit folder"
    }
} # end function FillInitInfo

function FillUnitTemplate {
    $script:azuredeployjson = $null
    $script:GitHubDeploymentJson = $false
    if(Test-Path -Path $script:UnitFileDeploy)
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

    $fdTemplate.Blocks.Clear()
    Foreach ($line in $script:azuredeployjson)
    {
        $pTemplate = New-Object -TypeName System.Windows.Documents.Paragraph
        $pTemplate.Inlines.Add($line)
        $fdTemplate.Blocks.Add($pTemplate)
    }
} # end function FillUnitTemplate

function FillUnitTemplateParameter {
    $script:azuredeployparameter = $null
    $script:GitHubDeploymentParameter = $false
    if(Test-Path -Path $script:UnitFileParameter)
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
    $fdParameter.Blocks.Clear()
    Foreach ($line in $script:azuredeployparameter)
    {
        $pParameter = New-Object -TypeName System.Windows.Documents.Paragraph
        $pParameter.Inlines.Add($line)
        $fdParameter.Blocks.Add($pParameter)
    }
} # end function FillUnitTemplateParameter

function ReplaceScriptVariables ([string]$line2replace) {
    [string]$line2return = $null
    If ($null -ne $script:regions)
    {
            $script:regions.GetEnumerator() | ForEach-Object {
                if ($line2replace -match $_.Location)
                {
                    $line2return = $line2replace -replace $_.Location, $script:DefaultRegion
                }
                elseif ($line2replace -match $_.DisplayName)
                {
                    $line2return = $line2replace -replace $_.DisplayName, $script:DefaultRegionLong
                }
            }
    }
    else
    {
        $logstring = "Region list is not yet ready. Log in first."
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Warning
    }
    return $line2return
} # end function ReplaceScriptVariables

function FillUnitPowerShell {
    $fdPowerShell.Blocks.Clear()
    if(Test-Path -Path $script:UnitFileScript)
    {
        $azurescript = Get-Content -Path $script:UnitFileScript
        $cbxVariableReplacement.IsEnabled = $true
        $cbxVariableReplacement.Visibility = "Visible"
        $lblVariableReplacement.Visibility = "Visible"
        Foreach ($line in $azurescript)
        {
            if ($cbxVariableReplacement.IsChecked)
            {
                $modifiedline = ReplaceScriptVariables -line2replace $line
            }
            else
            {
                $modifiedline = $line
            }
            $pScript = New-Object -TypeName System.Windows.Documents.Paragraph
            $pScript.Inlines.Add($modifiedline)
            $fdPowerShell.Blocks.Add($pScript)
        }
    }
    else
    {
        $azurescript = "No file with the name azurescript.ps1 found in unit folder"
        $cbxVariableReplacement.Visibility = "Hidden"
        $lblVariableReplacement.Visibility = "Hidden"
        $cbxVariableReplacement.IsEnabled = $false
    }
} # end function FillUnitPowerShell

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

    if (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.parameters.json")
    {
        $script:UnitFileParameter = "$script:SelectedUnitFolder\azuredeploy.parameters.json"
    }
    elseif (Test-path -Path "$script:SelectedUnitFolder\azuredeploy.parameters.json.github.txt")
    {
        $script:UnitFileParameter = "$script:SelectedUnitFolder\azuredeploy.parameters.json.github.txt"
    }
    
    $script:UnitFileScript = "$script:SelectedUnitFolder\azurescript.ps1"
    
    FillUnitInfo
    FillUnitTemplate
    FillUnitTemplateParameter
    FillUnitPowerShell
    ToggleDeployButtons
} # end function ActivateActionPane

function ToggleDeployButtons ($Toggle) {
    If ($Toggle -eq "off")
    {
        $imgDeployActive.Visibility = "Hidden"
        $imgDeployInactive.Visibility = "Hidden"
        $imgScriptActive.Visibility = "Hidden"
        $imgScriptInactive.Visibility = "Hidden"
    }

    if (($null -ne $script:SelectedUnit) -and (Test-Path -Path $script:UnitFileDeploy))
    {
        if ($script:logedin -eq $true)
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

    if (($null -ne $script:SelectedUnit) -and (Test-Path -Path $script:UnitFileScript))
    {
        if ($script:logedin -eq $true)
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
    RefreshUI
} # end function ToggleDeployButtons

function FormResize ($SelectedSize) {
    $multiplier = $SelectedSize/100
    
    $AMHWindow.Width = $script:StartupWidth * $multiplier
    $AMHWindow.Height = $script:StartupHeight * $multiplier
    
    Foreach ($control in $script:AllControls)
    {
        if ($control.FontSize) {
            $control.FontSize = $script:StartupFontSize * $multiplier
        }
    }
    $script:sliderValueBefore = $sliderSize.Value
    RefreshUI
} # end function FormResize

function LogoutCleanup {
        $logstring = "So long and thank you for the fish."
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
        Add-LogEntry -LogEntry "--------------------------------------------------------" -Severity Info
        $script:cred = $null
        $script:logedin = $false
        $cbxTenant.IsChecked = $false
        $cbxSubscription.IsChecked = $false
        $tbsbiCenter2.Text = ""
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
        
        Disconnect-AzAccount

        $btnLogin.Content = "login"
        ToggleDeployButtons -Toggle "off"
        Set-Location -Path $ScriptFolder
    } # end function LogoutCleanup

function GenerateForm {
    
    $script:AllControls = [System.Collections.Generic.List[PSObject]]::new()

    $XAML.SelectNodes("//*[@Name]") | ForEach-Object {
        New-Variable -Name ($_.Name) -Value $AMH.FindName($_.Name) -PassThru | ForEach-Object {
            $script:AllControls.Add($_.Value)
        }
    }
    
    GetAMHSettings

    $AMHWindow.Add_Closing($AMHWindow_Closing)
    $btnAzureModule.Add_Click($btnAzureModule_Click)

    $btnLogin.Add_Click($btnLogin_Click)
    
    $cbTenant.Add_DropDownClosed($cbTenant_DropDownClosed)
    $cbSubscription.Add_DropDownClosed($cbSubscription_DropDownClosed)
    $cbSubscription.Add_SelectionChanged($cbSubscription_DropDownClosed)
    $cbRegion.Add_DropDownClosed($cbRegion_DropDownClosed)
    $cbResourceGroup.Add_DropDownClosed($cbResourceGroup_DropDownClosed)
    $cbResourceGroup.Add_GotFocus($cbResourceGroup_GotFocus)
    $cbResourceGroup.Add_LostFocus($cbResourceGroup_LostFocus)
    $btnRGCreate.Add_Click($btnRGCreate_Click)
    
    $imgDeployActive.Add_MouseLeftButtonDown($deploytemplate)
    $imgScriptActive.Add_MouseLeftButtonDown($deployscript)
    
    $sliderSize.Add_ValueChanged($sizeValueChanged)
    $cbxVariableReplacement.Add_Unchecked($cbxVariableReplacement_Unchecked)
    $cbxVariableReplacement.Add_Checked($cbxVariableReplacement_Checked)

    $script:DropdownShaddow = $imgRefreshUnits.Effect
    $imgRefreshUnits.Add_MouseLeftButtonDown($refreshUnitsList_MouseLeftButtonDown)
    $imgRefreshUnits.Add_MouseLeftButtonUp($refreshUnitsList_MouseLeftButtonUp)
    $imgRefreshScripts.Add_MouseLeftButtonDown($refreshScripts_MouseLeftButtonDown)
    $imgRefreshScripts.Add_MouseLeftButtonUp($refreshScripts_MouseLeftButtonUp)

    $AMH.Title = $script:formCaption
    $script:StartupWidth = $AMHWindow.Width
    $script:StartupHeight = $AMHWindow.Height
    $script:StartupFontSize = $AMHWindow.FontSize

    $imgDeployActive.Source = "$ScriptFolder\Resources\DeployActive.png"
    $imgDeployInactive.Source = "$ScriptFolder\Resources\DeployInactive.png"
    $imgScriptActive.Source = "$ScriptFolder\Resources\ScriptActive.png"
    $imgScriptInactive.Source = "$ScriptFolder\Resources\ScriptInactive.png"
    $imgRefreshUnits.Source = "$ScriptFolder\Resources\btnRefresh.png"
    $imgRefreshScripts.Source = "$ScriptFolder\Resources\btnRefresh.png"

    $script:SelectedTenantName = $cbTenant.SelectedItem.Content
    $script:SelectedTenantID = $cbTenant.SelectedItem.Tag
  
    Add-LogEntry -LogEntry "Azure MCT Helper tool started: $(Get-Date)" -Severity Info
    
    if ($script:SkipAzModuleStatus -eq $false) {
        $lblAzureModuleStatus.Content = $script:AzModuleStatus
    }
    elseif ($script:SkipAzModuleStatus -eq $true) {
        $lblAzureModuleStatus.Content = "skipped"
        $script:AzModuleInstalled = $true
        Add-Module -module Az
        $btnAzureModule.IsEnabled = $false
        $cbTenant.IsEnabled = $true
        $btnLogin.IsEnabled = $true
    }

    Add-LogEntry -LogEntry $script:PreGUIMessages -Severity Info
    $tbLoginUser.Text = $script:DefaultAccount
    FillTenantCB
    FillUnitLB
    Clear-Host

    $AMH.ShowDialog() | Out-Null
} #end function GenerateForm

#endregion functions

#region Init
    $ScriptFolder = Get-ScriptDirectory
    $script:workdir = "$ScriptFolder\Units" # now with an actual value and not just generic
    Set-Location -Path $script:workdir

    try
    {
        # Test-Path will return true or false and that does not trigger an error if the file is not there
        Copy-Item -Path "C:\Users\RolfMcLaughl_cqz\source\repos\AzureMCTHelper\AzureMCTHelper\MainWindow.xaml" -Destination "C:\Users\RolfMcLaughl_cqz\OneDrive\PowerShell\Azure MCT Helper\Resources" -Force
    
        if(Test-Path -Path "$ScriptFolder\Resources\MainWindow.xaml")
        {
            [XML]$XAML = (Get-Content $ScriptFolder\Resources\MainWindow.xaml) -replace 'Page','Window'
        }
        else
        {
            Write-Host " The form cannot be found. Closing... " -BackgroundColor Red -ForegroundColor White
            Exit 1
        } 
    }
    catch
    {
        Write-Host " Error locating and loading the form. Closing... " -BackgroundColor Red -ForegroundColor White
        Exit 1
    }

    $XAML.Window.RemoveAttribute("x:Class") #removing attributes which are coming from the editor 
    $XAML.Window.RemoveAttribute("xmlns:mc")
    $XAML.Window.RemoveAttribute("mc:Ignorable")

    $Reader = New-Object System.Xml.XmlNodeReader $XAML
    $AMH = [Windows.Markup.XamlReader]::Load($Reader)

#endregion Init

#region Eventhandling
    
    $btnAzureModule_Click = {
    If ($script:SkipAzModuleStatus -eq $false)
    {
        $logstring = "verifying Azure module installation status"
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
        $btnAzureModule.Content = "verifying..."
        RefreshUI
        $logstring = "Installing Azure module"
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
        Add-Module -module Az
        if ($script:AzModuleInstalled -eq $true)
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
            Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Warning
            $lblAzureModuleStatus.Content = "not installed"}
        }
    elseif ($script:SkipAzModuleStatus -eq $true)
    {
        $logstring = "Azure module installation status skipped"
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
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
                Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Warning
            }
            else
            {
                if (($tbLoginUser.Text -match "@outlook.") -or ($tbLoginUser.Text -match "@live.") -or ($tbLoginUser.Text -match "@xbox.") -or ($tbLoginUser.Text -match "@hotmail.")) 
                {

                    $error.Clear()
                    try
                    {
                        $logstring = "Connecting MSA account $($tbLoginUser.Text)"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
                        Connect-AzAccount -Tenant $script:SelectedTenantID -SkipContextPopulation -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    }
                    catch
                    {
                        $logstring = "Cannot log in with MSA account $($tbLoginUser.Text)"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
                    }
                }
                else
                {
                    $script:cred = Get-Credential -UserName $tbLoginUser.Text -Message "Login credentials for the selected Azure tenant"
                    $error.Clear()
                    try
                    {
                        $logstring = "Connecting work or school account $($tbLoginUser.Text)"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
                        Connect-AzAccount -Tenant $script:SelectedTenantID -Credential $script:cred -SkipContextPopulation -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    }
                    catch
                    {
                        $logstring = "Cannot log in with work or school account $($tbLoginUser.Text)"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
                    }
                    
                }
                If ($error.Count -eq 0)
                {
                    $script:logedin = $true
                    $cbxTenant.IsChecked = $true
                    $tbsbiCenter2.Text = $tbLoginUser.Text
                    $btnLogin.Content = "logout"
                    FillSubscriptionCB
                    If ($null -ne $script:SelectedSubscriptionID)
                    {
                        $logstring = "Context: $script:SelectedTenantName and $script:SelectedSubscriptionName"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
                        Set-AzContext -Tenant $script:SelectedTenantID -Subscription $script:SelectedSubscriptionID
                        FillRegionCB
                    }
                    else
                    {
                        $logstring = "No accessible subscription for user $($tbLoginUser.Text) in $script:SelectedTenantName"
                        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
                    }
                    RefreshUI
                }
                else
                {
                    $script:logedin = $false
                    $cbxTenant.IsChecked = $false
                    $tbsbiCenter2.Text = ""
                    $logstring = "Error while logging in $($tbLoginUser.Text) to $script:SelectedTenantName"
                    Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
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
        If ($script:logedin -eq $true)
        {
            $cbSubscription.IsEnabled = $false
            FillSubscriptionCB
        }
        RefreshUI
    }

    $cbSubscription_DropDownClosed = {
        If ($script:logedin -eq $true)
        {
            $script:SelectedSubscriptionName = $cbSubscription.SelectedItem.Content
            $script:SelectedSubscriptionID = $cbSubscription.SelectedItem.Tag
            If ($null -ne $script:SelectedSubscriptionName) {
                $logstring = "Context: $script:SelectedTenantName and $script:SelectedSubscriptionName"
                Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
                Set-AzContext -Tenant $script:SelectedTenantID -Subscription $script:SelectedSubscriptionID
                $cbxSubscription.IsChecked = $true
                FillResourceGroupCB
            }
            else
            {
                $cbxSubscription.IsChecked = $false
                $cbResourceGroup.IsEnabled = $false
                $script:SelectedRecourcegroupName = $null
                $cbResourceGroup.Text = "(New) Resource group"
            }
            #RefreshUI
            
        }
        RefreshUI
    }

    $cbRegion_DropDownClosed = {
        if ($script:logedin -eq $true)
        { 
            $script:SelectedRegionName = $cbRegion.SelectedItem.Name
            $script:SelectedRegionDisplayName = $cbRegion.SelectedItem.Content
            #FillResourceGroupCB
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
            Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
            New-AzResourceGroup -Name $script:NewRecourcegroupName -Location $script:SelectedRecourcegroupRegion -Tag $script:AzResourceTag -Force
            $btnRGCreate.IsEnabled = $false
            FillResourceGroupCB
        }
    }

    $refreshUnitsList_MouseLeftButtonDown = {
        $imgRefreshUnits.Effect = $null
        FillUnitLB
    }

    $refreshUnitsList_MouseLeftButtonUp = {
        $imgRefreshUnits.Effect = $script:DropdownShaddow
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
            $imgRefreshScripts.Effect = $script:DropdownShaddow
        }
    }

    $refreshScripts_MouseLeftButtonUp = {
        $imgRefreshScripts.Effect = $script:DropdownShaddow
        #RefreshUI
    }

    $cbxVariableReplacement_Checked = {
        FillUnitPowerShell
    }

    $cbxVariableReplacement_Unchecked = {
        FillUnitPowerShell
    }

    $deploytemplate = {

        $logstring = "Deploying with script: $script:UnitFileDeploy"
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info
        
        if ($psversiontable.psversion.major -eq 5) # because ConvertFrom-Json added the parameter -AsHashtable later only local files will be used
        { # -TemplateFile & -TemplateParameterFile
            if ($script:GitHubDeploymentJson -eq $false)
            {
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateFile $script:UnitFileDeploy -TemplateParameterFile $script:UnitFileParameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            else
            {
                $logstring = "Cannot deploy GitHub scripts with this version of PowerShell"
                Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Error
            }
        }
        elseif ($psversiontable.psversion.major -gt 5)
        { # -TemplateObject & -TemplateParameterObject
            if (($script:GitHubDeploymentJson -eq $true) -and ($script:GitHubDeploymentParameter -eq $true))
            {
                $script:azuredeployjson = $script:azuredeployjson | ConvertFrom-Json -AsHashtable
                $script:azuredeployparameter = $script:azuredeployparameter | ConvertFrom-Json -AsHashtable
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateObject $script:azuredeployjson -TemplateParameterObject $script:azuredeployparameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            elseif (($script:GitHubDeploymentJson -eq $true) -and ($script:GitHubDeploymentParameter -eq $false))
            {
                $script:azuredeployjson = $script:azuredeployjson | ConvertFrom-Json -AsHashtable
                $script:AzureOutput = New-AzResourceGroupDeployment -ResourceGroupName $script:SelectedRecourcegroupName -TemplateObject $script:azuredeployjson -TemplateParameterFile $script:UnitFileParameter -Tag $script:AzResourceTag -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            elseif (($script:GitHubDeploymentJson -eq $false) -and ($script:GitHubDeploymentParameter -eq $true))
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

    $deployscript = {
        $logstring = "Deploying with script: $script:UnitFileScript"
        Add-LogEntry -StatusMessage $logstring -LogEntry $logstring -Severity Info

        $PSscript = Get-Content $script:UnitFileScript
        if ($cbxVariableReplacement.IsChecked -eq $true)
        {
            $PSscript = ReplaceScriptVariables -line2replace $PSscript
        }
        $PSScriptBlock = [scriptblock]::Create($PSscript)
        $script:AzureOutput = Invoke-Command -ScriptBlock $PSScriptBlock -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Add-Output
    }

    $sizeValueChanged = {
        FormResize -SelectedSize $sliderSize.Value
    }

    $AMHWindow_Closing = { 
        LogoutCleanup 
    }

#endregion Eventhandling

GenerateForm