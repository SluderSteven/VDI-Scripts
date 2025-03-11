# Description: This script will connect to Horizon View Connection Servers, retrieve the base image information for each pool, and post the information to a Microsoft Teams channel.
# I needed this to keep an eye peeled for folks who were updating their base images and not updating the pools.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Get-Module -ListAvailable VMware.VimAutomation.HorizonView, Vmware.Hv.Helper | Import-Module -ErrorAction SilentlyContinue -InformationAction SilentlyContinue -WarningAction SilentlyContinue
$Credentials = Import-Clixml -Path D:\Scripts\HVCredentials.xml
$Sites = @('HVSite01', 'HVSite02')
ForEach ($Site in $Sites) {
    $ImageTable = New-Object 'System.Collections.Generic.List[System.Object]'
    $ImagePostTable = New-Object 'System.Collections.Generic.List[System.Object]'
    $HvServer1 = Connect-HVServer -Server $Site -Credential $Credentials
    $ViewAPI = $HVServer1.ExtensionData
    if ($null -eq $ViewAPI) {
        Write-Error "Could not retrieve ViewApi services from connection object. Make sure you're connected via Connect-HVServer"
        break
    }
    if (($global:DefaultHVServers.name) -like "*01") {
        $VDISite = "HVSite01"
        $uri = "HVSITE01_WEBHOOKURI"
    } 
    elseif (($global:DefaultHVServers.name) -like "*02") {
        $VDISite = "HVSite02"
        $uri = "HVSITE02_WEBHOOKURI"
    }
    $AllPools = Get-HVPool
    ForEach ($Pool in $AllPools) {
        $item = Get-HVPool -PoolName $Pool.Base.Name
        $ImageObj = [PSCustomObject]@{
            'Pool Name'         = $item.Base.Name
            'Current Parent VM' = $item.AutomatedDesktopData.VirtualCenterNamesData.ParentVMPath.substring(($pool.AutomatedDesktopData.VirtualCenterNamesData.ParentVMPath.LastIndexOf("/") + 1))
            'Current Snapshot'  = $item.AutomatedDesktopData.VirtualCenterNamesData.SnapshotPath.substring(($pool.AutomatedDesktopData.VirtualCenterNamesData.SnapshotPath.LastIndexOf("/") + 1))
            'Parent VM Paths'   = $item.AutomatedDesktopData.VirtualCenterNamesData.ParentVMPath
            'Snapshot Paths'    = $item.AutomatedDesktopData.VirtualCenterNamesData.SnapshotPath
            'Full Path'         = $item.AutomatedDesktopData.VirtualCenterNamesData.ParentVmPath + $Pool.AutomatedDesktopData.VirtualCenterNamesData.SnapshotPath
        }
        $ImageTable.Add($ImageObj)
    }
    $ImageTable | Sort-Object -Property 'Pool Name' | ForEach-Object {
        $activityTitle = "<strong><Font Size=3>Pool: </font><font size=4 color=lightgreen>$($_.'Pool Name')</font></strong>"
        $ParentImageSection = @{
            activityTitle    = "$activityTitle"
            activitySubtitle = ""
            activityText     = "<ul><li><Font size=3>Current Parent VM: </font><strong><font size=3 color=lightblue>$($_.'Current Parent VM')</font></strong></li>
    <li><Font size=3>Current Snapshot: </font><strong><font size=3 color=lightgreen>$($_.'Current Snapshot')</font></strong></li>
    <li><Font size=2>Parent VM Path: </font><strong><font size=2 color=lightblue>$($_.'Parent VM Paths')</font></strong></li>
    <li><Font size=2>Snapshot Path: </font><strong><font size=2 color=lightgreen>$($_.'Snapshot Paths')</font></strong></li>
    <li><Font size=2>Full Path: </font><strong><font size=2 color=lightblue>$($_.'Full Path')</font></strong></li></ul>"
        }
        $ImagePostTable.add($ParentImageSection)
    }
    #Convert to JSON payload
    $imagebody = ConvertTo-Json @{
        title    = 'VDI Base Images'
        type     = 'MessageCard'
        text     = "<Font size=4>Site:</font> <Font size=4><strong> $($VDISite)</font></strong>"
        sections = $ImagePostTable
    }
    #Post output to Teams
    Invoke-RestMethod -Uri $uri -Method Post -Body $imagebody -ContentType 'application/json' -WarningAction SilentlyContinue -InformationAction SilentlyContinue -ErrorAction SilentlyContinue; 
    while ($global:DefaultHVServers.count -gt "0") { Disconnect-HVServer -Server * -Force -Confirm:$false }
}
