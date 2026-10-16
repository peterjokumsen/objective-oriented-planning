using './main.bicep'
param baseName = readEnvironmentVariable('BASE_NAME', 'oop')
param environment = readEnvironmentVariable('ENVIRONMENT', 'dev')
param location = readEnvironmentVariable('LOCATION', 'westeurope')
param resourceGroupName = readEnvironmentVariable('RG_NAME', '')
// The helloworld fallback is not a placeholder. On a first deploy there is no
// `api` repository in the ACR yet, so deploy.sh exports this fallback and the
// environment comes up running something; the real image is pushed by
// `az acr build` and the app is repointed at it.
param containerImage = readEnvironmentVariable('IMAGE', 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest')
param sharedResourceGroupName = readEnvironmentVariable('SHARED_RG_NAME', '')
param acrName = readEnvironmentVariable('SHARED_ACR_NAME', '')
