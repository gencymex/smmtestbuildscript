
#Install pre-requisites and enable secure remote connection, do not forget to grab you SSH keys to access later. Must have your Fedora 25 workstation ISO located in /var/lib/libvirt/images be
#fore running this script

dnf group install with-optional virtualization

dnf -y install xorg-x11-xauth pixman-devel spice-server-devel gcc-c++ nasm libuuid-devel acpica-tools patch python

systemctl enable sshd
systemctl start sshd

sed -i 's,^\(PasswordAuthentication \).*,\1'no',' /etc/ssh/sshd_config
ssh-keygen -t rsa -b 4096 -N '' -f smmtest.rsa
cat smmtest.rsa.pub >> ./authorized_keys
cp -v ./authorized_keys ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
 


#Enable libvirt 

systemctl enable libvirtd
systemctl start libvirtd

systemctl enable virtlogd
systemctl start virtlogd


#Check to see if QEMU is installed, if installed then remove, if not installed, then download and build


QEMU_SOURCE=$HOME/qemu
QEMU_BUILD=$HOME/qemu-build
QEMU_INSTALL=/opt/qemu

git clone git://git.qemu.org/qemu.git $QEMU_SOURCE
cd $QEMU_SOURCE
git checkout a0def594286d
mkdir -p -v $QEMU_BUILD
cd $QEMU_BUILD

$QEMU_SOURCE/configure \
  --target-list=x86_64-softmmu,i386-softmmu \
  --enable-spice \
  --enable-trace-backends=log \
  --enable-debug \
  --prefix=$QEMU_INSTALL

make -j $(getconf _NPROCESSORS_ONLN)
make install


#Now it is time to copy file attributes in order for libvirt to launch the QEMU binaries we just built

for BINARY in $QEMU_INSTALL/bin/qemu-system-*; do
  chown -c --reference=/usr/bin/qemu-system-x86_64 $BINARY
  chmod -c --reference=/usr/bin/qemu-system-x86_64 $BINARY
  chcon -v --reference=/usr/bin/qemu-system-x86_64 $BINARY
done



#now it is time to enable permanent nested virtualization

sed --regexp-extended --in-place=.bak \
  --expression='s,^#(options kvm_intel nested=1)$,\1,' \
  /etc/modprobe.d/kvm.conf

rmmod kvm_intel
modprobe kvm_intel

#verifying the setting, if everything was done right the output should be "Y"

cat /sys/module/kvm_intel/parameters/nested


#Time to clone the edk2 repo, change the EDK2_SOURCE to the location that you store your source code if necessary
EDK2_SOURCE=$HOME/edk2
git clone https://github.com/tianocore/edk2.git $EDK2_SOURCE


#Patch the EDK2 source code SSL library

cd $EDK2_SOURCE/CryptoPkg/Library/OpensslLib

git clone -b OpenSSL_1_1_0e https://github.com/openssl/openssl openssl

perl process_files.pl




#Build OVMF
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


#Time to install the OVMF
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

chcon -v --reference=${QEMU_INSTALL}/share/qemu/bios.bin ${OVMF_INSTALL}/*.fd



#Assuming Fedora 25 workstation ISO located in /var/lib/libvirt/images

qemu-img create -f qcow2 \
  -o compat=1.1 -o cluster_size=65536 \
  -o preallocation=metadata -o lazy_refcounts=on \
  /var/lib/libvirt/images/ovmf.fedora.q35.img 100G

#get template to virtual host

cd $HOME
wget https://github.com/tianocore/tianocore.github.io/wiki/libvirt-domain-templates/ovmf.fedora.q35.template

virsh define ovmf.fedora.q35.template



echo 'Please copy smmtest.rsa to your remote access machine' 
