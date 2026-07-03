VMware vCenter Server Appliance 8.0.1 OVF Deployment Fix
Issue
During a fresh deployment of VMware vCenter Server Appliance (VCSA)
8.0.1, Stage 2 of the installation fails at approximately 69% with
errors similar to:
`Install-parameter upgrade.import.directory not set`
`vlcm` service fails to start
`/etc/vmware-vlcm/vlcm_db/vlcm.properties` is missing
Solution
Convert the VCSA OVA into an OVF using OVFTool.
Delete the original `.mf` (manifest) file.
Edit the generated `.ovf` file.
Locate the following property:
``` xml
<Property
    ovf:key="guestinfo.cis.upgrade.import.directory"
    ovf:type="string"
    ovf:userConfigurable="false"
```
Change:
``` xml
ovf:userConfigurable="false"
```
to:
``` xml
ovf:userConfigurable="true"
```
Save the OVF.
Deploy the modified `.ovf` instead of the original `.ova`.
Continue with the VCSA installation. Stage 2 should complete
successfully.
---
Example Environment
    E:\vmware\
    │
    ├── VMware-VCSA-all-8.0.1-21560480.iso
    ├── vcsa\
    │   ├── VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ova
    │   └── ovftool\
    │       └── win32\
    │           └── ovftool.exe

---
Convert OVA to OVF
Open Command Prompt and navigate to the OVFTool directory.
``` cmd
cd E:\vmware\vcsa\ovftool\win32
```
Run:
``` cmd
ovftool.exe ^
E:\vmware\vcsa\VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ova ^
E:\vmware\VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ovf
```
Expected output:
``` text
Opening OVA source...
The manifest validates
Transfer Completed
Completed successfully
```
---
Delete Manifest File
Delete the original manifest file:
    *.mf

This prevents OVF validation failures after modifying the OVF.
---
Edit the OVF
Search for:
``` xml
<Property
    ovf:key="guestinfo.cis.upgrade.import.directory"
```
Change:
``` xml
ovf:userConfigurable="false"
```
to:
``` xml
ovf:userConfigurable="true"
```
Save the file.
---
Deploy
Deploy the modified OVF using Deploy OVF Template.
Proceed with the normal VCSA Stage 1 and Stage 2 installation.
---
Result
The installation should proceed beyond the previous failure point
(~69%), allowing:
Successful Stage 2 completion
`vlcm` service initialization
Creation of `/etc/vmware-vlcm/vlcm_db/vlcm.properties`
Successful VCSA deployment
---
Notes
This workaround was validated with:
VMware vCenter Server Appliance 8.0.1
Build 21560480
The issue occurs when deploying the original OVA directly in certain
environments and causes the Lifecycle Manager (vLCM) initialization
to fail during first boot.
