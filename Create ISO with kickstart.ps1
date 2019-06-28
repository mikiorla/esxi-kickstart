$ESXiHosts = @(("e671-1.test.ad", "192.168.2.30"), ("e671-2.test.ad", "192.168.2.33"), ("e671-3.test.ad", "192.168.2.34"))
foreach ($esxi in $ESXiHosts) {
    $hostname = $esxi[0]
    $ip = $esxi[1]
}

$ip = "192.168.2.30"
$hostname = "e671-1.test.ad"
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

#$esxiIsoFile = Get-ChildItem D:\iso | Out-GridView -Title "Choose ISO to mount" -PassThru
$esxiIsoFile = "D:\iso\VMware-VMvisor-Installer-6.7.0.update01-10302608.x86_64.iso"

#add menu for chosing iso
#$beforeMount = Get-Volume
Mount-DiskImage -ImagePath $esxiIsoFile -StorageType ISO -Access ReadOnly
#$sourceFIles
#$mountedISO = Compare-Object (Get-Volume) $beforeMount | select -ExpandProperty Inputobject
$mountedISO = Get-Volume | ? { $_.DriveType -eq "CD-ROM" -and $_.OperationalStatus -eq "OK" -and $_.DriveLetter }

$copyDestination = "d:\iso\tmp\" + $mountedISO.FileSystemLabel
Copy-Item (Get-PSDrive $mountedISO.DriveLetter).root -Recurse -Destination $copyDestination -Force
Dismount-DiskImage -ImagePath $esxiIsoFile

Get-ChildItem $copyDestination
Get-ChildItem $copyDestination -Recurse | Set-ItemProperty -Name isReadOnly -Value $false -ErrorAction SilentlyContinue
$bootFile = "$copyDestination\BOOT.CFG"
$bootFileTitle = Get-Content $bootFile | Select-String "title"
$time = (Get-Date -f "HHmmss")
$newBootFileContent = (Get-Content $bootFile).Replace($bootFileTitle,"title=Loading ESXi installer using kickstart file $time").Replace("kernelopt=cdromBoot runweasel", "kernelopt=cdromBoot runweasel ks=cdrom:/KS_MILAN.CFG")
Set-Content $bootFile -Value $newBootFileContent -Force
New-Item -ItemType File -Path $copyDestination -Name "ks_milan.cfg" -Value ($KS_CUSTOM | Out-String)
code "$copyDestination\ks_milan.cfg"

$isoSourceFiles = "/mnt/" + $copyDestination.Replace("\", "/").replace(":", "")
#$isoSourceFiles = "/mnt/d/iso/tmp/ESXI-6.7.0-20181002001-STANDARD"

$isoDestinationFile = "/mnt/d/iso/tmp/"+$hostname+".iso"
$rCommand = "genisoimage -relaxed-filenames -J -R -o $isoDestinationFile -b ISOLINUX.BIN -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot $isoSourceFiles"

# sudo apt-get install genisoimage
wsl bash -c $rCommand
#wsl bash -c "scp $isoDestinationFile root@192.168.2.20:/vmfs/volumes/datastore1/" #VMware1!

Get-Item $isoDestinationFile

#region ...with PSCore Remoting
#new-pssession
$c7Session = New-PSSession -HostName 10.20.30.100 -UserName root -KeyFilePath C:\Users\morlovic\.ssh\c7droot

#foreach esxi command
$pathIsoFilesToExport = "/home/iso2export/tmp"
$pathKsFile = "/home/iso2export/tmp/ks_milan.cfg"

Invoke-Command -Session $c7Session -ScriptBlock { ls -l $using:pathKsFile }
Invoke-Command -Session $c7Session -ScriptBlock { cat $using:pathKsFile }

#edit ks file respectively

$rCommand = { genisoimage -relaxed-filenames -J -R -o /home/custom_esxi_$using:hostName.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot $using:pathIsoFilesToExport }
Invoke-Command -Session $c7Session -ScriptBlock $rCommand

wsl bash -c "lsb_release -a"
#endregion