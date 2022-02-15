# AzureMCTHelper

PowerShell script with WPF GUI for easy usage of Azure tasks during training  

![Image of Azure MCT Helper main window](/media/docu_AzureMCTHelper_main_window.png)

## 1st things first

Do not use this script in production unless you consider your training environment as production.
The script is provided as is and no support or warranties are given.

## Installation of the Azure MCT Helper

Place the script and its subfolders in any folder on your system. Make sure that the execution of PowerShell scripts is allowed for the account you are using. There are no administrative rights needed to run the script, although the installation of the Azure PowerShell module is required. The script will not work as intended without it. Optionally the installation of the Azure CLI module is required in case the unit contains shell files.

### Initial configuration

There are two configuration files in the folder "Resources", settings.json and tenants.csv. If you are intending to use the settings.json file, ignore the tenants.csv file. You can toggle between these two files through the variable `$script:UseSettingsJSON` in the actual script file AzureMCTHelper.ps1. The default is to use the JSON file for configuration.

The settings.json file has four sections as well as the version section.

* defaults
* tenants
* accounts
* editors

#### settings.json

```json
{
    "version": "1",
    "defaults": {
        "formCaption": "Azure MCT Helper v0.9",
        "workdir": "Units",
        "SkipAzModuleStatus": false,
        "DefaultTenant": "Contoso Training",
        "DefaultSubscription": "Azure Pass",
        "DefaultRegion": "northeurope",
        "DefaultRegionLong": "North Europe",
        "DefaultResourceGroup": "AzClass",
        "DefaultAccount": "1",
        "DefaultEditor": "0"
        },
    "tenants": [
        {
            "Name": "Contoso Training",
            "ID": "12345678-1234-5678-abcd-12345678abcd"
        },
        {
            "Name": "Contoso",
            "ID": "12345678-5678-1234-abcd-12345678abcd"
        }
    ],
    "accounts": [
        "rolf@contosodemo.com",
        "rolf@contoso.com"
    ],
    "editors": [
        "code",
        "ise",
        "notepad"
    ]
}
```

#### Defaults section

In the defaults section, you can pre-configure values to become values of variables used in the script. If you don't want to use the settings.json file you can set default values for the needed variables in the actual script file.
These are the variables you need to replace with your own values:

```powershell
        $script:formCaption = 'Azure MCT Helper v0.9'
        $script:workdir = "Units"
        $script:SkipAzModuleStatus = $false
        $script:DefaultTenant = ""
        $script:DefaultSubscription = ""
        $script:DefaultRegion = "northeurope"
        $script:DefaultRegionLong = "North Europe"
        $script:DefaultResourceGroup = "AzClass"
        $script:DefaultAccount = "0"
        $script:DefaultEditor = "0"
```

#### Tenants section

In the tenants section, list the tenants name and IDs you want to authenticate against. Both values, Name and ID, are required for a successful login.The tenants section populates the dropdown list "Tenant selection" in the UI.
>**Note** The script will not work properly without this information and you need at least one entry.

#### Accounts section

In this section, list the user account names you want to use in your script. There will be no passwords stored. From your list, pick one entry to become your default account by setting the value of the respective variable `$script:DefaultAccount` to its numbered place in the list.
>**Note** Remember that the numbering starts with zero (0).
The DefaultAccount will be added to the login textbox, but you can always overwrite the value in the textbox during the runtime of the script. This is an optional configuration as the script will work properly without this information, unless the value of the variable `$script:DefaultAccount` is incorrect.

#### Editors section

In the last section of the settings.json a choice out of three editors for the files is possible. The options are VS Code, PowerShell ISE and notepad. The editors are incorporated in the script and cannot be changed to anything other than the three editors offered.
As with the default account the default editor is selected by setting the number of the editors place in the defaults section.
>**Note** Remember that the numbering starts with zero (0).
A value of 0 selects VS Code as default editor. A double click with the left mouse button on any file shown in the tabs on the right side of the tool will start the selected editor.

## The user interface (UI)

The UI has three separate areas to work with. To the left there is the context area, the middle is the unit area, and the area on the right is the script area.

### Context area

Through the separate controls the Azure context is configured. The context includes the tenant and Azure subscription selection and the resource group, that will be used for the unit deployments if not configured otherwise in the scripts. Depending on the user credentials and subsequent selections in the UI the Azure context will be adjusted. The dropdown list "Resource group(s)" even allows you to create new resource groups based on the information provided.

### Unit area

The unit area is the main selection area for the scripts. Each button represent one folder in the units folder. The units folder is defined through the variable `$script:workdir` which by itself can be configured in the settings.json or the script itself as described earlier.

Each of the folders represents one scenario that can be deployed. Files in each unit folder can be any of the following list:

* info.txt
* azuredeploy.json
* azuredeploy.parameters.json
* azuredeploy.json.github.txt
* azuredeploy.parameters.json.github.txt
* azurescript.ps1
* azurescript.sh

All of the files are optional and the author of the unit can decide which files to use. The names of the files are mandatory though.
Each button representing a unit takes its name from the unit folder. A search box is located above the button list to filter the units based on their name. At the bottom of the unit area is a refresh button to load the list of units again, in case unit folders were modified after the launch of the script.

### Script area

The main component of the script are are the tabs showing the content of the script files which are loaded upon selection of one of the unit buttons. Each file is optional and are in the responsibility of the author of the unit files. Each file has a defined purpose.

***info.txt***
It can be used to describe the unit and give some background information about what is going to be deployed to Azure. It is an optional file and when it is in the unit folder its content will be displayed on the top of the script area.

***azuredeploy.json***
As within Azure itself `azuredeploy.json` files can be used as templates to deploy Azure resources. Under the hood the PowerShell cmdlet `New-AzResourceGroupDeployment` is used together with the provided template file to achieve the same result through this tool.

***azuredeploy.parameters.json***
Together with the above mentioned file `azuredeploy.json` the resources get the parameter values passed on to customize the deployment to your needs. Together the two files are used by `New-AzResourceGroupDeployment` to create the resources in Azure.

***azuredeploy.json.github.txt***
If the unit, that should be deployed, already exists on GitHub, the azuredeploy.json.github.txt file provide a way to just point to the URL of the file. So a unit leveraging the Azure storage account quickstart template on GitHub would contain a file in its unit folder named `azuredeploy.json.github.txt` with just one line of text in it pointing to this link: [https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.storage/storage-account-create/azuredeploy.json](https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.storage/storage-account-create/azuredeploy.json).

***azuredeploy.parameters.json.github.txt***
Following the same principle the file `azuredeploy.parameters.json.github.txt` can be placed into the unit folder and only contain one line of text representing the URL to the parameters file of the same GitHub example. In the above mentioned case this would be: [https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.storage/storage-account-create/azuredeploy.parameters.json](https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.storage/storage-account-create/azuredeploy.parameters.json).

>**Note** Deployments using the GitHub files require to run the Azure MCT Helper script with PowerShell 7. The reason behind that is a newer version of the Cmdlet `ConvertFrom-Json`. This version supports the creation of hash tables which subsequently can be used as parameter objects for the Cmdlet `New-AzResourceGroupDeployment` instead of pointing to local files.

***azurescript.ps1***
Another option to deploy resources to Azure is through native PowerShell scripts. They require the Azure PowerShell module to be installed.
Once the module is installed and a login in the context area has been successful the scripts can be run.

>**Note** Do not use interactive login or the Cmdlet `Get-Credential` in the scripts that you place in the unit folder.

***azurescript.sh***
Another option to deploy resources to Azure is through native Bash scripts. They require the Azure CLI to be installed.
One the CLI is installed the script will identify the installation and allow the login to Azure CLI as well as the execution of shell scripts.
There is no need to install the Linux subsystem to run the shell scripts to deploy Azure resources.

#### Azure CLI Installation and login

If the Azure CLI is not already installed on your system you download and install it from here: [https://docs.microsoft.com/cli/azure/install-azure-cli](https://docs.microsoft.com/cli/azure/install-azure-cli).

The script will identify the installed software and show a yellow bulb on the Azure CLI tab in the script section. If the Azure CLI is not installed the bulb will be red.

Select the yellow bulb to open the Azure CLI login page.
