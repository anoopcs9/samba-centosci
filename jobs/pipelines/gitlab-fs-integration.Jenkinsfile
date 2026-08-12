def FILE_SYSTEMS = ['cephfs', 'xfs']

@NonCPS
def matchCell(String actionType, String triggerPhrase, String mrLabels, String fileSystem) {
    if (actionType == 'PUSH') {
        return true
    }
    if (actionType == 'NOTE') {
        if (triggerPhrase =~ /(?m)\/(re)?run\s+all/) {
            return true
        }
        if (triggerPhrase =~ /(?m)\/(re)?run\s+ci\s*$/) {
            return true
        }
        def m = triggerPhrase =~ /(?m)\/(re)?run\s+ci\/([^\s]+)/
        if (m.find()) {
            return m.group(2) == fileSystem
        }
        return false
    }
    if (actionType == 'MERGE' && mrLabels) {
        return mrLabels.contains("ci/${fileSystem}")
    }
    return true
}

@NonCPS
def filterContains(String filter, String value) {
    for (def item in filter.split(',')) {
        if (item.trim() == value) return true
    }
    return false
}

def shouldRunCell(String fileSystem) {
    def filter = params.FILE_SYSTEM_VARIANT_FILTER
    if (filter && filter != 'all' && !filterContains(filter, fileSystem)) {
        return false
    }
    def actionType = env.gitlabActionType ?: ''
    def triggerPhrase = env.gitlabTriggerPhrase ?: ''
    def mrLabels = env.gitlabMergeRequestLabels ?: ''
    return matchCell(actionType, triggerPhrase, mrLabels, fileSystem)
}

def buildCell(String fileSystem) {
    def statusName = "ci/${fileSystem}"
    def cellName = "samba_gitlab-${fileSystem}-integration"

    node('cico-workspace') {
        checkout([$class: 'GitSCM',
            branches: scm.branches,
            userRemoteConfigs: scm.userRemoteConfigs,
        ])

        withEnv([
            "FILE_SYSTEM=${fileSystem}",
            "CENTOS_VERSION=9s",
            "OS_ARCH=x86_64",
            "DUFFY_POOL_TYPE=metal",
        ]) {
            try {
                updateGitlabCommitStatus name: statusName, state: 'running'

                stage("${cellName} - Provision Node") {
                    sh 'jobs/scripts/common/get-node.sh'
                }

                stage("${cellName} - Build") {
                    sh """
                        jobs/scripts/common/bootstrap.sh \
                            \$WORKSPACE/jobs/scripts/gitlab-fs-integration/gitlab-fs-integration.sh \
                            "MERGE_REQUEST_IID=\${gitlabMergeRequestIid} TARGET_REPO_HTTP_URL=\${gitlabTargetRepoHttpUrl} CENTOS_VERSION=\${CENTOS_VERSION} FILE_SYSTEM=\${FILE_SYSTEM}"
                    """
                }

                updateGitlabCommitStatus name: statusName, state: 'success'
            } catch (err) {
                currentBuild.result = 'FAILURE'
                updateGitlabCommitStatus name: statusName, state: 'failed'
                emailext(
                    to: '${gitlabUserEmail}',
                    replyTo: '$DEFAULT_REPLYTO',
                    subject: "${cellName} - Build # ${env.BUILD_NUMBER} - \${BUILD_STATUS}!",
                    body: '$DEFAULT_CONTENT',
                    mimeType: 'text/plain',
                    attachLog: true
                )
                throw err
            } finally {
                stage("${cellName} - Copy Results") {
                    sh "jobs/scripts/gitlab-fs-integration/copy.sh || true"
                    sh "mkdir -p ${fileSystem} && mv -f test.out *.tar.gz ${fileSystem}/ 2>/dev/null || true"
                    archiveArtifacts artifacts: "${fileSystem}/**", allowEmptyArchive: true
                }
                stage("${cellName} - Return Node") {
                    sh 'jobs/scripts/common/return-node.sh'
                }
            }
        }
    }
}

properties([
    buildDiscarder(logRotator(daysToKeepStr: '14', artifactDaysToKeepStr: '14')),
    parameters([
        string(name: 'FILE_SYSTEM_VARIANT_FILTER', defaultValue: 'all',
               description: 'Run a specific file system variant (e.g. cephfs) or all')
    ]),
    [$class: 'GitLabConnectionProperty', gitLabConnection: 'samba-upstream-gitlab'],
    pipelineTriggers([
        [$class: 'GitLabPushTrigger',
            triggerOnPush: false,
            triggerOnMergeRequest: false,
            triggerOpenMergeRequestOnPush: 'source',
            triggerOnlyIfNewCommitsPushed: true,
            noteRegex: '/(re)?run ((all)|(ci(/[^\\s]*)?))',
            ciSkip: false,
            setBuildDescription: false,
            addNoteOnMergeRequest: false,
            addVoteOnMergeRequest: false,
            labelsThatForcesBuildIfAdded: 'ci/cephfs,ci/xfs',
        ]
    ])
])

def cells = [:]
for (def fs in FILE_SYSTEMS) {
    def fileSystem = fs
    if (shouldRunCell(fileSystem)) {
        cells["${fileSystem}"] = { buildCell(fileSystem) }
    }
}

if (cells.isEmpty()) {
    echo 'No matching cells to build'
} else {
    parallel cells
}
