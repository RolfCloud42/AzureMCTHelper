# AzureMCTHelper

PowerShell script with WPF GUI for easy usage of Azure tasks during Microsoft trainings
![Image](http://./image.png)

## 1st things first

Do not use this script in production unless you consider your training environment as production.
The script is provided as is and no support or warranties are given or possible.

## How to use the Azure MCT Helper

Place the script and its subfolders in any folder on your system. Make sure that the execution of PowerShell scripts is allowed for the account you are using. You do not need administrative rights to run the script. Although the installation of the Azure PowerShell module is required. The script will not work as intended without it.

## Initial configuration

There are two files in the folder "Resources". The settings.json and the tenants.csv. If you are intending to use the settings.json you can ignore the tenants.csv file. You can toggle between using the settings vs the tenants file through the variable $script:UseSettingsJSON in the actual script file AzureMCTHelper.ps1.

The settings.json has three sections beside the version.

* defaults
* tenants
* accounts

In the defaults section you pre-configure values to become values of variables used in the script.
In the tenants section you list the tenants name and IDs and finally in the accounts section the user accounts you want to use are stored.
There is no need and place to store passwords!

The tenants section fills a dropdown in the GUI and the DefaultAccount, starting with zero (0), will be added to the login textbox.

 