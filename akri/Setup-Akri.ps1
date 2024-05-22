# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
<#
    .PARAMETER installAkri
        installAkri boolean flag
    
    .PARAMETER uninstallAkri
        uninstallAkri boolean flag

    .PARAMETER kubeConfigFile
        clusterName Path

    .PARAMETER namespace
        namespace
#>
param (
    [Parameter()]
    [bool] $installAkri,

    [Parameter()]
    [bool] $uninstallAkri,

    [Parameter(Mandatory = $true)]
    [string] $kubeconfigFile,
        
    [Parameter(Mandatory = $true)]
    [string] $namespace
)

function Install-Akri {
    <#
    .DESCRIPTION
        Helper function to install the Akri addon on the target cluster.

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

    Write-Host "Installing Akri"
    Write-Host "Creating namespace $namespace"
    $namespacecheck = kubectl.exe --kubeconfig=$kubeConfigFile get namespace | findstr $namespace
    if ($null -eq $namespacecheck) {
        Write-Host "namespace does not exist, Creating"
        kubectl.exe --kubeconfig=$kubeConfigFile create namespace $namespace
    }
    
    helm.exe --kubeconfig $kubeConfigFile repo add akri-helm-charts https://project-akri.github.io/akri/
    helm.exe --kubeconfig $kubeConfigFile repo update 
   
    Write-Host "Installing Akri charts"
    helm.exe --kubeconfig $kubeconfigFile install $global:akriRelName akri-helm-charts/akri --set agent.full=true --namespace $namespace --debug
    
    ## Wait for akri-controller pod to be ready
    Write-Host "Waiting for Pod 'akri-controller' to be ready."
    while($true) 
    {
        $result = (Execute-KubeCtl -ignoreError -kubeconfig $kubeconfigFile -arguments $("wait --for=condition=Ready --timeout=5m -n $namespace pod -l app.kubernetes.io/name=akri-controller"))
        if ($result -ne $null)
        {
            break
        }
        Start-Sleep -Seconds 15
    }
    Write-Host "Pod 'akri-controller' is ready."
}

function Execute-KubeCtl
{
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

function Execute-Command
{
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

    if ($showOutput.IsPresent)
    {
        $result = (& $command $arguments.Split(" ") | Out-Default)
    }
    else
    {
        $result = (& $command $arguments.Split(" ") 2>&1)
    }

    $out = $result | ?{$_.gettype().Name -ine "ErrorRecord"}  # On a non-zero exit code, this may contain the error
    $outString = ($out | Out-String).ToLowerInvariant()

    if ($LASTEXITCODE)
    {
        if ($ignoreError.IsPresent)
        {
            return
        }
        $err = $result | ?{$_.gettype().Name -eq "ErrorRecord"}
        throw "$command $arguments failed to execute [$err]"
    }
    return $out
}

function Uninstall-Akri {
    <#
    .DESCRIPTION
        Helper function to Uninstall the Akri addon on the target cluster.

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

    Write-Host "Uninstalling akri release"
    Write-Host "& helm.exe --kubeconfig $kubeConfigFile uninstall $global:akriRelName"
    #helm.exe --kubeconfig $kubeConfigFile uninstall $global:akriRelName -n$namespace
    start-process -FilePath "helm.exe" -ArgumentList $("--kubeconfig $kubeConfigFile delete $global:akriRelName --namespace $namespace --debug") -Wait
    Write-Host "Akri release ""$global:akriRelName"" uninstalled"

    Write-Host "Uninstalling Akri CRDS"
    & kubectl.exe --kubeconfig=$kubeConfigFile delete crds configurations.akri.sh instances.akri.sh -n $namespace
}


$global:akriRelName = "akri"
if (($installAkri -eq $false -and $uninstallAkri -eq $false) -or ($installAkri -eq $true -and $uninstallAkri -eq $true))
{
    Write-Error "Please set either installAkri or uninstallAkri flag"
    exit
}

try {
    if ($installAkri -eq $true) {
        Install-Akri -kubeconfigFile $kubeconfigFile -namespace $namespace
    }
    elseif ($uninstallAkri -eq $true) {
        Uninstall-Akri -kubeConfigFile $kubeconfigFile -namespace $namespace
    }
    else {
        Write-Error "Unknown"
        exit
    }
}
catch [Exception] {
    Write-Error "Exception caught!!!" $_.Exception.Message.ToString()
        
}
