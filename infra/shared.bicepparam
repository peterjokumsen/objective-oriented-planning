using './shared.bicep'
param baseName = readEnvironmentVariable('BASE_NAME', 'oop')
param location = readEnvironmentVariable('LOCATION', 'westeurope')
// Empty default is deliberate: scripts/common.sh computes this from BASE_NAME and
// exports it. An empty value fails the deployment loudly rather than silently
// creating a group called rg--shared.
param sharedResourceGroupName = readEnvironmentVariable('SHARED_RG_NAME', '')
