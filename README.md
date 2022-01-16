# AzureMCTHelper

PowerShell script with WPF GUI for easy usage of Azure tasks during Microsoft trainings  

![AzureMCTHelper main window](https://github.com/RolfCloud42/AzureMCTHelper/blob/main/media/docu_AzureMCTHelper_main_window.png)

## 1st things first

Do not use this script in production unless you consider your training environment as production.
The script is provided as is and no support or warranties are given or possible.

## How to use the Azure MCT Helper

Place the script and its subfolders in any folder on your system. Make sure that the execution of PowerShell scripts is allowed for the account you are using. You do not need administrative rights to run the script. Although the installation of the Azure PowerShell module is required. The script will not work as intended without it.

## Initial configuration

There are two files in the folder "Resources". The settings.json and the tenants.csv. If you are intending to use the settings.json you can ignore the tenants.csv file. You can toggle between using the settings vs. the tenants file through the variable $script:UseSettingsJSON in the actual script file AzureMCTHelper.ps1.

![settings.son file](https://github.com/RolfCloud42/AzureMCTHelper/blob/main/media/docu_settings_json.png)

The settings.json has three sections beside the version section:

* defaults
* tenants
* accounts

### Defaults section

In the defaults section you pre-configure values to become values of variables used in the script.

In case you do not want to use the settings.json file you can set default values for the needed variables in the actual script file.
These are the variables you need to fill with your own values:

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

### Tenants section

In the tenants section you list the tenants name and IDs you want to authenticate against. Both values, Name and ID, are needed for a successful login.
The tenants section fills a dropdown list in the GUI. The script will not work properly without this information and you need at least one entry.

### Accounts section

In this section you can list the user account names you want to use in your script. There will be no passwords stored.
From your list you can pick one entry to become your default account by setting the value of the respective variable `$script:DefaultAccount` to its numbered place in the list.
The DefaultAccount will be added to the login textbox, but you can always overwrite the value in the textbox during the runtime of the script.
> Remember that the numbering starts with zero (0).
This is an optional configuration and the script will work properly without this information unless you set a value of the variable `$script:DefaultAccount` and this value does not exist.
