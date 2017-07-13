# smmtestbuildscript
A script for building the system from Testing SMM with QEMU, KVM and libvirt based on the guide from the Tiano Core EDK2 wiki with Fedora 26 "https://github.com/tianocore/tianocore.github.io/wiki/Testing-SMM-with-QEMU,-KVM-and-libvirt" and can be seen below.

NOTE: Some things might have changed in EDK2 since the original was written, so this script varies in some areas from the guide. Please update the fresh install, and copy the Fedora 26 ISO file to /var/lib/libvirt/images/ before running this script. This script does not support the Windows sections of Lazslo's guide.







# GUIDE:
     Guide: This is a copy of the Tianocore EDK2 wiki
     
     This article describes an example setup for testing the edk2 SMM driver stack

This article describes an example setup for testing the edk2 SMM driver stack as it is built into OVMF, on QEMU/KVM, managed by libvirt. The setup uses hardware virtualization (KVM) and requires a Linux host machine.

We assume that the host machine is dedicated to the above kind of testing (i.e., it is not a general purpose / interactive workstation or desktop computer); we'll be using the root user. It's also assumed that the host is in a protected internal network and not exposed on the public internet.

The examples below will use Fedora, for both host and (one) guest operating system; feel free to use any other Linux distribution that you like.
Hardware requirements

Please use an x86_64 machine with at least 4 logical processors (quad core with HT disabled, or dual core with HT enabled). The machine should have at least 8GB of RAM, and support Intel hardware virtualization (VT-x).

For now, EPT support is also required.

(In the longer term, SMM emulation in KVM should work without EPT. RHBZ#1348092 tracks this issue.)

Commands for verifying the host CPU features will be provided in the next section.

(There's no reason why an AMD host wouldn't be appropriate; this article assumes an Intel host only because such seem to be more widely available.)

Regarding disk space, a few hundred GB should be plenty. An SSD is strongly recommended.
Install the host operating system

Obtain the Live installation image for Fedora 26 Workstation (direct link), and boot it.

Before starting the installation, select Try Fedora on the GUI, open a terminal in the Live environment, and verify that the hardware requirements are satisfied. All of the following commands should return nonzero line counts (the actual counts should match the number of logical processors on your host):

grep -c -w vmx /proc/cpuinfo
grep -c -w ept /proc/cpuinfo

Furthermore, for performance reasons, a virtualization host is recommended (but not required) where the following command outputs Y:

cat /sys/module/kvm_intel/parameters/unrestricted_guest

Proceed with the installation. For help, please refer to the Installation Guide.

In general, stick with the defaults. On the Configuration and Installation Progress screen, do not create a non-root user, only set the root password.
Perform an initial system update

Although this step is mentioned in the Installation Guide under Common Post-installation Tasks, it is worth mentioning here.

After booting the installed host OS, switch to a character console with Ctrl+Alt+F2, log in as root, install any available updates, and reboot:

dnf --refresh upgrade
reboot

Remote access

After the installation and the initial system update, it is more convenient to access the virtualization host remotely.

    Users on Linux desktops can run virsh and virt-manager locally, and implicitly connect to the remote libvirt daemon over SSH.

    For Windows users, it is recommended to set up a local X server, and an SSH client for forwarding X11 traffic. A succinct guide can be found here.

    This is an optional step, not a requirement. However, without it, there's no easy way to bring the default virtual machine management GUI, virt-manager, from the Linux virtualization host to one's familiar Windows productivity environment.

For both options above, the SSH daemon should be enabled and started on the virtualization host. Log in as root on the GUI (if necessary, click the Not listed? label on the login screen, and enter root plus the appropriate password). Open a terminal, and run the following commands:

systemctl enable sshd
systemctl start sshd

If the second option (X11 forwarding) is selected, then the following command is necessary as well:

dnf install xorg-x11-xauth

These are the last actions that, in the optimal case, should be performed with direct physical access to the virtualization host.
Install QEMU and libvirt

In this step no low-level system components are installed, therefore it's enough to log in to the virtualization host via SSH. Run the following commands:

dnf group install --with-optional virtualization

systemctl enable libvirtd
systemctl start libvirtd

systemctl enable virtlogd
systemctl start virtlogd

Enable nested virtualization

In this article, we have no use for nested virtualization, except as a somewhat obscure test case (described below) for edk2's EFI_PEI_MP_SERVICES_PPI implementation (which lives in UefiCpuPkg/CpuMpPei and UefiCpuPkg/Library/MpInitLib). Given that multiprocessing is a primary building block for the most important SMM driver in edk2 (UefiCpuPkg/PiSmmCpuDxeSmm), it makes sense to test multiprocessing with a less demanding exercise as well.

Enabling nested virtualization in KVM, on the host, is ultimately one possible trigger for OVMF to program the MSR_IA32_FEATURE_CONTROL register of all VCPUs in parallel, exposing VT-x to the guest OS. (Please see the RFE for details.) For this, OVMF uses EFI_PEI_MP_SERVICES_PPI.

Permanently enable nested virtualization with the following commands:

sed --regexp-extended --in-place=.bak \
  --expression='s,^#(options kvm_intel nested=1)$,\1,' \
  /etc/modprobe.d/kvm.conf

rmmod kvm_intel
modprobe kvm_intel

Verify the setting -- the following command should print Y:

cat /sys/module/kvm_intel/parameters/nested

Install OVMF from source

    Install build dependencies:

    dnf install gcc-c++ nasm libuuid-devel acpica-tools

    Clone the upstream edk2 repository:

    EDK2_SOURCE=$HOME/edk2
    git clone https://github.com/tianocore/edk2.git $EDK2_SOURCE

    Download and embed OpenSSL into the edk2 source tree as instructed in the $EDK2_SOURCE/CryptoPkg/Library/OpensslLib/OpenSSL-HOWTO.txt file.

    At the time of this writing (2017-Jul-12), upstream edk2 still uses OpenSSL version 1.1.0e, although the OpenSSL project has released 1.1.0f meanwhile (on 2017-May-25). Therefore, the commands from OpenSSL-HOWTO.txt can currently be condensed like written below -- please double-check the sanctioned version in OpenSSL-HOWTO.txt first, and update the OPENSSL_VER assignment below as necessary:

    OPENSSL_VER=openssl-1.1.0e

    wget -q -O - http://www.openssl.org/source/${OPENSSL_VER}.tar.gz \
    | tar -C $EDK2_SOURCE/CryptoPkg/Library/OpensslLib -x -z

    ln -s ${OPENSSL_VER} $EDK2_SOURCE/CryptoPkg/Library/OpensslLib/openssl

    Build OVMF:

    cd $EDK2_SOURCE
    source edksetup.sh
    make -C "$EDK_TOOLS_PATH"

    build -a IA32 -a X64 -p OvmfPkg/OvmfPkgIa32X64.dsc \
      -D SMM_REQUIRE -D SECURE_BOOT_ENABLE \
      -D HTTP_BOOT_ENABLE -D TLS_ENABLE \
      -t GCC5 \
      -b NOOPT \
      -n $(getconf _NPROCESSORS_ONLN)

    build -a IA32 -p OvmfPkg/OvmfPkgIa32.dsc \
      -D SMM_REQUIRE -D SECURE_BOOT_ENABLE \
      -D HTTP_BOOT_ENABLE -D TLS_ENABLE \
      -t GCC5 \
      -b NOOPT \
      -n $(getconf _NPROCESSORS_ONLN)

        We build the Ia32 (32-bit PEI and DXE) and Ia32X64 (32-bit PEI, 64-bit DXE) OVMF platforms because they support ACPI S3 suspend/resume and SMM at the same time. S3 is a demanding use case for the SMM infrastructure, therefore we should enable this combination.

        The X64 build of OVMF does not support the same yet (UefiCpuPkg/Universal/Acpi/S3Resume2Pei forces OVMF to choose between S3 and SMM). Thankfully, the PEI bitness is entirely irrelevant to guest OSes, thus the Ia32X64 platform can be used identically, as far as OS-facing functionality is concerned.

        The Ia32 platform has more readily exposed instabilities in the edk2 SMM driver stack (as built into OVMF and run on QEMU), historically, than the Ia32X64 platform. Therefore it makes sense to build Ia32 too.

        32-bit UEFI OSes are not covered in the current version of this article (2017-Jul-12).

    Install OVMF (the split firmware binaries and variable store template):

    OVMF_INSTALL=/opt/edk2/share/ovmf-smm

    mkdir -p -v $OVMF_INSTALL

    install -m 0644 -v \
      ${EDK2_SOURCE}/Build/Ovmf3264/NOOPT_GCC5/FV/OVMF_CODE.fd \
      ${OVMF_INSTALL}/OVMF_CODE.3264.fd

    install -m 0644 -v \
      ${EDK2_SOURCE}/Build/Ovmf3264/NOOPT_GCC5/FV/OVMF_VARS.fd \
      ${OVMF_INSTALL}/OVMF_VARS.fd

    install -m 0644 -v \
      ${EDK2_SOURCE}/Build/OvmfIa32/NOOPT_GCC5/FV/OVMF_CODE.fd \
      ${OVMF_INSTALL}/OVMF_CODE.32.fd

    chcon -v --reference=/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd \
      ${OVMF_INSTALL}/*.fd

        In the last step, we copy the SELinux context from one of the Fedora-provided OVMF files to our manually built files, so that the latter too can be used with libvirt. (Fedora's own OVMF binaries are perfectly usable for end-users, it's just that the target audience of this article is people interested in edk2 development and analysis.)

Create disk images for the virtual machines

In this section, we create two disk images (one for a Fedora 26 guest, another for a Windows 10 guest). We also place a number of ISO images in the right place, so that we can install the guests from zero.
Fedora 26

    Copy or move the image file Fedora-Workstation-Live-x86_64-26-1.5.iso, which we also used for installing the virtualization host, to the directory /var/lib/libvirt/images/.

    Create an empty disk for the guest:

    qemu-img create -f qcow2 \
      -o compat=1.1 -o cluster_size=65536 \
      -o preallocation=metadata -o lazy_refcounts=on \
      /var/lib/libvirt/images/ovmf.fedora.q35.img 100G

    The image file will have a nominal 100GB size, but it will only consume as much disk space on the host as necessary. In addition, whenever the fstrim utility is executed in the guest, unused space will be returned to the host.

Windows 10

    Download en_windows_10_enterprise_2015_ltsb_n_x64_dvd_6848316.iso from MSDN, and place it under /var/lib/libvirt/images/.

    Create an empty disk for the guest, similarly to the Fedora 26 command:

    qemu-img create -f qcow2 \
      -o compat=1.1 -o cluster_size=65536 \
      -o preallocation=metadata -o lazy_refcounts=on \
      /var/lib/libvirt/images/ovmf.win10.q35.img 100G

    When installing the Windows 10 guest, we'll need the VirtIO drivers. The following instructions have been distilled from the Fedora Project Wiki:

    wget -O /etc/yum.repos.d/virtio-win.repo \
      https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo

    dnf install virtio-win

    The ISO image with the drivers becomes available through the /usr/share/virtio-win/virtio-win.iso symlink.

Install the Fedora 26 guest
Libvirt domain definition (Fedora 26 guest)

Download the file ovmf.fedora.q35.template to the virtualization host, and define the guest from it:

virsh define ovmf.fedora.q35.template

After this step, the template file can be deleted.

Note that the template hard-codes a number of pathnames from the above sections. If you changed any of those pathnames, please update the template file accordingly, before running the virsh define command above. (Most of the defined domain's characteristics can be edited later as well, with virsh edit or virt-manager.)

This domain configuration can be used for both installing the guest and booting the installed guest.

