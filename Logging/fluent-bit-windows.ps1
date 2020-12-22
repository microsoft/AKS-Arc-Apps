# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
<#
    .PARAMETER installWindowsLogging
        installWindowsLogging boolean flag
    
    .PARAMETER uninstallWindowsLogging
        uninstallWindowsLogging boolean flag

    .PARAMETER kubeConfigFile
        clusterName Path

    .PARAMETER namespace
        namespace

    .PARAMETER fluent_bit_docker_image_name
        fluent-bit-docker-image-name

    .PARAMETER fluent_bit_docker_image_pull_secret
        fluent_bit_docker_image_pull_secret
#>
param (
  [Parameter()]
  [bool] $installWindowsLogging,

  [Parameter()]
  [bool] $uninstallWindowsLogging,

  [Parameter(Mandatory = $true)]
  [string] $kubeconfigFile,

  [Parameter(Mandatory = $true)]
  [string] $namespace,

  [Parameter(Mandatory = $true)]
  [string] $fluent_bit_docker_image_name,

  [Parameter(Mandatory = $false)]
  [string] $fluent_bit_docker_image_pull_secret
)

function Install-Windows-Logging {
    param (
        [Parameter(Mandatory = $true)]
        [string] $kubeconfigFile,
      
        [Parameter(Mandatory = $true)]
        [string] $namespace,
      
        [Parameter(Mandatory = $true)]
        [string] $fluent_bit_docker_image_name,
      
        [Parameter(Mandatory = $false)]
        [string] $fluent_bit_docker_image_pull_secret
    )
  
    Write-Host "Creating Config Map"
    $PASSWORD=$(kubectl.exe --kubeconfig=$kubeConfigFile get secret elastic-cluster-es-elastic-user --namespace $namespace -o go-template='{{.data.elastic | base64decode}}')

  $fluentbitconfigMapYaml=@"
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name:         fluent-bit-windows
    namespace:    $namespace
  
  data:
    parsers.conf: |
      [PARSER]
          Name docker
          Format json
          Time_Keep On
          Time_Key time
          Time_Format %Y-%m-%dT%H:%M:%S.%L
      
    fluent-bit.conf: |
      [SERVICE]
          Flush 1
          Daemon Off
          Log_Level Info
          Parsers_File parsers.conf
          HTTP_Server On
          HTTP_Listen 0.0.0.0
          HTTP_Port 2020

      [INPUT]
          Name tail
          Path C:\var\log\containers\*.log
          Parser docker
          Tag kube.*
          Mem_Buf_Limit 5MB
          Skip_Long_Lines On

      [FILTER]
          Name kubernetes
          Match kube.*
          Kube_URL https://kubernetes.default.svc.cluster.local:443
          Kube_CA_File C:\var\run\secrets\kubernetes.io\serviceaccount\ca.crt
          Kube_Token_File C:\var\run\secrets\kubernetes.io\serviceaccount\token
          Kube_Tag_Prefix kube
          Merge_Log On
          Keep_Log Off
          K8S-Logging.Parser On
          K8S-Logging.Exclude On
  
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
          tls.debug 3
"@

  $cmFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
  Set-Content -Path $cmFile -Value $fluentbitconfigMapYaml
  kubectl.exe --kubeconfig=$kubeConfigFile apply -f $cmFile
  rm $cmFile

  $fluent_bit_ds=@"
  apiVersion: apps/v1
  kind: DaemonSet
  metadata:
    name: fluent-bit-windows
    namespace: $namespace
    labels:
      app: fluent-bit-windows
    
  spec:
    selector:
      matchLabels:
        app: fluent-bit-windows
    template:
      metadata:
        labels:
          app: fluent-bit-windows
      spec:
        imagePullSecrets:
        - name: $fluent_bit_docker_image_pull_secret
        containers:
        - name: fluent-bit-windows
          image: $fluent_bit_docker_image_name
          imagePullPolicy: Always
          ports:
            - containerPort: 2020
          volumeMounts:
          - name: varlog
            mountPath: /var/log
          - name: varlibdockercontainers
            mountPath: /ProgramData/docker/containers
            readOnly: true
          - name: fluent-bit-config
            mountPath: /fluent-bit/etc/
        terminationGracePeriodSeconds: 10
        volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdockercontainers
          hostPath:
            path: /ProgramData/docker/containers
        - name: fluent-bit-config
          configMap:
            name: fluent-bit-windows
        serviceAccountName: fluent-bit
        nodeSelector:
          kubernetes.io/os: windows
"@
 
$dsFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'yaml' } -PassThru
Set-Content -Path $dsFile -Value $fluent_bit_ds
kubectl.exe --kubeconfig=$kubeConfigFile apply -f $dsFile
rm $dsFile

}

function Uninstall-Windows-Logging {
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
  
    Write-Host "Uninstalling windows logging"
    kubectl.exe --kubeconfig=$kubeConfigFile delete ds fluent-bit-windows --namespace $namespace 
    kubectl.exe --kubeconfig=$kubeConfigFile delete cm fluent-bit-windows --namespace $namespace 
}

if (($installWindowsLogging -eq $false -and $uninstallWindowsLogging -eq $false) -or ($installWindowsLogging -eq $true -and $uninstallWindowsLogging -eq $true)) {
    Write-Error "Please set either installWindowsLogging or uninstallWindowsLogging flag"
    exit
  }
try {
    if ($installWindowsLogging -eq $true) {
          
      Install-Windows-Logging -kubeconfigFile $kubeconfigFile -namespace $namespace -fluent_bit_docker_image_name $fluent_bit_docker_image_name -fluent_bit_docker_image_pull_secret $fluent_bit_docker_image_pull_secret
    }
    elseif ($uninstallWindowsLogging -eq $true) {
      Uninstall-Windows-Logging -kubeConfigFile $kubeconfigFile -namespace $namespace
    }
    else {
      Write-Error "Unknown"
      exit
    }
  }
  catch [Exception] {
    Write-Error "Exception caught!!!" $_.Exception.Message.ToString()
          
  }