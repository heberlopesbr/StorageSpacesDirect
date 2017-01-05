# 1.0 - Configurar Hosts Confiaveis
set-item WSMan:\localhost\Client\TrustedHosts "*"

# 2.0 - Criar a sessão remota com o Host (Substituir o IP pelo IP do seu Host Remoto)
Enter-PSSession -ComputerName 192.168.130.206 -Credential administrator

# 3.0 - Instalar as Features de Data-Center-Bridging e Clustering 
Install-WindowsFeature -name  data-center-bridging -IncludeManagementTools
Install-WindowsFeature -name  failover-clustering -IncludeManagementTools

 
# 4.0 - Criar Politica para SMB-Direct
New-NetQosPolicy "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3
 
# 5.0 - Habilitar Controle de Fluxo para trafego SMB
Enable-NetQosFlowControl -Priority 3
 
# 6.0 - Desabilitar Controle de Fluxo para demais trafego
Disable-NetQosFlowControl -Priority 0,1,2,4,5,6,7
 
# 7.0 - Aplicar politica para a Interface 
Get-NetAdapter
Enable-NetAdapterQos -InterfaceDescription INTERNA 
 
# 8.0 - Definir SMB Direct para 50% de banda minima
New-NetQosTrafficClass "SMB" -Priority 3 -BandwidthPercentage 50 -Algorithm ETS

# 9.0 - Criar um Switch Virtual (SET)
Install-WindowsFeature -name HYPER-V -IncludeManagementTools
restart-computer -force 
New-VMSwitch -name "v SWITCH" -NetAdapterName "INTERNA" -EnableEmbeddedTeaming $true

# 10.0 - Adicionar Interface de SMB
Add-VMNetworkAdapter -SwitchName "v SWITCH" -name SMB -ManagementOS

# 11.0 - Adicionar Interface de Gerencia
Add-VMNetworkAdapter -SwitchName "v SWITCH" -name MANAGEMENT -ManagementOS


# 12.0 - Definir VLAN ID da Interface de SMB (Substituir pelo numero da VLAN configurado nas portas do seu Switch)
Set-VMNetworkAdapterVlan -VMNetworkAdapterName "SMB" -VlanId 18 -Access -ManagementOS

# 13.0 - Definir VLAN ID da Interface de Gerencia (Substituir pelo numero da VLAN configurado nas portas do seu Switch)
Set-VMNetworkAdapterVlan -VMNetworkAdapterName "MANAGEMENT" -VlanId 15 -Access -ManagementOS

# 14.0 - Reiniciar a Insterface de SMB
Get-NetAdapter
Restart-NetAdapter "vEthernet (SMB)"

# 15.0 - Reiniciar a Insterface de Gerencia
Restart-NetAdapter "vEthernet (MANAGEMENT)"

# 16.0 - Habilitar RDMA para Interface SMB 
Enable-NetAdapterRdma "vEthernet (SMB)"

# 17.0 - Configurar a afinidade entre a Interface SMB e o adaptador fisico
Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName "SMB" -ManagementOS -PhysicalNetAdapterName "INTERNA"

# 18.0 - Limpar as configurações de IP da Interface
Remove-NetIPAddress -InterfaceAlias "vEthernet (SMB)" -Confirm:$false
Remove-NetIPAddress -InterfaceAlias "vEthernet (MANAGEMENT)" -Confirm:$false

# 19.0 - Configurar IP da Interface de Gerencia (Substitua pelo IP de sua preferencia)
New-NetIPAddress -InterfaceAlias "vEthernet (MANAGEMENT)" -IPAddress 172.23.0.206 -PrefixLength 24 -DefaultGateway 172.23.0.254 -Type Unicast
Set-DnsClientServerAddress -InterfaceAlias "vEthernet (MANAGEMENT)" -ServerAddresses 172.23.0.1

# 20.0 - Configurar IP da Interface SMB (Substitua pelo IP de sua preferencia)
New-NetIPAddress -InterfaceAlias "vEthernet (SMB)" -IPAddress 172.23.3.206 -PrefixLength 24  -Type Unicast

# 21.0 - Exibir as Configurações das Interfaces
Get-VMNetworkAdapterVlan -ManagementOS

# 22.0 - Adicionar Servidor como Membro do Dominio
Add-Computer -DomainName "Digite seu FQDN do seu AD" -Credential "Dominio\administrator" -RESTART


# 23.0 - Realizar teste nos servidores que irão compor o cluster (Substitua os nomes dos Nodes pelos nomes dos seus Hosts)
Test-Cluster -node BRADC1F203, BRADC1F204, BRADC1F205, BRADC1F206 -Include "Storage Spaces Direct","Inventory", "System Configuration"

# 24.0 - Criar o cluster  (Substitua os nomes dos Nodes pelos nomes dos seus Hosts e use um IP de sua preferencia)
New-Cluster -name "CLUSTERHYPERV01" -Node BRADC1F203, BRADC1F204, BRADC1F205, BRADC1F206  -NoStorage -StaticAddress 172.23.0.221 

# 25.0 - Configurar Quorum (Cria o File Share e ajuste o comando para o endereço do seu ambiente)
Set-ClusterQuorum -nodeandfilesharemajority \\172.23.0.1\CLUSTERHYPERV01

# 26.0 - Limpar discos dos Hosts Locais para o S2D
icm (Get-Cluster -Name "CLUSTERHYPERV01" | Get-ClusterNode) {
Update-StorageProviderCache
Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
Get-StoragePool | ? IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
Get-StoragePool | ? IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
Get-Disk | ? Number -ne $null | ? IsBoot -ne $true | ? IsSystem -ne $true | ? PartitionStyle -ne RAW | % {
$_ | Set-Disk -isoffline:$false
$_ | Set-Disk -isreadonly:$false
$_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
$_ | Set-Disk -isreadonly:$true
$_ | Set-Disk -isoffline:$true
}
Get-Disk |? Number -ne $null |? IsBoot -ne $true |? IsSystem -ne $true |? PartitionStyle -eq RAW | Group -NoElement -Property FriendlyName
} | Sort -Property PsComputerName,Count

# 27.0 - Habilitar o S2D
Enable-ClusterStorageSpacesDirect -CacheState Disabled  -CimSession CLUSTERHYPERV01 -Autoconfig:0 -SkipEligibilityChecks

# 28.0 - Criar o Pool de Armazenamento usando os discos disponiveis (sata)
New-StoragePool -StorageSubSystemFriendlyName *Cluster* -FriendlyName CLUSTERHYPERV01-SP01 -ProvisioningTypeDefault Fixed -PhysicalDisks (Get-PhysicalDisk | ? CanPool -eq $true)  

# 29.0 - Criar o Storage Tier 
Get-StorageTier
New-StorageTier -StoragePoolFriendlyName "CLUSTERHYPERV01-SP01" -FriendlyName "TIER-HDD" -MediaType HDD

# 30.0 - Criar Volume e apresentar para o Cluster como CSV 
New-Volume -StoragePoolFriendlyName "CLUSTERHYPERV01-SP01" -FriendlyName "CLUSTERHYPERV01-VL01" -FileSystem CSVFS_ReFS -StorageTierFriendlyNames "TIER-HDD"-StorageTierSizes 1024GB -CimSession "CLUSTERHYPERV01"
