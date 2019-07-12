# esxi-kickstart
Powershell to create bootable ISO image with custom kickstart file included.

It uses <a href="https://docs.microsoft.com/en-us/windows/wsl/install-win10"> WSL2 </a> Ubuntu 18.04.2 LTS for <b> genisoimage </b> command.<a href="https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.esxi.install.doc/GUID-C03EADEA-A192-4AB4-9B71-9256A9CB1F9C.html?hWord=N4IghgNiBcIOYFMB2BLAzgexQWzIkAvkA"> Checkout </a> genisoimage syntax on VMware site. 

Installation and Upgrade Script commands <a href="https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.esxi.upgrade.doc/GUID-61A14EBB-5CF3-43EE-87EF-DB8EC6D83698.html"> checkout </a> on VMware site.

Hostname and IP that will be included in kickstart need to be customized (also other options like gateway or subnetmask can be included).

Kickstart options are definied in multiline string variable KS_CUSTOM.




