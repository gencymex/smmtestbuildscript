#!/bin/bash
#This script will install pre-requisites and enable secure remote connection, do not forget to grab you SSH keys to access later. Must have your Fedora 25 workstation ISO located in /var/lib/libvirt/images before running this script.


#define script variables for EDK2 first

EDK2_SOURCE=$HOME/edk2
OVMF_INSTALL=/opt/edk2/share/ovmf-smm

#copy the ovmf template for use at the end of this script
cp ./ovmf.fedora.q35.template $HOME

dnf -y group install --with-optional virtualization

dnf -y install xorg-x11-xauth pixman-devel spice-server-devel gcc-c++ nasm libuuid-devel acpica-tools patch python

git clone https://github.com/tianocore/edk2.git $EDK2_SOURCE
git clone -b OpenSSL_1_1_0e https://github.com/openssl/openssl $EDK2_SOURCE/CryptoPkg/Library/OpensslLib/openssl

systemctl enable sshd
systemctl start sshd

sed -i 's,^\(PasswordAuthentication \).*,\1'no',' /etc/ssh/sshd_config
ssh-keygen -t rsa -b 4096 -N '' -f smmtest.rsa
cat smmtest.rsa.pub >> ./authorized_keys
mv -v ./authorized_keys ~/.ssh/authorized_keys
chmod 755 ~/.ssh
chmod 644 ~/.ssh/authorized_keys

 
#Enable libvirt 

systemctl enable libvirtd
systemctl start libvirtd

systemctl enable virtlogd
systemctl start virtlogd

#now it is time to enable permanent nested virtualization

sed --regexp-extended --in-place=.bak \
  --expression='s,^#(options kvm_intel nested=1)$,\1,' \
  /etc/modprobe.d/kvm.conf

rmmod kvm_intel
modprobe kvm_intel

#verifying the setting, if everything was done right the output should be "Y"
echo "Verifying  nested VM capability:"
cat /sys/module/kvm_intel/parameters/nested


#Patch the EDK2 source code SSL library. The process has changed since Laszlo created the tutorial page. the script called is now process_files.

cd $EDK2_SOURCE/CryptoPkg/Library/OpensslLib

perl process_files.pl

#Build OVMF
cd $EDK2_SOURCE
. ./edksetup.sh
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


#Time to install the OVMF
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

chcon -v --reference=/usr/share/qemu/bios.bin ${OVMF_INSTALL}/*.fd



#Assuming Fedora 26 workstation ISO located in /var/lib/libvirt/images

qemu-img create -f qcow2 \
  -o compat=1.1 -o cluster_size=65536 \
  -o preallocation=metadata -o lazy_refcounts=on \
  /var/lib/libvirt/images/ovmf.fedora.q35.img 100G

#get template to virtual host

#for some reason the script does not find the template in the repo directory. We must copy it to the $HOME directory and then execute virsh
cd $HOME
virsh define ovmf.fedora.q35.template



echo "This host for testing SMM with QEMU, KVM, and libvirt is now configured and ready to run the VM for testing remotely. Please move 'smmtest.rsa' to your remote access machine and begin the testing."
