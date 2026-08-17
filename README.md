# CentOS CI

This repository contains Jenkins Pipeline definitions, JJB job configurations, and Openshift object specs for testing Samba and related integration projects. These jobs are run on an OCP4 based [Jenkins][ocp4-jenkins] instance.

[ocp4-jenkins]: https://jenkins-samba.apps.ocp.cloud.ci.centos.org/
[jjb]: https://jenkins-job-builder.readthedocs.io/en/latest/
[gwt]: https://plugins.jenkins.io/generic-webhook-trigger/

## Repository breakdown

- [.github/workflows/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/.github/workflows)
	- *deploy.yaml*: GitHub action to update JJB job definitions in Jenkins. Triggered manually via workflow_dispatch when JJB YAML files change.
	- *verify.yaml*: GitHub action to verify YAML changes for pull requests raised in the repository.
- [deploy/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/deploy)
	- *container-registry.yaml*: Openshift spec for project/namespaced deployment of a local image registry within CentOS CI.
	- *deploy-jobs.sh*: Helper script to update jobs in Jenkins using jenkins-jobs commandline utility. Used as alternate entrypoint for container built with Dockerfile.
	- *Dockerfile*: Instructions to build a container with jenkins-jobs installed to handle job configuration changes.
	- *jenkins.conf*: Configurations to connect to Jenkins instance running on Openshift.
	- *verify-yaml.sh*: Helper script to perform check on YAML changes. Default entrypoint inside container.

- [jobs/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/jobs)

	Job definitions for [Jenkins][ocp4-jenkins]:

	- [jobs/pipelines/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/jobs/pipelines) - Scripted Pipeline (Jenkinsfile) definitions. These are loaded directly from the repository by Jenkins on each build and do not require a deploy to take effect.
		- *build-rpms.Jenkinsfile*: Builds Samba RPMs across os_version, os_arch, and samba_branch combinations (24 parallel cells). Triggered by [samba-build](https://github.com/samba-in-kubernetes/samba-build) events via [Generic Webhook Trigger][gwt].
		- *fs-integration-test-cases.Jenkinsfile*: Runs FS integration tests from [sit-test-cases](https://github.com/samba-in-kubernetes/sit-test-cases) across 6 filesystem backends in parallel.
		- *fs-integration-environment.Jenkinsfile*: Runs FS integration tests from [sit-environment](https://github.com/samba-in-kubernetes/sit-environment) across 6 filesystem backends in parallel.
		- *gitlab-fs-integration.Jenkinsfile*: Runs FS integration tests triggered by GitLab MRs from Samba upstream, across cephfs and xfs backends.
		- *sink-clustered-deployment.Jenkinsfile*: Runs SINK clustered deployment tests from [samba-operator](https://github.com/samba-in-kubernetes/samba-operator) across k8s versions in parallel.

	- *\*-pipeline.yml*: [JJB][jjb] definitions that register the Pipeline jobs in Jenkins. These only define the job shell (name, SCM source, properties) and point to the corresponding Jenkinsfile. Changes to these files require running the deploy workflow.

- [jobs/scripts/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/jobs/scripts)

	Shell scripts executed by the Pipeline jobs. Common scripts handle Duffy node provisioning (`get-node.sh`), remote execution (`bootstrap.sh`), and cleanup (`return-node.sh`). Job-specific scripts are in per-job subdirectories.

- [mirror/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/mirror)

	Openshift specs of a CronJob mirroring those images from docker.io which may get blocked while pulling due to "Download rate limit exceeded" error.
- [prune/](https://github.com/samba-in-kubernetes/samba-centosci/tree/main/prune)

	Openshift specs of a CronJob to clean up images marked for deletion within local CI registry using docker registry's garbage collection.
