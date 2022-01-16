# AzureMCTHelper

PowerShell script with WPF GUI for easy usage of Azure tasks during training  

![Image of Azure MCT Helper main window](/media/docu_AzureMCTHelper_main_window.png)

## 1st things first

Do not use this script in production unless you consider your training environment as production.
The script is provided as is and no support or warranties are given.

## Installation of the Azure MCT Helper

Place the script and its subfolders in any folder on your system. Make sure that the execution of PowerShell scripts is allowed for the account you are using. You do not need administrative rights to run the script, although the installation of the Azure PowerShell module is required. The script will not work as intended without it.

### Initial configuration

There are two files in the folder "Resources", settings.json and tenants.csv. If you are intending to use the settings.json file, ignore the tenants.csv file. You can toggle between these two files through the variable `$script:UseSettingsJSON` in the actual script file AzureMCTHelper.ps1.

![screenshot of settings.json file](/media/docu_settings_json.png)

The settings.json file has three sections as well as the version section.

* defaults
* tenants
* accounts

#### Defaults section

In the defaults section, you can pre-configure values to become values of variables used in the script. If you don't want to use the settings.json file you can set default values for the needed variables in the actual script file.
These are the variables you need to replace with your own values:

```powershell
        $script:formCaption = 'Azure MCT Helper v0.9'
        $script:workdir = "$ScriptFolder\Units"
        $script:SkipAzModuleStatus = $true
        $script:DefaultTenant = ""
        $script:DefaultSubscription = ""
        $script:DefaultRegion = "northeurope"
        $script:DefaultRegionLong = "North Europe"
        $script:DefaultResourceGroup = "AzClass"
        $script:DefaultAccount = "0"
```

#### Tenants section

In the tenants section, list the tenants name and IDs you want to authenticate against. Both values, Name and ID, are required for a successful login.The tenants section populates the dropdown list "Tenant selection" in the UI.
>**Note** The script will not work properly without this information and you need at least one entry.

#### Accounts section

In this section, list the user account names you want to use in your script. There will be no passwords stored. From your list, pick one entry to become your default account by setting the value of the respective variable `$script:DefaultAccount` to its numbered place in the list.
>**Note** Remember that the numbering starts with zero (0).
The DefaultAccount will be added to the login textbox, but you can always overwrite the value in the textbox during the runtime of the script. This is an optional configuration as the script will work properly without this information, unless the value of the variable `$script:DefaultAccount` is incorrect.

## The user interface (UI)

The UI has three separate areas to work with. To the left there is the context area, the middle is the unit area, and the area on the right is the script area.

### Context area

Through the separate controls the Azure context is configured. The context includes the tenant and Azure subscription selection and the resource group, that will be used for the unit deployments. Depending on the user credentials and subsequent selections in the UI the Azure context will be adjusted.

The dropdown list "Resource group(s)" even allows you to create new resource groups based on the information provided.

### Unit area

 