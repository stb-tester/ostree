#!/bin/bash

. $(dirname $0)/libtest.sh

echo "1..4"

setup_os_repository "archive-z2" "uboot"

cd ${test_tmpdir}

${CMD_PREFIX} ostree --repo=sysroot/ostree/repo remote add --set=gpg-verify=false testos $(cat httpd-address)/ostree/testos-repo
${CMD_PREFIX} ostree --repo=sysroot/ostree/repo pull testos testos/buildmaster/x86_64-runtime
${CMD_PREFIX} ostree admin deploy --karg=root=LABEL=rootfs --os=testos testos:testos/buildmaster/x86_64-runtime

assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'root=LABEL=rootfs'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'init='

echo "ok deployment with initramfs"

pull_test_tree() {
    kernel_contents=$1
    initramfs_contents=$2
    devicetree_contents=$3

    cd ${test_tmpdir}/osdata/boot
    rm -f initramfs* vmlinuz* devicetree*
    bootcsum=$(echo -n "$kernel_contents$initramfs_contents$devicetree_contents" \
               | sha256sum | cut -f 1 -d ' ')
    echo -n "$kernel_contents" > vmlinuz-3.6.0-${bootcsum}
    [ -n "$initramfs_contents" ] && echo -n "$initramfs_contents" > initramfs-3.6.0-${bootcsum}
    [ -n "$devicetree_contents" ] && echo -n "$devicetree_contents" > devicetree-3.6.0-${bootcsum}
    cd -
    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo commit --tree=dir=osdata/ -b testos/buildmaster/x86_64-runtime
    ${CMD_PREFIX} ostree pull testos:testos/buildmaster/x86_64-runtime
}

get_key_from_bootloader_conf() {
    conffile=$1
    key=$2

    awk "/^$key/ { print \$2 }" "$conffile"
}

pull_test_tree "the kernel only"
${CMD_PREFIX} ostree admin deploy --os=testos --karg=root=/dev/sda2 --karg=rootwait testos:testos/buildmaster/x86_64-runtime
assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'rootwait'
assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'init='
assert_not_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'initrd'

echo "ok switching to bootdir with no initramfs"

pull_test_tree "the kernel" "initramfs to assist the kernel"
${CMD_PREFIX} ostree admin deploy --os=testos --karg-none --karg=root=LABEL=rootfs testos:testos/buildmaster/x86_64-runtime
assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'initrd'
assert_file_has_content sysroot/boot/$(get_key_from_bootloader_conf sysroot/boot/loader/entries/ostree-testos-0.conf "initrd") "initramfs to assist the kernel"
assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'root=LABEL=rootfs'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'rootwait'
assert_not_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'init='

echo "ok switching from no initramfs to initramfs enabled sysroot"

pull_test_tree "the kernel" "" "my .dtb file"
${CMD_PREFIX} ostree admin deploy --os=testos testos:testos/buildmaster/x86_64-runtime
assert_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'init='
assert_file_has_content sysroot/boot/"$(get_key_from_bootloader_conf sysroot/boot/loader/entries/ostree-testos-0.conf 'devicetree')" "my .dtb file"
assert_not_file_has_content sysroot/boot/loader/entries/ostree-testos-0.conf 'initrd'

echo "ok switching from initramfs to no initramfs sysroot with devicetree"
