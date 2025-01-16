#!/bin/bash

CONTAINER_GIT_REPO="https://github.com/phlogistonjohn/samba-container"
CONTAINER_GIT_BRANCH="jjm-build-img-next-2"
CONTAINER_CMD=${CONTAINER_CMD:-podman}
IMG_REGISTRY="quay.io"
# Temporarily using John Mulligan's quay.io repository with a bot account until
# jobs are complete and stable enough for container images to be published on
# quay.io/samba.org
IMG_REGISTRY_BASE="${IMG_REGISTRY}/phlogistonjohn"
# At the moment we are interested in pushing unqualified tags only for x86_64
PUSH_TAGS_SELECTION=$([[ $OS_ARCH != "x86_64" ]] && echo "fqin" || echo "mixed")

# if anything fails, we'll abort
set -e

dnf -y install git make podman

git clone --depth=1 --branch="${CONTAINER_GIT_BRANCH}" \
	"${CONTAINER_GIT_REPO}" "${CONTAINER_GIT_BRANCH}"
cd "${CONTAINER_GIT_BRANCH}"

make KIND=${KIND} OS_NAME=${OS_NAME} PACKAGE_SOURCE=${PACKAGE_SOURCE} \
	BUILD_ARCH=${OS_ARCH} build-image

IMAGE=$(./hack/build-image --kind ${KIND} --distro-base ${OS_NAME} \
		--package-source ${PACKAGE_SOURCE} --arch ${OS_ARCH} \
		--print)

./hack/build-image --retag --container-engine ${CONTAINER_CMD} \
	--repo-base ${IMG_REGISTRY_BASE} --no-distro-qualified \
	-i ${IMAGE}

podman login -u ${IMG_REGISTRY_USER} \
	-p ${IMG_REGISTRY_PASSWORD} ${IMG_REGISTRY}

./hack/build-image --push --container-engine ${CONTAINER_CMD} --verbose \
	--push-state "exists" --push-selected-tags ${PUSH_TAGS_SELECTION} \
	-i ${IMG_REGISTRY_BASE}/${IMAGE}

podman logout ${IMG_REGISTRY}
