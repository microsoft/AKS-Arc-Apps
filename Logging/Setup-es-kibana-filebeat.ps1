# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
<#
    .PARAMETER installLogging
        installLogging boolean flag
    
    .PARAMETER uninstallLogging
        uninstallLogging boolean flag

    .PARAMETER kubeConfigFile
        clusterName Path

    .PARAMETER namespace
        namespace

    .PARAMETER forwardingLocalPort
        Local port to use for kubectl port forwarding

    .PARAMETER forwardingRemotePort
        Remote port to use for kubectl port forwarding
#>
param (
  [Parameter()]
  [bool] $installLogging,

  [Parameter()]
  [bool] $uninstallLogging,

  [Parameter(Mandatory = $true)]
  [string] $kubeconfigFile,

  [Parameter(Mandatory = $true)]
  [string] $namespace,

  [Parameter()]
  [ValidateRange(0, 65535)]
  [Int]$forwardingLocalPort = 5601,

  [Parameter()]
  [ValidateRange(0, 65535)]
  [Int]$forwardingRemotePort = 5601
)

function Install-Logging {
  <#
  .DESCRIPTION
      Helper function to install the logging addon on the target cluster.

  .PARAMETER kubeConfigFile
      cluster kubeConfigFile

  .PARAMETER namespace
      namespace
      
  .PARAMETER forwardingLocalPort
      Local port to use for kubectl port forwarding

  .PARAMETER forwardingRemotePort
      Remote port to use for kubectl port forwarding
  #>

  param (
    [Parameter(Mandatory = $true)]
    [String] $kubeConfigFile,

    [Parameter(Mandatory = $true)]
    [String] $namespace,

    [Parameter()]
    [ValidateRange(0, 65535)]
    [Int]$forwardingLocalPort,

    [Parameter()]
    [ValidateRange(0, 65535)]
    [Int]$forwardingRemotePort
  )

  Write-Host "Installing elastic operator"
  Write-Host "Creating namespace $namespace"
  $namespacecheck = kubectl.exe --kubeconfig=$kubeConfigFile get namespace | findstr $namespace
  if ($null -eq $namespacecheck) {
    Write-Host "namespace does not exist, Creating"
    kubectl.exe --kubeconfig=$kubeConfigFile create namespace $namespace
  }
  

  Write-Host "Downloading elastic operator manifests"
  $esOperatoryaml = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  wget https://download.elastic.co/downloads/eck/1.2.1/all-in-one.yaml -o $esOperatoryaml


  ## Add the nodeSelector
  (Get-Content $esOperatoryaml) | 
  Foreach-Object {
    if ($_ -match "containers:") {
      "      nodeSelector:"
      "        kubernetes.io/os: linux"
    }
    $_ 
  } | Set-Content $esOperatoryaml

  kubectl.exe --kubeconfig=$kubeConfigFile apply -f $esOperatoryaml
  Remove-Item $esOperatoryaml

  $esclusteryaml = @"
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elastic-cluster
  namespace: $namespace
spec:
  version: 7.9.2
  nodeSets:
  - name: default
    count: 3
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 50Gi
        storageClassName: default
    config:
      node.master: true
      node.data: true
      node.ingest: true
    podTemplate:
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
        nodeSelector:
          kubernetes.io/os: linux
"@

  $esclusteryamlFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $esclusteryamlFile -Value $esclusteryaml
  Write-Host "Creating namespace $namespace"
  $namespacecheck = kubectl.exe --kubeconfig=$kubeConfigFile get namespace | findstr $namespace
  if ($null -eq $namespacecheck) {
    Write-Host "namespace does not exist, Creating"
    kubectl.exe --kubeconfig=$kubeConfigFile create namespace $namespace
  }

  kubectl.exe --kubeconfig=$kubeConfigFile apply -f $esclusteryamlFile
  Remove-Item $esclusteryamlFile

  ## wait for ES cluster to be healthy
  Write-Host "waiting for ES cluster to be healthy."
  while ($true) {
    $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=1m -n $namespace pod -l common.k8s.elastic.co/type=elasticsearch"))
    if ($result -ne $null) {
      break
    }
    Write-Host "waiting for ES cluster to be healthy."
    Start-Sleep -Seconds 15
  }
  Write-Host "ES cluster is healthy." -ForegroundColor Green

  ## deploy kibana

  $kibanaYaml = @"
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: $namespace
spec:
  version: 7.9.2
  count: 1
  elasticsearchRef:
    name: elastic-cluster
  podTemplate:
    spec:
      nodeSelector:
        kubernetes.io/os: linux
"@

  $kibanayamlFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $kibanayamlFile -Value $kibanaYaml
  kubectl.exe --kubeconfig=$kubeConfigFile apply -f $kibanayamlFile
  Remove-Item $kibanayamlFile
  ## wait for kibana to be healthy
  Write-Host "waiting for kibana to be ready."
  while ($true) {
    $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=1m -n $namespace pod -l kibana.k8s.elastic.co/name=kibana"))
    if ($result -ne $null) {
      break
    }
    Write-Host "waiting for kibana to be ready."
    Start-Sleep -Seconds 15
  }
  Write-Host "kibana pod is ready." -ForegroundColor Green

  ## install filebeat using helm
  Write-Host "installing filebeat using helm"
  
  ## get the elastic-cluster password. username is elastic

  $PASSWORD=$(kubectl.exe --kubeconfig=$kubeConfigFile get secret elastic-cluster-es-elastic-user --namespace $namespace -o go-template='{{.data.elastic | base64decode}}')
  $filebeatvaluesYaml=@"
  filebeatConfig:
    filebeat.yml: |
      filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/*.log
        processors:
        - add_kubernetes_metadata:
            host: `${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
      output.elasticsearch:
        username: elastic
        password: $PASSWORD
        protocol: https
        hosts: ["elastic-cluster-es-http:9200"]
        ssl.verification_mode: "none"
  nodeSelector:
    kubernetes.io/os: linux
  hostNetworking: true
  tolerations: 
    - effect: NoSchedule
      operator: Exists
"@
  $customyamlFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $customyamlFile -Value $filebeatvaluesYaml

  helm.exe --kubeconfig $kubeConfigFile repo add elastic https://helm.elastic.co
  helm.exe --kubeconfig $kubeConfigFile install filebeat --version 7.9.2 elastic/filebeat --namespace $namespace -f $customyamlFile

  Write-Host "waiting for filebeat to be ready."
  while ($true) {
    $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=1m -n $namespace pod -l app=filebeat-filebeat"))
    if ($result -ne $null) {
      break
    }
    Write-Host "waiting for filebeat to be ready."
    Start-Sleep -Seconds 15
  }
  Write-Host "filebeat pod is ready." -ForegroundColor Green

  Write-Host "Starting port forwarder for Kibana"
  & start-process -FilePath "kubectl.exe" -ArgumentList $("--kubeconfig=$kubeconfigFile port-forward svc/kibana-kb-http "+$forwardingLocalPort+":"+$forwardingRemotePort+" -n=$namespace")
  Write-Host "Kibana is available at: https://localhost:$forwardingLocalPort/" -ForegroundColor Green

  Write-Host "Retrieving Kibana dashboard login Password"
  Write-Host $PASSWORD -ForegroundColor Yellow
  Write-Host "UserName is " -NoNewline
  Write-Host "elastic" -ForegroundColor Yellow
}

function Execute-KubeCtl {
  <#
    .DESCRIPTION
        Executes a kubectl command.

    .PARAMETER kubeconfig
        The kubeconfig file to use. Defaults to the management kubeconfig.

    .PARAMETER arguments
        Arguments to pass to the command.

    .PARAMETER ignoreError
        Optionally, ignore errors from the command (don't throw).

    .PARAMETER showOutput
        Optionally, show live output from the executing command.
    #>

  param (
    [string] $kubeconfig,
    [string] $arguments,
    [switch] $ignoreError,
    [switch] $showOutput
  )

  return Execute-Command -command kubectl.exe -arguments $("--kubeconfig=$kubeconfig $arguments") -showOutput:$showOutput.IsPresent -ignoreError:$ignoreError.IsPresent
}

function Execute-Command {
  <#
    .DESCRIPTION
        Executes a command and optionally ignores errors.

    .PARAMETER command
        Comamnd to execute.

    .PARAMETER arguments
        Arguments to pass to the command.

    .PARAMETER ignoreError
        Optionally, ignore errors from the command (don't throw).

    .PARAMETER showOutput
        Optionally, show live output from the executing command.
    #>

  param (
    [String]$command,
    [String]$arguments,
    [Switch]$ignoreError,
    [Switch]$showOutput
  )

  if ($showOutput.IsPresent) {
    $result = (& $command $arguments.Split(" ") | Out-Default)
  }
  else {
    $result = (& $command $arguments.Split(" ") 2>&1)
  }

  $out = $result | ? { $_.gettype().Name -ine "ErrorRecord" }  # On a non-zero exit code, this may contain the error
  $outString = ($out | Out-String).ToLowerInvariant()

  if ($LASTEXITCODE) {
    if ($ignoreError.IsPresent) {
      return
    }
    $err = $result | ? { $_.gettype().Name -eq "ErrorRecord" }
    throw "$command $arguments failed to execute [$err]"
  }
  return $out
}

function Uninstall-Logging {
  <#
  .DESCRIPTION
      Helper function to Uninstall the logging addon on the target cluster.

  .PARAMETER kubeConfigFile
      cluster kubeConfigFile

  .PARAMETER namespace
      namespace
  #>

  param (
    [Parameter(Mandatory = $true)]
    [String] $kubeConfigFile,
      
    [Parameter(Mandatory = $true)]
    [String] $namespace
  )

  Write-Host "Uninstalling logging"
  helm.exe --kubeconfig $kubeConfigFile delete filebeat --namespace $namespace
  $esclusteryaml = @"
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elastic-cluster
  namespace: $namespace
"@
  $esclusteryamlFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $esclusteryamlFile -Value $esclusteryaml
  kubectl.exe --kubeconfig=$kubeConfigFile delete -f $esclusteryamlFile

  Write-Host "Deleting operator"
  kubectl.exe --kubeconfig=$kubeConfigFile delete -f https://download.elastic.co/downloads/eck/1.2.1/all-in-one.yaml
}

if (($installLogging -eq $false -and $uninstallLogging -eq $false) -or ($installLogging -eq $true -and $uninstallLogging -eq $true)) {
  Write-Error "Please set either installLogging or uninstallLogging flag"
  exit
}

try {
  if ($installLogging -eq $true) {
        
    Install-Logging -kubeconfigFile $kubeconfigFile -namespace $namespace -forwardingLocalPort $forwardingLocalPort -forwardingRemotePort $forwardingRemotePort
  }
  elseif ($uninstallLogging -eq $true) {
    Uninstall-Logging -kubeConfigFile $kubeconfigFile -namespace $namespace
  }
  else {
    Write-Error "Unknown"
    exit
  }
}
catch [Exception] {
  Write-Error "Exception caught!!!" $_.Exception.Message.ToString()
        
}