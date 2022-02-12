# create shell variables
resourceGroup=AzClass
location=northeurope

az group create --name $resourceGroup --location $location

vnetName=TutorialVNet1
subnetName=TutorialSubnet1
vnetAddressPrefix=10.100.0.0/24
subnetAddressPrefix=10.100.0.0/26

az network vnet create \
  --name $vnetName \
  --resource-group $resourceGroup \
  --address-prefixes $vnetAddressPrefix \
  --subnet-name $subnetName \
  --subnet-prefixes $subnetAddressPrefix