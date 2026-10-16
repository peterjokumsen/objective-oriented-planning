@export()
type EnvironmentType = 'dev' | 'test' | 'prod'

@export()
type GlobalInputs = {
  @description('The location of the resources.')
  location: string
  @description('The base name for all resources.')
  baseName: string
  @description('Container image to use for the container app.')
  containerImage: string
  @description('The environment name.')
  environment: EnvironmentType
}
