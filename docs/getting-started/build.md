---
icon: octicons/play-24
---

# Build the Images

## Using the Build Script

### Interactive Mode

1. Start a build by running the build script (`./build.sh`).

      This example will look for the configuration files in the `config` directory.

      ```shell
      ./build.sh
      ```

       The script displays a menu to initialize a virtual machine image build(s).

       The builds are supported by a JSON configuration file (`project.json`) that includes the details for each guest operating system.

2. Select a guest operating system.

      ```shell
      Select a guest operating system:

      1: Linux
      2: Windows

      Enter q to quit or i for info.
      ```

3. Select a distribution (or edition).

      ```shell
      Select a Linux distribution:

      1: AlmaLinux OS
      2: CentOS
      3: Debian
      4: Fedora Server
      5: Oracle Linux
      6: Red Hat Enterprise Linux
      7: Rocky Linux
      8: SUSE Linux Enterprise Server
      9: Ubuntu Server
      10: VMware Photon OS

      Enter b to go back, or q to quit.
      ```

4. Select a version.

      ```shell
      Select a version:

      1: Ubuntu Server 26.04
      2: Ubuntu Server 24.04
      3: Ubuntu Server 22.04

      Enter b to go back, or q to quit.
      ```

5. The build will start.

      ```shell
      Building a Ubuntu Server 26.04 LTS virtual machine image for VMware vSphere...

      Initializing HashiCorp Packer and required plugins...
      Starting the build of Ubuntu Server 26-04-LTS...
      vsphere-iso.linux-ubuntu: output will be in this color.
      ```

#### Demo

![](../assets/images/build.gif)


### Command-Line Mode

You can also run the build script using command-line options to specify the operating system, distribution, version, and edition, allowing for non-interactive builds. This is useful for automation or scripting purposes.

#### Examples:

- Build an Ubuntu Server 26.04 LTS image:

```shell
./build.sh --os "Linux" --dist "Ubuntu Server" --version "26.04" --auto-continue
```

???+ note "Info"
    This will start the build process for Ubuntu Server 26.04 LTS without any user prompts.

- Build a Windows Server 2022 Standard edition image:

```
./build.sh --os "Windows" --dist "Windows Server" --version "2022" --edition "Standard" --auto-continue
```

## Build Script Options

You can use the following options with the script.

| Option            | Short Form | Description                                                                                 |
| ----------------- | ---------- | ------------------------------------------------------------------------------------------- |
| `--help`          | `-h`, `-H` | Display the help message.                                                                   |
| `--deps`          | `-d`, `-D` | Check the required dependencies.                                                            |
| `--json`          | `-j`, `-J` | Specify the project file. Defaults to `project.json` next to this script.                   |
| `--os`            |            | Specify the guest operating system (e.g., `Linux`, `Windows`).                              |
| `--dist`          |            | Specify the distribution (e.g., `Ubuntu Server`, `Windows Server`).                         |
| `--version`       |            | Specify the version (e.g., `24.04`, `2025`).                                                |
| `--edition`       |            | Specify the edition for Windows (e.g., `Standard`, `Datacenter`).                           |
| `--auto-continue` |            | Build without prompts. Requires `--os`, `--dist`, `--version`, and `--edition` for Windows. |
| `--show`          | `-s`, `-S` | Display the Packer command for the build.                                                   |
| `--debug`         | `-b`, `-B` | Run Packer in debug mode.                                                                   |

The script runs Packer from the project root, so you can start it from any directory. A relative
`config_path` or `--json` path is resolved from the current directory.

With `--auto-continue`, the script never prompts:

- `--os`, `--dist`, and `--version` are required, and `--edition` is required for Windows.
- Packer runs with `-on-error=abort`, so a failed build stops instead of waiting for input.
- The script exits with the Packer exit status. It exits with `2` for an invalid option or
  selection, or a missing build directory, and with `1` for other errors.

## Build Directly with Packer

You can also start a build based on a specific source for some of the virtual machine images.

For example, if you simply want to build only Microsoft Windows Server 2022 Standard Core, run the
following:

Initialize the plugins:

```shell
packer init builds/windows/server/2022/.
```

Build the specific machine image:

```shell
packer build -force -on-error=ask \
    --only vsphere-iso.windows-server-standard-core \
    -var-file="config/build.pkrvars.hcl" \
    -var-file="config/common.pkrvars.hcl" \
    -var-file="config/vsphere.pkrvars.hcl" \
    builds/windows/server/2022
```

## Build with Environmental Variables

Use environment variables instead of providing sensitive credentials in clear-text files.

An environment variable will always take precedence over a configuration file value.

You can add the environmental variables using the `set-envvars.sh` script.

```shell
. ./set-envvars.sh
```

???+ tip "Tip"

    You must run the script as source or the shorthand "`.`" from Bash or Zsh.

- Press Enter to accept the value shown in brackets.
- Leave other prompts blank to use the value from the configuration files.
- The script prompts again when a value is not valid, such as a port outside `1`–`65535`.
- The static IP, proxy, Red Hat Subscription Manager, and SUSE Customer Center sections are only
  prompted for when you choose to configure them. Otherwise, their variables are cleared.
- Variables are only changed after every prompt is answered.
- Secrets are masked when you display the environment variables.
---

???+ note "Content Library"

    By default, the machine image artifacts are transferred to a [vSphere Content Library][vsphere-content-library]
    as an OVF template and the temporary machine image is destroyed. [^1]

    If an item of the same name exists in the target content library, Packer will update the
    existing item with the new version of OVF template.

the VMware vSphere [product documentation][vsphere-tpm] for requirements and pre-requisites. The
Microsoft Windows 11 machine image is not transferred to the content library by default. It is **not
supported** to clone an encrypted virtual machine to the content library as an OVF Template. You can
adjust the common content library settings to use VM Templates.

[//]: Links
[vsphere-tpm]: https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-4DBF65A4-4BA0-4667-9725-AE9F047DE00A.html
