#!/bin/bash

# Set up a centos8 machine with the required environment to
# run the tests from https://github.com/samba-in-kubernetes/sit-test-cases.git
# and run the tests.

BACKEND="${FILE_SYSTEM:-cephfs}"
CENTOS_VERSION="${CENTOS_VERSION//[!0-9]}"
TEST_EXTRA_VARS=""
TEST_TARGET="test"

set -e

dnf -y install git

rm -rf tests
mkdir tests
cd tests
git clone --branch vfs-ceph-new https://github.com/anoopcs9/sit-environment.git
cd sit-environment

if [ -n "${gitlabMergeRequestIid}" ]; then
cat << EOF > local.yml
install:
  samba:
    git:
      repo: ${gitlabTargetRepoHttpUrl}
      mr: ${gitlabMergeRequestIid}
EOF
else
cat << EOF > local.yml
install:
  samba:
    git:
      repo: https://gitlab.com/synarete/samba.git
      version: vfs_ceph_new
EOF
fi

TEST_EXTRA_VARS="backend=${BACKEND}"

dnf -y install epel-release epel-next-release

dnf -y install make ansible-core

if [ "${CENTOS_VERSION}" -eq 8 ]; then
	dnf -y install python3.12-pip
	dnf -y install ansible-collection-ansible-posix \
		ansible-collection-ansible-utils
	pip3.12 install netaddr
else
	dnf config-manager --set-enabled crb
	dnf -y install python3-pip
	ansible-galaxy collection install ansible.posix ansible.utils
	pip3 install netaddr
fi

dnf -y install qemu-kvm qemu-img libvirt libvirt-devel

dnf -y copr enable pvalena/vagrant
dnf -y install vagrant vagrant-libvirt rsync

setfacl -m u:qemu:x /root/

systemctl start libvirtd

set +e

EXTRA_VARS="${TEST_EXTRA_VARS}" make "${TEST_TARGET}"
ret=$?

EXTRA_VARS="${TEST_EXTRA_VARS}" make statedump

pushd /tmp
find "sit_statedump" -name test.out -exec cp {} . \;
tar -zcvf "sit_statedump.tar.gz" "sit_statedump"
popd

exit $ret
