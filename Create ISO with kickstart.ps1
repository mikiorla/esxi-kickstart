#Requires -Version 5.1
$ESXiHosts = @(
    @("e671-1.test.ad", "192.168.2.30"),
    @("e671-2.test.ad", "192.168.2.33"),
    @("e671-3.test.ad", "192.168.2.34"))

$remember_pathToISOFiles, $remember_esxiISOFile = $null
foreach ($esxi in $ESXiHosts) {
    $hostname = $esxi[0]
    $ip = $esxi[1]

$KS_CUSTOM = @"
### Accept the VMware End User License Agreement
vmaccepteula

### Set the root password for the DCUI and Tech Support Mode
rootpw VMware1!

### The install media (priority: local / remote / USB)
install --firstdisk --overwritevmfs

### Set the network to  on the first network adapter
network --bootproto=static --device=vmnic0 --ip=$ip --netmask=255.255.255.0 --gateway=192.168.2.1 --nameserver=192.168.2.40 --hostname=$hostname --addvmportgroup=0

### Reboot ESXi Host
#reboot --noeject # --eject doesnt exist
reboot
#Creates an init script that runs only during the first boot.
# The script has no effect on subsequent boots.
# If multiple %firstboot sections are specified,
#  they run in the order that they appear in the kickstart file.
%firstboot --interpreter=busybox
esxcli network ip dns search add --domain=test.ad
esxcli network ip set --ipv6-enabled=false
### Disable CEIP
esxcli system settings advanced set -o /UserVars/HostClientCEIPOptIn -i 2
### Enable maintaince mode
esxcli system maintenanceMode set -e true
### Reboot
esxcli system shutdown reboot -d 15 -r "rebooting after ESXi host configuration"
"@

    if (-not $remember_pathToISOFiles) {
        if (($pathToISOFiles = Read-Host "Enter ISO folder path (default e:\iso)") -eq '') { $pathToISOFiles = "e:\iso"; } else { $pathToISOFiles }
        $remember_pathToISOFiles = $pathToISOFiles
    }
    else { Write-Host -ForegroundColor Cyan "[ok] path to ISO file already choosed" }

    $pathToISOFiles = $pathToISOFiles.ToLower()

    if (-not $remember_esxiISOFile) {
        try { $esxiIsoFile = Get-ChildItem $pathToISOFiles\VMware*.iso -ErrorAction Stop }
        catch { $_.Exception; break }
        if ($esxiIsoFile -is [array]) {
            Write-host -ForegroundColor Cyan "INFO: Multiple files detected. Select one."
            $a = 1
            foreach ($item in $esxiIsoFile ) {
                Write-host "[$a] $($item.Name)" #$($item.gettype().Name) Parent:$($item.parent)"
                $a++
            }
            $select = Read-host -Prompt "Please choose number"
            while ([array](1..$a) -notcontains $select) { $select = Read-host -Prompt "Please choose number" }
            $esxiIsoFile = $esxiIsoFile.Item($select - 1)
            $remember_esxiISOFile = $esxiIsoFile
        }
    }
    else { Write-Host -ForegroundColor Cyan "[ok] esxi ISO file already choosed" }

    Write-Host -ForegroundColor Cyan "[acition] Mounting $esxiIsoFile"
    #$beforeMount = Get-Volume
    Mount-DiskImage -ImagePath $esxiIsoFile -StorageType ISO -Access ReadOnly
    # After sucefully mounting few times I have now problems mounting ISO file on Win10 Build:17134 Version: 10.0.17134, it gets stuck on mounting ... warning log in System recorded
    # Get-EventLog -LogName System -EntryType Warning -InstanceId 219 -Newest 1 | fl
    # Problems with 'MIcrosoft Virtual DVD-ROM' if you'r PC doesnt have CD drive

    #$mountedISO = Compare-Object (Get-Volume) $beforeMount | select -ExpandProperty Inputobject
    $mountedISO = Get-Volume | ? { $_.DriveType -eq "CD-ROM" -and $_.OperationalStatus -eq "OK" -and $_.DriveLetter }

    $copyDestination = $pathToISOFiles + "\tmp\" + $mountedISO.FileSystemLabel # copy destination folder name
    # to do:check if folder already exist, if yes delete or increment
    Copy-Item (Get-PSDrive $mountedISO.DriveLetter).root -Recurse -Destination $copyDestination -Force
    Write-Host -ForegroundColor Cyan "[acition] Dismount-DiskImage $esxiIsoFile"
    Dismount-DiskImage -ImagePath $esxiIsoFile

    #Get-ChildItem $copyDestination
    Get-ChildItem $copyDestination -Recurse | Set-ItemProperty -Name isReadOnly -Value $false -ErrorAction SilentlyContinue
    $bootFile = "$copyDestination\BOOT.CFG"
    $bootFileEFI = "$copyDestination\EFI\BOOT\BOOT.CFG"
    $bootFileTitle = Get-Content $bootFile | Select-String "title"
    $time = (Get-Date -f "HHmmss")
    $newBootFileContent = (Get-Content $bootFile).Replace($bootFileTitle, "title=Loading ESXi installer using kickstart file $time").Replace("kernelopt=cdromBoot runweasel", "kernelopt=cdromBoot runweasel ks=cdrom:/KS_MILAN.CFG")
    Set-Content $bootFile -Value $newBootFileContent -Force
    Set-Content $bootFileEFI -Value $newBootFileContent -Force
    New-Item -ItemType File -Path $copyDestination -Name "ks_milan.cfg" -Value ($KS_CUSTOM | Out-String)
    #code "$copyDestination\ks_milan.cfg" #review file

    $isoSourceFiles = "/mnt/" + $copyDestination.Replace("\", "/").replace(":", "")
    #$isoSourceFiles = "/mnt/d/iso/tmp/ESXI-6.7.0-20181002001-STANDARD"
    $isoDestinationFile = $hostname + ".iso"
    $isoDestinationFilePath = "/mnt/" + $pathToISOFiles.Replace("\", "/").replace(":", "") + "/tmp/" + $isoDestinationFile
    $rCommand = "genisoimage -relaxed-filenames -J -R -o $isoDestinationFilePath -b ISOLINUX.BIN -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot $isoSourceFiles"

    # sudo apt-get install genisoimage
    wsl bash -c $rCommand

    #wsl bash -c "scp $isoDestinationFilePath root@192.168.2.20:/vmfs/volumes/datastore1"
    Write-Host -ForegroundColor Cyan "[action] deleting folder $copyDestination"
    Remove-Item $copyDestination -Recurse -Force
}
