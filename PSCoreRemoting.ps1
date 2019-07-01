<#

sudo apt-get install genisoimage

#>



$ESXiHosts = @(("esxi1", "10.20.30.10"), ("esxi2", "10.20.30.20"))
foreach ($esxi in $ESXiHosts) {
    $hostName = $esxi[0]
    $hostIp = $esxi[1]
}
#new-pssession
$c7Session = New-PSSession -HostName 10.20.30.100 -UserName root -KeyFilePath C:\Users\morlovic\.ssh\c7droot

#mount ISO and copy to Linux machine

#edit custom ks and copy to linux location

#foreach esxi command
$pathIsoFilesToExport = "/home/iso2export/tmp"
$pathKsFile = "/home/iso2export/tmp/ks_milan.cfg"
$thingsToChangeInKs = "network --bootproto=static --device=vmnic0 --ip=$hostIp --netmask=255.255.255.0 --gateway=10.20.30.1 --nameserver=10.20.30.100 --hostname=$hostName --addvmportgroup=0"

Invoke-Command -Session $c7Session -ScriptBlock { ls -l $using:pathKsFile }
Invoke-Command -Session $c7Session -ScriptBlock { cat $using:pathKsFile }


#edit ks file respectively
"genisoimage -relaxed-filenames -J -R -o /home/custom_esxi_test.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot /home/iso2export/tmp"
$rCommand = { genisoimage -relaxed-filenames -J -R -o /home/custom_esxi_$using:hostName.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e efiboot.img -no-emul-boot $using:pathIsoFilesToExport }
Invoke-Command -Session $c7Session -ScriptBlock $rCommand



Enter-PSSession $c7Sessionls



