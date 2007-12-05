lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
selinux --disabled
firewall --disabled
part / --size 950
services --disabled=iptables --enabled=ntpd,collectd
bootloader --timeout=1

repo --name=f8 --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-8&arch=$basearch
#repo --name=development --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch

repo --name=libvirt-gssapi --baseurl=http://laforge.boston.redhat.com/rpms


%packages
@core
bash
kernel
passwd
policycoreutils
chkconfig
authconfig
rootfiles
dhclient
libvirt
openssh-clients
openssh-server
iscsi-initiator-utils
ntp
kvm
nfs-utils
wget
krb5-workstation
cyrus-sasl-gssapi
cyrus-sasl
cyrus-sasl-lib
collectd
tftp
-policycoreutils
-audit-libs-python
-hdparm
-libsemanage
-ustr
-authconfig
-rhpl
-wireless-tools
-setserial
-prelink
-newt-python
-newt
-selinux-policy-targeted
-selinux-policy
-kudzu
-libselinux-python
-rhpl
-glibc.i686
-xen-libs.i386
-libxml2.i386
-zlib.i386
-libvirt.i386
-avahi.i386
-libgcrypt.i386
-gnutls.i386
-libstdc++.i386
-e2fsprogs-libs.i386
-ncurses.i386
-readline.i386
-libselinux.i386
-device-mapper-libs.i386
-libdaemon.i386
-dbus-libs.i386
-expat.i386
-libsepol.i386
-libcap.i386
-libgpg-error.i386
-libgcc.i386
-kbd
-usermode
-grub
-fedora-logos
-kpartx
-dmraid
-mkinitrd
-parted
-nash
-tar
-openldap
-libuser
-mdadm
-mtools
-cpio
-cyrus-sasl-gssapi.i386
-cyrus-sasl-lib.i386

%post

# the ovirt service

cat > /etc/init.d/ovirt << \EOF
#!/bin/bash
#
# ovirt Start ovirt services
#
# chkconfig: 3 99 01
# description: ovirt services
#

# Source functions library
. /etc/init.d/functions

start() {
        # HACK: we need to do depmod here to make sure we get updated kvm
        # modules; this does not work in %post, since I don't think that is
        # done in a chroot
        /sbin/depmod

        modprobe kvm
        modprobe kvm-intel >& /dev/null
        modprobe kvm-amd >& /dev/null
        # login to all of the discovered iSCSI servers
	# HACK: this should be delegated to the iSCSI scripts
        for server in `cat /etc/iscsi-servers.conf`; do
            scan=`/sbin/iscsiadm --mode discovery --type sendtargets --portal $server 2>/dev/null`
            if [ $? -ne 0 ]; then
                 echo "Failed scanning $server...skipping"
                 continue
	    fi
            target=`echo $scan | cut -d' ' -f2`
            port=`echo $scan | cut -d':' -f2 | cut -d',' -f1`
            /sbin/iscsiadm --mode node --targetname $target --portal $server:$port --login
        done

        /sbin/iptables -A FORWARD -m physdev --physdev-is-bridged -j ACCEPT
}

stop() {
        /sbin/iptables -D FORWARD -m physdev --physdev-is-bridged -j ACCEPT
        /sbin/iscsiadm --mode node --logoutall=all
        rmmod kvm-intel >& /dev/null
        rmmod kvm-amd >& /dev/null
        rmmod kvm >& /dev/null
}

case "$1" in
  start)
        start
        ;;
  stop)
        stop
        ;;
  restart)
        stop
        start
        ;;
  *)
        echo "Usage: ovirt {start|stop|restart}"
        exit 2
esac
EOF

chmod +x /etc/init.d/ovirt
/sbin/chkconfig ovirt on

# next the dynamic bridge setup service
cat > /etc/init.d/ovirt-early << \EOF
#!/bin/bash
#
# ovirt-early Start early ovirt services
#
# chkconfig: 3 01 99
# description: ovirt-early services
#

# Source functions library
. /etc/init.d/functions

start() {
        # find all of the ethernet devices in the system
        cd /sys/class/net
        ETHDEVS=`ls -d eth*`
        cd $OLDPWD
        for eth in $ETHDEVS; do
            BRIDGE=ovirtbr`echo $eth | cut -b4-`
            echo -e "DEVICE=$eth\nONBOOT=yes\nBRIDGE=$BRIDGE" > /etc/sysconfig/network-scripts/ifcfg-$eth
            echo -e "DEVICE=$BRIDGE\nBOOTPROTO=dhcp\nONBOOT=yes\nTYPE=Bridge" > /etc/sysconfig/network-scripts/ifcfg-$BRIDGE
            echo 'DHCLIENTARGS="-R subnet-mask,broadcast-address,time-offset,routers,domain-name,domain-name-servers,host-name,nis-domain,nis-servers,ntp-servers,iscsi-servers,libvirt-auth-method"' >> /etc/sysconfig/network-scripts/ifcfg-$BRIDGE
        done

        # find all of the partitions on the system

        # get the system pagesize
        PAGESIZE=`getconf PAGESIZE`

        # look first at raw partitions
        BLOCKDEVS=`ls /dev/sd? /dev/hd? 2>/dev/null`

        # now LVM partitions
        LVMDEVS="$DEVICES `/usr/sbin/lvscan | awk '{print $2}' | tr -d \"'\"`"

	SWAPDEVS="$LVMDEVS"
        for dev in $BLOCKDEVS; do
            SWAPDEVS="$SWAPDEVS `/sbin/fdisk -l $dev 2>/dev/null | sed -e 's/*/ /' | awk '$5 ~ /82/ {print $1}' | xargs`"
        done

	# now check if any of these partitions are swap, and activate if so
        for device in $SWAPDEVS; do
            sig=`dd if=$device bs=1 count=10 skip=$(( $PAGESIZE - 10 )) 2>/dev/null`
            if [ "$sig" = "SWAPSPACE2" ]; then
                /sbin/swapon $device
            fi
        done
}

stop() {
        # nothing to do
        return
}

case "$1" in
  start)
        start
        ;;
  stop)
        stop
        ;;
  restart)
        stop
        start
        ;;
  *)
        echo "Usage: ovirt-early {start|stop|restart}"
        exit 2
esac
EOF

chmod +x /etc/init.d/ovirt-early
/sbin/chkconfig ovirt-early on

# just to get a boot warning to shut up
touch /etc/resolv.conf

# needed for the iscsi-servers dhcp option
cat > /etc/dhclient.conf << EOF
option iscsi-servers code 200 = array of ip-address;
option libvirt-auth-method code 202 = text;
EOF

cat > /etc/dhclient-up-hooks << \EOF
if [ -n "$new_iscsi_servers" ]; then
    for s in $new_iscsi_servers; do
        echo $s >> /etc/iscsi-servers.conf
    done
fi
if [ -n "$new_libvirt_auth_method" ]; then
    METHOD=`echo $new_libvirt_auth_method | cut -d':' -f1`
    SERVER=`echo $new_libvirt_auth_method | cut -d':' -f2-`
    if [ $METHOD = "krb5" ]; then
        mkdir -p /etc/libvirt
        wget -q http://$SERVER/$new_ip_address-libvirt.tab -O /etc/libvirt/krb5.tab
        rm -f /etc/krb5.conf ; wget -q http://$SERVER/$new_ip_address-krb5.conf -O /etc/krb5.conf
    fi
fi
EOF

chmod +x /etc/dhclient-up-hooks

# make libvirtd listen on the external interfaces
sed -i -e 's/#LIBVIRTD_ARGS="--listen"/LIBVIRTD_ARGS="--listen"/' /etc/sysconfig/libvirtd

cat > /etc/kvm-ifup << \EOF
#!/bin/sh

switch=$(/sbin/ip route list | awk '/^default / { print $NF }')
/sbin/ifconfig $1 0.0.0.0 up
/usr/sbin/brctl addif ${switch} $1
EOF

chmod +x /etc/kvm-ifup

# set up qemu daemon to allow outside VNC connections
sed -i -e 's/# vnc_listen = \"0.0.0.0\"/vnc_listen = \"0.0.0.0\"/' /etc/libvirt/qemu.conf

# set up libvirtd to listen on TCP (for kerberos)
sed -i -e 's/# listen_tcp = 1/listen_tcp = 1/' /etc/libvirt/libvirtd.conf
sed -i -e 's/# listen_tls = 0/listen_tls = 0/' /etc/libvirt/libvirtd.conf

# make sure we don't autostart virbr0 on libvirtd startup
rm -f /etc/libvirt/qemu/networks/autostart/default.xml

%end