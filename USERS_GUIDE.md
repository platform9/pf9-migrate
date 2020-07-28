## USERS GUIDE
This guide covers installation, configuration, usage, and troubleshooting of pf9-migrate.

## SUPPORTED OPERATING SYSTEMS
This software has been tested and validated on Ubuntu 18.04.  No other operating systems are supported.

## MIGRATION OVERVIEW
The OpenStack Migration Tool supports migration of ephemeral and volume-backed instances between OpenStack clouds or between different tenants in the same cloud.  It uses Openstack CLI to perform queries and operations against the source and target clouds.  

Two (2) migration methods are supported:
1. OpenStack Native
2. Infrastructure Native

**When using OpenStack Native**, ephemeral images and Cinder volume are converted to Glance images, downloaded (to the machine running `pf9-migrate`), uploaded to the target cloud.  Each volume is then converted back (from a Glance image).  

**When using Infrastructure Native**, ephemeral images are transfered directly from the source hypervisor to the target hypervisor using SCP. For Cinder LVM configurations, the LVM backing volume (Logical Volume) for each Cinder volume is block-level copied from the source Cinder node directly to the target Cinder node using `dd` over SSH. 

## MIGRATION PROCESS
The migration process starts with discovery by invoking `pf9-discover` which discovers relevant data about the source instance such as project, image/boot-volume, attached network/IP, flavor, config drive, SSH key, availability zone, security groups, server group, and instance properties. It then performs validations (by name) on the target cloud to ensure the instance can be migrated and persists the discoverd instance data in a configuration file. If any warnings are encoundered during discover, `pf9-discover` will exit with a non-zero exit status.

The migration process continues with migration by invoking `pf9-migrate` which proceeds as follows:

#### EPHEMERAL INSTANCES
- Shutdown source instance (and lock it so only an administrator can turn it back on)
- Create server server group on target cloud
- Migrate the IP/MAC from source instance (by creating Neutron port) 
- Start instance on target cloud (from Glance image)
- Stop instance on target cloud
- Looking up the UUID for instance on target cloud
- Perform a block-level copy of ephemeral disk image (and all associated backing files) from the source hypervisor to the target hypervisor
- Perform a block-level copy of all attached volumes
- Start instance on target cloud

#### VOLUME_BACKED INSTANCES
- Shutdown source instance (and lock it so only an administrator can turn it back on)
- Create server server group on target cloud
- Create a bootable volume on the target cloud
- Perform a block-level copy of boot volume from the source Cinder node to the target Cinder node
- Perform a block-level copy of all attached volumes
- Migrate IP/MAC from source instance (by creating Neutron port)
- Start instance on target cloud

#### ALL INSTANCES
- Attach volumes
- Attach security group(s)

## MIGRATION SERVICE ACCOUNT
During migrations, `pf9-migrate` uses SSH access to all Hypervisor and Cinder nodes to facilitate data migration for ephemeral images and the LVM logical volumes that backend Cinder volumes. A service account is created on all hypervisor and Cinder nodes, and a full-mesh of SSH access is configured with sudo access to the following commands:
- lvs
- lvcreate (for creating LVM snapshots prior to data migration)
- lvremove (for removing LVM snapshots after data migration)
- dd
- scp

## INSTALLATION
To install `pf9-migrate`, perform the following steps:
- Extract the software distribution archive to a temporary directory
- From the temporary directory, run:
```
./INSTALL [-vvv]
```

The installer will create a directory in your `$HOME` directory named `pf9-migrate` and install the software in that location.

## CONFIGURATION
There are several files that comprise the configuration:
- CONFIG
- maps/az-map.dat
- maps/cinder-map.dat
- maps/hv-map.dat
- maps/project-volumeType-map.dat

### CONFIG
The configuration file (`CONFIG`) contains site-specific settings.

The following settings define the Openstack User & Project that pf9-migrate will use when performing operations against each cloud:
- `source-cloud|~/.ssh/source-cloud.rc`
- `target-cloud|~/.ssh/target-cloud.rc`

The following settings define the method for migrating data (i.e. ephemeral images and Cinder volumes):
- `instance-migration-type|rsync-qemu`
- `instance-migration-user|pf9`
- `instance-migration-group|pf9group`

The following settings define the SSH User & Key to use when accessing Hypervisors and Cinders node in the source and target clouds:
- `source-ssh-username|dyvantage`
- `source-ssh-privatekey|~/.ssh/dyv-cloudera`
- `target-ssh-username|dyvantage`
- `target-ssh-privatekey|~/.ssh/dyv-cloudera`

### maps/hv-map.dat
The Hypervisor Mapping File (`maps/hv-map.dat`) defines (potentially) node-specific settings for each KVM Hypervisor in both source and target clouds.  Each line in the file has the following format:
```
<hypervisor-nodename>|<ip-address>|<instances-path>
```

Here is an example for a Hypervisor in a Platform9 KVM Region:
```
kvm-01|172.10.1.101|/opt/pf9/data/instances
```

Here is an example for a Hypervisor in a Rackspace KVM Region:
```
kvm-01|172.10.1.201|/var/lib/nova/instances
```

NOTE: ALL Hypervisors for both source and target clouds must be included in this file.  If you see an error during migration related to mapping paths on the source or target hypervisor, it is most likely because the hypervisor is not included in this mapping file.

### maps/cinder-map.dat
The Cinder Mapping File (`maps/cinder-map.dat`) defines (potentially) node-specific settings for each Cinder node in both source and target clouds.  Each line in the file has the following format:
```
<cinder-nodename>|<ip-address>|<volume-prepend-string>|<path-to-lvm-vg>
```

Here is an example for a Cinder LVM Node in a Platform9 KVM Region:
```
f7533c4f-7259-460a-842c-6ae4e9f97955|172.10.1.51|volume-|/dev/cinder-volumes
```

Here is an example for a Cinder LVM Node in a Rackspace KVM Region:
```
cn589|172.10.1.51|volume-|/dev/lxc
```

### maps/az-map.dat
The Availability Zone Mapping File (`maps/az-map.dat`) is an exception file for mapping Availability Zones from the source cloud to the target cloud.  When an instances is migrated, the source and target AZ is assumed to be the same.  If the AZ Mapping File contains an entry for an AZ on the source cloud, the re-mapped AZ defined in the file will be used on the target cloud.

For example, if `maps/az-map.dat` contained the following lines:
```
nova|general
```

All instances in the `nova` AZ on the source cloud will placed in the `general` AZ on the target cloud.  Instances in all other AZs will be placed in the same AZ on the target cloud.

### maps/project-volumeType-map.dat
The Project-to-VolumeType Mapping File (`maps/project-volumeType-map.dat`) is mapping file used for creating Cinder volumes.  When creating a new volume, no volume type is used.  However, if an entry exists for the Project that the source instance as assigned to, the volume type mapped in the file will be used when creating the Cinder volume on the target cloud.

For example, if `maps/project-volumeType-map.dat` contained the following lines:
```
Project_1|Tier1_SSD
```

Any volumes create for instances assigned to the `Project_1` project will be created on the target cloud using a volume type of `Tier1_SSD`.

## USAGE
Migrations consist of two (2) discrete steps:
1. Discovery (of source instance)
2. Migration (of source instance to target cloud)

Step 1 creates a configuration file located in `configs/<uuid>`.  This file is read by the migration process.  If you want to change any settings before performing a migration, simply edit the config file before invoking `pf9-migrate`.

## VALIDATION
To validate that everything is working, including the openstack.rc files for both the soruce and target clouds, run the following command:
```
$ ./pf9-migrate -v
[Reading Configuration File]
[Validating OpenStack]
 --> validating OpenStack CLI is installed
 --> validating login credentials for source cloud
 --> validating login credentials for target cloud
```

### INSTANCE DISCOVERY
Here is a sample discovery of an ephemeral instance with an attached volume:
```
$ ./pf9-discover tgt01
SOURCE-CLOUD: Discovering instance: Name = tgt01
 --> instance_name = tgt01
 --> instance_uuid = a25252fa-3c29-4965-a958-b6d409fb44a3
 --> project_name/project_id = Development/bed430d2817e443eb62c4a999ba7f2c3
 --> network_name/network_uuid = srv-20/6340b11a-874b-44e4-881e-2c92df0c1b45
 --> fixed_ip/port_mac = 172.31.20.8/fa:16:3e:bf:c5:07
 --> hypervisor = srv-pmo-kvm-00
 --> instance_type = ephemeral
 --> image_name = ubuntu-18.04-server-cloudimg-amd64.img
 --> image_id = ee81f999-63a9-7251-ae03-ea8f54299fe3
 --> flavor = m1.small
 --> availability_zone = nova
 --> ssh_keyname = dyv-cloudera
 --> properties = []
 --> config_drive = [True]
 --> fixed_ip = 172.31.20.8

TARGET-CLOUD: looking up UUIDs for named resources
 --> target_network_id = 89cda127-eeab-413d-80ff-305e99ad172a
 --> flavor_id = 2
 --> target_ssh_key = dyv-cloudera
 --> target_project_id = 4c3afccafd344fc7b16c626b8dc47b94
 --> target_image_id = ee81f999-63a9-7251-ae03-ea8f54299fe3

-------------------- --------------- ------------------------------------- -------------------------------- --------------------
Instance Name        Instance Type   Image                                 Network/Fixed IP                 Security Groups
-------------------- --------------- ------------------------------------- -------------------------------- --------------------
tgt01                ephemeral       ubuntu-18.04-server-cloudimg-amd64.img srv-20/172.31.20.8               default

------------------------------------ -------------------- ---------------- -------------------- ---------- ---------------------
Volume ID                            Device Name          Bootable         Volume Type          Size-GB    Migration Time (Sec)
------------------------------------ -------------------- ---------------- -------------------- ---------- ---------------------
a5fb5038-45ae-4823-8fe4-676b4480dbbe /dev/vdb             false            null                 1          6.82

Building Config File: /home/ubuntu/pf9-migrate/configs/a25252fa-3c29-4965-a958-b6d409fb44a3
DISCOVERY COMPLETE: Execution Time: 00h:01m:02s
```

### INSTANCE MIGRATION
Here is a sample migration session:
```
$ ./pf9-migrate tgt01
#### STARTING MIGRATION: Instance Name = a25252fa-3c29-4965-a958-b6d409fb44a3

[Source Instance Prep]
 --> Power-off and Lock Source Instance

[Migrating/Remapping Server Group]
 info: no server group to migrate

[Cinder Volume Migration]
 --> Source volume: a25252fa-3c29-4965-a958-b6d409fb44a3-vdb
 --> Detaching volume from instance
 --> LV Path (source hypervisor): 172.31.19.101:/dev/cinder-volumes/volume-a5fb5038-45ae-4823-8fe4-676b4480dbbe
 --> Creating non-bootable volume on target cloud: a25252fa-3c29-4965-a958-b6d409fb44a3-vdb (size = 1)
 --> LV Path (target hypervisor): 172.31.19.102:/dev/cinder-volumes/volume-77de4b02-3e34-410e-97f2-ce615815e326
 --> Taking snapshot of LV
 --> Copying source LV to target Cinder node (migrating volume)
 --> CLEANUP: removing snapshot on source Cinder node (snapshot_name = a5fb5038-45ae-4823-8fe4-676b4480dbbe-snapshot)
     Transfer Rate: 265.96 Mbps (elapsed_time = 32.297688142 seconds)
 --> Re-attaching volume to source instance

[Reading Instance Properties]
 info: no properties to migrate

[Start Target Instance]
 --> Exception found: re-mapping Availability Zone from nova to general
 --> Migrating IP/Mac address (creating port on target cloud)
 --> target_port_uuid = a9c28c95-90d9-4b72-8046-0e22e1547ea8
 --> Starting ephemeral instance 'tgt01'
 --> target_instance_uuid = 4097f9d2-cd4e-4cc0-91ca-a82c1b083633
 --> Waiting for instance to start:..00h:00m:05s
 --> Looking up metadata for target instance

[Post-Launch Image Update]
 --> Stopping instance on target cloud...........00h:00m:57s
 --> target hypervisor = srv-pmo-kvm-02.tomchris.net
 --> image path on target: 172.31.19.102:/opt/pf9/data/instances/4097f9d2-cd4e-4cc0-91ca-a82c1b083633
 --> Looking up metadata for source cloud
 --> image path on source: 172.31.19.101:/opt/pf9/data/instances/a25252fa-3c29-4965-a958-b6d409fb44a3/disk
 --> performing direct transfer of ephemeral image, file size = 619061248 bytes
     Transfer Rate: 441.17 Mbps (elapsed_time = 11.225593301 seconds)
     Checking for backing image
     RAW backing image found
         /opt/pf9/data/instances/_base/ca231be932878ea2fc084a53821e1509f22a0a32
         Original Size: 2361393152 bytes
     Converting to qcow2:  Complete
         /tmp/migrate_ca231be932878ea2fc084a53821e1509f22a0a32
         New Image Size: 1074628 bytes
 --> performing direct transfer of backing image, file size = 1074628 bytes
     Transfer Rate: .40 Mbps (elapsed_time = 21.464516125 seconds)
 --> removing converted backing image on source hypervisor (/tmp/migrate_ca231be932878ea2fc084a53821e1509f22a0a32)
 --> Re-starting instance with updated image
 --> Waiting for instance to start
..00h:00m:03s

[Attach Additional Volumes]
 --> Attaching volume 'a25252fa-3c29-4965-a958-b6d409fb44a3-vdb' to tgt01 as device 'auto-assign'

[Attach Additional Securty Groups]
 --- no additional security groups ---

[MIGRATION COMPLETE]
 --> Total Time for migration: 00h:04m:38s
```

## TROUBLESHOOTING
All stdout and stderr for each migration is logged to logs/<uuid>.log

**HINT**: to see all underlying Openstack CLI commands used by the migration tool, run the following command:
```
grep openstack logs/<uuid>.log
```
Or run this command while a migration is running:
```
tail -f logs/<uuid>.log | grep openstack
```
