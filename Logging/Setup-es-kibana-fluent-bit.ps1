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
  Start-Sleep -Seconds 30
  for($i = 0; $i -le 10; $i++) {
    $pods = ((& kubectl.exe --kubeconfig=$kubeConfigFile get pods -n $namespace -l common.k8s.elastic.co/type=elasticsearch -o json) | ConvertFrom-Json) 2>$null
    $runnigPodsCount = 0
    foreach ( $pod in $pods.items) {
      if ($pod.status.phase -ieq "Running") {
          $runnigPodsCount++
      }
    }
    Write-Host "$runnigPodsCount pods are running" 
    if($runnigPodsCount -eq 3)
    {
      break
    }
    if($i -eq 9)
    {
      throw "elasticsearch is not in ready state"
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
  Start-Sleep -Seconds 30
  for($i = 0; $i -le 10; $i++) {
    $pods = ((& kubectl.exe --kubeconfig=$kubeConfigFile get pods -n $namespace -l kibana.k8s.elastic.co/name=kibana -o json) | ConvertFrom-Json) 2>$null
    $runnigPodsCount = 0
    foreach ( $pod in $pods.items) {
      if ($pod.status.phase -ieq "Running") {
          $runnigPodsCount++
      }
    }
    if($runnigPodsCount -eq 1)
    {
      break
    }
    if($i -eq 9)
    {
      throw "Kibana is not in ready state"
    }
    Write-Host "waiting for kibana to be ready."
    Start-Sleep -Seconds 15
  }
  
  Write-Host "kibana pod is ready." -ForegroundColor Green

  ## install fluent-bit using helm
  Write-Host "installing fluent-bit using helm"
  
  ## get the elastic-cluster password. username is elastic

  $PASSWORD=$(kubectl.exe --kubeconfig=$kubeConfigFile get secret elastic-cluster-es-elastic-user --namespace $namespace -o go-template='{{.data.elastic | base64decode}}')
  $fluentbitvaluesYaml=@"
config:
  ## https://docs.fluentbit.io/manual/service
  service: |
    [SERVICE]
        Flush 1
        Daemon Off
        Log_Level Info
        Parsers_File parsers.conf
        Parsers_File custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
  ## https://docs.fluentbit.io/manual/pipeline/inputs
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        Parser docker
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On
  ## https://docs.fluentbit.io/manual/pipeline/filters
  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On
  ## https://docs.fluentbit.io/manual/pipeline/outputs
  outputs: |
    [OUTPUT]
        Name  es
        Match kube.*
        Host elastic-cluster-es-http
        Port 9200
        Logstash_Format On
        Retry_Limit False
        Type  flb_type
        Time_Key @timestamp
        Replace_Dots On
        Logstash_Prefix kubernetes_cluster
        Index kubernetes_cluster
        HTTP_User elastic
        HTTP_Passwd $PASSWORD
        tls On
        tls.verify Off
nodeSelector:
  kubernetes.io/os: linux
tolerations:
  - effect: NoSchedule
    operator: Exists
"@
  $customyamlFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $customyamlFile -Value $fluentbitvaluesYaml

  helm.exe --kubeconfig $kubeConfigFile repo add fluent https://fluent.github.io/helm-charts
  helm.exe --kubeconfig $kubeConfigFile install fluent-bit fluent/fluent-bit --namespace $namespace -f $customyamlFile

  
  Write-Host "waiting for fluent-bit to be ready."
  Start-Sleep -Seconds 30
  $linuxNodes = ((& kubectl.exe --kubeconfig=$kubeConfigFile get nodes -n $namespace -l kubernetes.io/os=linux -o json) | ConvertFrom-Json) 2>$null
  for($i = 0; $i -le 10; $i++) {
    $pods = ((& kubectl.exe --kubeconfig=$kubeConfigFile get pods -n $namespace -l app.kubernetes.io/name=fluent-bit -o json) | ConvertFrom-Json) 2>$null
    $runnigPodsCount = 0
    foreach ( $pod in $pods.items) {
      if ($pod.status.phase -ieq "Running") {
          $runnigPodsCount++
      }
    }
    if($runnigPodsCount -eq $linuxNodes.items.Count)
    {
      break
    }
    if($i -eq 9)
    {
      throw "fluent-bit is not in ready state"
    }
    Write-Host "waiting for fluent-bit to be ready."
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
  helm.exe --kubeconfig $kubeConfigFile delete fluent-bit --namespace $namespace
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