#Requires -PSEdition Desktop
#Requires -Version 5.1

function New-ISOWithKickstart {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $CopyFilesFormPath
    )
    #{ "Name":"esxi2", "ip":"ip2" },
    begin {
        #"Name":"esxi67u3-2", "ip":"10.10.10.20", "gateway":"10.10.10.1" , "dns":"10.10.10.1"
        #"Name":"esxi67u3-3", "ip":"10.10.10.30", "gateway":"10.10.10.1" , "dns":"10.10.10.1"
        $esxiHosts = '{
        "esxiHosts":[
         {"Name":"esxi67u3-2", "ip":"10.10.10.20", "gateway":"10.10.10.1" , "dns":"10.10.10.1"}
        ]
    }'

        if ( -not (Get-Module -ListAvailable Storage)) { Write-Warning "Storage module not found, cannot continue."; break }


    }

    process {

        $esxiHosts = $esxiHosts | ConvertFrom-Json #create object to work with

        #region choose ISO file
        if (-not $CopyFilesFormPath) {

            if (($pathToISOFiles = Read-Host "Enter ISO folder path (default e:\iso)") -eq '') { $pathToISOFiles = "e:\iso"; } else { $pathToISOFiles }
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
            }
            #$beforeMount = Get-Volume
            Write-Host -ForegroundColor Cyan "[action] Mounting $esxiIsoFile"
            try { Mount-DiskImage -ImagePath $esxiIsoFile -StorageType ISO -Access ReadOnly -ErrorAction Stop } catch { $_.exception; break }
            # After sucefully mounting few times I have now problems mounting ISO file on Win10 Build:17134 Version: 10.0.17134, it gets stuck on mounting ... warning log in System recorded
            # Get-EventLog -LogName System -EntryType Warning -InstanceId 219 -Newest 1 | fl
            # Problems with 'MIcrosoft Virtual DVD-ROM' if you'r PC doesnt have CD drive

            #$mountedISO = Compare-Object (Get-Volume) $beforeMount | select -ExpandProperty Inputobject
            $mountedISO = Get-Volume | ? { $_.DriveType -eq "CD-ROM" -and $_.OperationalStatus -eq "OK" -and $_.DriveLetter }

            $copyDestination = $pathToISOFiles + "\tmp\" + $mountedISO.FileSystemLabel # copy destination folder name
            # to do:check if folder already exist, if yes delete or increment
            Write-Host -ForegroundColor Cyan "[action] Copy mounted files $esxiIsoFile"
            Copy-Item (Get-PSDrive $mountedISO.DriveLetter).root -Recurse -Destination $copyDestination -Force

        }
        #endregion

        #region Copy from extracted
        else {
            try {
                $copyDestination = New-Item -ItemType Directory -Name "tmp" -Force
                $copyDestination = $copyDestination.FullName
                Write-Host -ForegroundColor Cyan "[action] Copy extracted or mounted files from $CopyFilesFormPath"
                Copy-Item "$CopyFilesFormPath\*" -Recurse -Destination $copyDestination -Force
                $pathToISOFiles = $copyDestination
            }
            catch {
                $_.Exception.Message
                break
            }


        }
        #endregion

        if (-not $CopyFilesFormPath) {
            Write-Host -ForegroundColor Cyan "[acition] Dismount-DiskImage $esxiIsoFile"
            Dismount-DiskImage -ImagePath $esxiIsoFile
        }


        Write-Host -ForegroundColor Cyan "[action] Set files as rw"
        Get-ChildItem $copyDestination -Recurse | Set-ItemProperty -Name isReadOnly -Value $false -ErrorAction SilentlyContinue

        foreach ($esxi in $ESXiHosts.esxiHosts) {
            $hostname = $esxi.Name
            $ip = $esxi.ip
            $dns = $esxi.dns
            $gw = $esxi.gateway

            $KS_CUSTOM = @"
### Accept the VMware End User License Agreement
vmaccepteula

### Set the root password for the DCUI and Tech Support Mode
rootpw VMware1!

### The install media (priority: local / remote / USB)
install --firstdisk --overwritevmfs

### Set the network to  on the first network adapter
network --bootproto=static --device=vmnic0 --ip=$ip --netmask=255.255.255.0 --gateway=$gw --nameserver=$dns --hostname=$hostname --addvmportgroup=0 --vlanid=0

### Reboot ESXi Host
#reboot --noeject # --eject doesnt exist
reboot --noeject
#Creates an init script that runs only during the first boot.
# The script has no effect on subsequent boots.
# If multiple %firstboot sections are specified,
#  they run in the order that they appear in the kickstart file.
%firstboot --interpreter=busybox
esxcli network ip dns search add --domain=hosting.matrix.ag
esxcli network ip set --ipv6-enabled=false
### Disable CEIP
esxcli system settings advanced set -o /UserVars/HostClientCEIPOptIn -i 2
### Enable maintaince mode
esxcli system maintenanceMode set -e true
### Reboot
esxcli system shutdown reboot -d 15 -r "Rebooting one more after ESXi configuration"
"@

            $bootFile = "$copyDestination\BOOT.CFG"
            $bootFileEFI = "$copyDestination\EFI\BOOT\BOOT.CFG"
            $bootFileTitle = Get-Content $bootFile | Select-String "title"
            $time = (Get-Date -f "HHmmss")
            $newBootFileContent = (Get-Content $bootFile).Replace($bootFileTitle, "title=Loading ESXi installer using kickstart file $time").Replace("kernelopt=cdromBoot runweasel", "kernelopt=cdromBoot runweasel ks=cdrom:/KS_MILAN.CFG")
            Set-Content $bootFile -Value $newBootFileContent -Force
            Set-Content $bootFileEFI -Value $newBootFileContent -Force
            if (Test-Path $copyDestination\"ks_milan.cfg") {
                #Write-Host -ForegroundColor Cyan ". kickstart file already present,seting new value"
                #Set-Content $copyDestination\"ks_milan.cfg" -Value ($KS_CUSTOM | Out-String)
                Remove-item $copyDestination\"ks_milan.cfg" -Force -Confirm:0
                Write-Host -ForegroundColor Cyan ". creating custom kickstart file"
                New-Item -ItemType File -Path $copyDestination -Name "ks_milan.cfg" -Value ($KS_CUSTOM | Out-String)
            }
            else {
                Write-Host -ForegroundColor Cyan ". creating custom kickstart file"
                New-Item -ItemType File -Path $copyDestination -Name "ks_milan.cfg" -Value ($KS_CUSTOM | Out-String)
            }

            #code "$copyDestination\ks_milan.cfg" #review file

            $isoSourceFiles = ("/mnt/" + $copyDestination.Replace("\", "/").replace(":", "")).ToLower()
            Write-host -Foreg Yellow "isoSourceFiles " -NoNewline; write-host $isoSourceFiles
            $isoDestinationFile = "$hostname.iso".ToLower()
            $isoDestinationFilePath = ("/mnt/" + (Get-Location).path.Replace("\", "/").replace(":", "") + "/" + $isoDestinationFile).ToLower()
            #$isoDestinationFilePath = "/mnt/" + $pathToISOFiles.Replace("\", "/").replace(":", "") + "/tmp/" + $isoDestinationFile
            Write-host -fore Yellow "isoDestinationFilePath " -NoNewline; Write-Host $isoDestinationFilePath
            $rCommand = "genisoimage -relaxed-filenames -J -R -o $isoDestinationFilePath -b ISOLINUX.BIN -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot $isoSourceFiles"

            # sudo apt-get install genisoimage
            wsl bash -c $rCommand

            #wsl bash -c "scp $isoDestinationFilePath root@192.168.2.20:/vmfs/volumes/datastore1"
        }

        Write-Host -ForegroundColor Cyan "[action] deleting folder $copyDestination"
        Remove-Item $copyDestination -Recurse -Force
    }

    end {
    }
}























