#!/bin/bash

PULL_REQUEST_ID="${PULL_REQUEST_ID:-${PULL_REQUEST_ID}}"
TARGET_BRANCH="${TARGET_BRANCH:-${ghprbTargetBranch:-master}}"
ACTUAL_COMMIT="${ACTUAL_COMMIT:-${sha1}}"
SINK_OPERATOR_GIT_REPO="${BUILD_GIT_REPO:-https://github.com/samba-in-kubernetes/samba-operator}"
SINK_OPERATOR_GIT_BRANCH=${SINK_OPERATOR_GIT_BRANCH:-"master"}

CENTOS_VERSION="${CENTOS_VERSION//[!0-9]}"
KUBE_VERSION=${KUBE_VERSION:-"latest"}
CONTAINER_CMD=${CONTAINER_CMD:-"podman"}

CI_IMG_REGISTRY="registry-samba.apps.ocp.cloud.ci.centos.org"
CI_IMG_TAG="ci-k8s-${KUBE_VERSION}-run"

# Exit immediately if a command exits with non-zero status
set -e

if [ "${CENTOS_VERSION}" -eq 9 ]; then
	dnf config-manager --set-enabled crb
fi

dnf -y install git podman skopeo

${CONTAINER_CMD} login --authfile=".podman-auth.json" \
	--username="${IMG_REGISTRY_AUTH_USR}" \
	--password="${IMG_REGISTRY_AUTH_PASSWD}" ${CI_IMG_REGISTRY}

REGISTRY_AUTH_FILE="$(readlink -f .podman-auth.json)"

# Git clone samba-operator repository
git clone --depth=1 --branch="${SINK_OPERATOR_GIT_BRANCH}" "${SINK_OPERATOR_GIT_REPO}"

pushd samba-operator || exit 1

if [ -n "${PULL_REQUEST_ID}" ]; then
	# We have to fetch the whole target branch to be able to rebase.
	git fetch --unshallow  origin

	git fetch origin "pull/${PULL_REQUEST_ID}/head:pr_${PULL_REQUEST_ID}"
	git checkout "pr_${PULL_REQUEST_ID}"

	git rebase "origin/${TARGET_BRANCH}"
	ret=$?
	if [ $ret -ne 0 ] ; then
		echo "Unable to automatically rebase to \
			branch '${TARGET_BRANCH}'. Please rebase your PR!"
		exit 1
	fi

	declare -a SKIP_FILES=(docs/ .md LICENSE .codespellignore .codespellrc \
				.github .gitignore .golangci.yaml .revive.toml \
				.yamllint.yaml)

	readarray FILES_CHANGED < <(git diff --name-only origin/"${TARGET_BRANCH}")

	proceed=0
	for i in "${FILES_CHANGED[@]}"
	do
		found=0
		for j in "${SKIP_FILES[@]}"
		do
			if [[ "$i" =~ "$j" ]]; then
				found=1
				break
			fi
		done
		if [ ${found} -eq 0 ]; then
			proceed=1
		fi
	done

	if [ ${proceed} -eq 0 ]; then
		echo "Doc/Format-Spec only change, skipping..."
		exit 0
	fi

	CI_IMG_TAG="ci-k8s-${KUBE_VERSION}-pr${PULL_REQUEST_ID}"
	# if the sha1 hash is provided, we will try to append a short form of it to
	# the tag to make the image unique to each "push" of the PR.
	if [[ "$ACTUAL_COMMIT" =~ ^[abcdef0-9]{4}[abcdef0-9]*$ ]]; then
		shortsha="${sha1:0:8}"
		CI_IMG_TAG="${CI_IMG_TAG}-${shortsha}"
	fi
fi

CI_IMG_OP="${CI_IMG_REGISTRY}/sink/samba-operator:${CI_IMG_TAG}"

export CONTAINER_CMD REGISTRY_AUTH_FILE CI_IMG_REGISTRY CI_IMG_OP

./tests/centosci/sink-clustered-deployment.sh

# Mark current operator image for deletion from CI registry
skopeo delete "docker://${CI_IMG_OP}"

popd || exit 1

exit 0
