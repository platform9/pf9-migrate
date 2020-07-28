# RELEASE NOTES
OpenStack Migration Tool v0.4.3

# UPDATES FOR THIS RELEASE
1. This is a documentation-only release.

# KNOWN ISSUES
1. Prior to migration, the source instance and shutdown and locked. Only an administrator can unlock and boot the source isntance once it is migrated.
2. Since implementing Server Group migration (in v0.2), the `source-cloud.rc` and `target-cloud.rc` files must be mapped to the same project.

# UPDATES (FROM PREVIOUS RELEASES)
1. Added a '-h <hypervisor>' flag to `pf9-migrate` for specifying the target hypervisor to place the migrated instance on.
2. Added code to cleanup temporary resources created during the migration process, specifically snapshots of LVM volumes and coverted/compressed ephemeral disk images.
3. Added code to resolve race condition when discovering target hypervisor in the event of Scheduler failures, i.e. multiple attempts to launch instance and an alternate hypervisor is attempted.
4. Fixed bugs when looking up server group metadata during migration.
5. Added migration of SSH keys.  If no SSH key is discovered on the source instance, the default key (`techops-official`) will be used.

NOTE: The default SSH key is currently set in `globals` (variable name = `ssh_default_key`).

For example, to change the default SSH key, edit `globals` and change the following line:

```
: "${ssh_default_key='techops-official'}"
```

# INSTALLATION
The installer installs all dependencies (most notably OpenStack CLI) and creates a Python virtual environment from which to run the tool.

To install, run the following command (after extracting the distribution archive):
```
./INSTALL
```

# UPGRADE PROCESS
Use the following procedure to perform an upgrade:
- Extract the software distribution archive to a temporary directory
- From the temporary directory, run:
```
./INSTALL --upgrade
```

This procedure will update the installation located ~/pf9-migrate.  It will not change the configuration file located in ~/pf9-migrate/CONFIG.

# USAGE
For configuration and usage details, see [USERS_GUIDE.md](USERS_GUIDE.md)
