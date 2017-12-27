DEVICE=/dev/disk/by-id/${STICK_ID}
DEVICE_PARTITION=${DEVICE}-part1
FSTYPE=btrfs
#FSTYPE=ext4
FSLABEL=debian9-64
MOUNTPOINT=/mnt/
ISO_URL_PATH=https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/
ISO_NAME=debian-live-9.2.0-amd64-mate.iso
APT_DRIVER=btrfs-tools aufs-dkms firmware-linux-nonfree firmware-iwlwifi firmware-realtek
APT_OTHER=tmux vim htop atop iotop sysstat



help:
	### Usage:
	# * change variables at top of Makefile or call make with the wanted environment variables
	# ** STICK_ID needs be set, everything else is optional
	# ** you can use "make find-stick-by-id" to list the available sticks
	#
	# * use "make all" or once the stick is partitioned "make all-save"
	#
	# * use "make chroot" to setup users and whatever else you want…
	#
	# * use "make clean" will unmount everything … and you are ready to boot the stick
	#

	### example:
	# > sudo STICK_ID=usb-TOSHIBA_TransMemory_0060E056B5B4E18050000F5D-0:0 make all-save



all-save:	clean find-stick-by-id mount persistence grub wget chroot-auto clean
	## like "make all" except partition+mkfs

all:	clean find-stick-by-id partition mkfs mount persistence grub wget chroot-auto clean

clean:	chroot-umount umount



find-stick-by-id:
	[ -n "${STICK_ID}" ] || (echo 'ERROR: The variable $${STICK_ID} must be set!'; \
				 echo 'available devices:'; \
				 ls -l /dev/disk/by-id/usb-* | grep -v -e '-part. ->' | grep --color 'usb[^ ]* ' || echo 'ERROR: No stick found!'; \
				 exit 1)
	[ -b ${DEVICE} ]



partition:
	which install-mbr || apt install mbr
	which parted || apt install parted
	dd if=/dev/zero of=${DEVICE} bs=4M count=1
	install-mbr --force ${DEVICE}
	parted ${DEVICE} mkpart primary 1 100%
	parted ${DEVICE} set 1 boot on

mkfs:
	[ -L ${DEVICE_PARTITION} ] || (echo 'ERROR: Partition not found!'; exit 2)
	mkfs -t ${FSTYPE} -L ${FSLABEL} ${DEVICE_PARTITION} #-f



umount:
	- umount ${DEVICE_PARTITION}

mount:	umount
	lsblk -f ${DEVICE_PARTITION} | grep -i ${FSTYPE} -B 1

	mount ${DEVICE_PARTITION} ${MOUNTPOINT}



rsync:
	rsync -avr files/* /mnt/



${MOUNTPOINT}/persistence.conf:	rsync
	
persistence:	${MOUNTPOINT}/persistence.conf



grub-install:
	grub-install --force --no-floppy --root-directory=${MOUNTPOINT} ${DEVICE}
	#grub-install --force --no-floppy --root-directory=${MOUNTPOINT} ${DEVICE_PARTITION}

grub-install-if-nonexisting:
	[ -d ${MOUNTPOINT}/boot/grub/i386-pc ] || (make grub-install)

${MOUNTPOINT}/boot/grub/grub.cfg:	rsync

grub.cfg:	${MOUNTPOINT}/boot/grub/grub.cfg
	## just a link to easier call this target

grub:	grub-install-if-nonexisting ${MOUNTPOINT}/boot/grub/grub.cfg



${MOUNTPOINT}/boot/iso:
	mkdir ${MOUNTPOINT}/boot/iso

${MOUNTPOINT}/boot/iso/${ISO_NAME}:	${MOUNTPOINT}/boot/iso
	## when ${ISO_NAME} exists in the current dir (e.g. via symlink) than we don't need to download
	[ -f ${ISO_NAME} ] && cp ${ISO_NAME} ${MOUNTPOINT}/boot/iso/${ISO_NAME}
	[ -f ${ISO_NAME} ] || wget -O ${MOUNTPOINT}/boot/iso/${ISO_NAME} ${ISO_URL_PATH}${ISO_NAME}

wget:	${MOUNTPOINT}/boot/iso/${ISO_NAME}



${MOUNTPOINT}/rw:
	mkdir ${MOUNTPOINT}/rw

chroot-umount:
	- umount /tmp/joined/proc/
	- umount /tmp/joined/sys/
	- umount /tmp/joined/dev/
	- umount /tmp/joined
	- umount /tmp/squash
	- umount /tmp/iso

chroot-mount: chroot-umount mount
	which /usr/bin/unionfs-fuse || apt install unionfs-fuse

	- mkdir /tmp/iso /tmp/squash /tmp/joined

	mount ${MOUNTPOINT}/boot/iso/${ISO_NAME} /tmp/iso
	mount /tmp/iso/live/filesystem.squashfs /tmp/squash
	unionfs-fuse -o cow ${MOUNTPOINT}/rw=rw:/tmp/squash=ro /tmp/joined

	mount -t proc proc /tmp/joined/proc/
	mount -t sysfs sys /tmp/joined/sys/
	mount -o bind /dev /tmp/joined/dev/

chroot-setup:
	- rm /tmp/joined/etc/resolv.conf  ## in case it is a symlink
	echo 'nameserver 8.8.8.8' > /tmp/joined/etc/resolv.conf
	sed -i -e 's/main.*$$/main contrib non-free/g' /tmp/joined/etc/apt/sources.list.d/base.list
	chroot /tmp/joined apt update

	chroot /tmp/joined apt install -y ${APT_DRIVER}
	chroot /tmp/joined apt install -y ${APT_OTHER}

${MOUNTPOINT}/rw/boot/initrd.img-4.9.0-4-amd64:	files/rw/etc/initramfs-tools/scripts/live
	chroot /tmp/joined update-initramfs.orig.initramfs-tools -u -t

chroot-initramfs:	${MOUNTPOINT}/rw/boot/initrd.img-4.9.0-4-amd64

chroot-auto:	${MOUNTPOINT}/rw chroot-mount chroot-setup chroot-initramfs

chroot:	${MOUNTPOINT}/rw chroot-mount
	### Now feel free to use the image in a chroot ###
	#   You might want:
	#   > dpkg-reconfigure locales tzdata
	#   > passwd
	#   > adduser user
        ###
	#   > exit
	###
	chroot /tmp/joined
