import groovy.json.JsonSlurper

def K8S_VERSIONS = ['1.33', '1.32', 'latest']

@NonCPS
def matchCell(String eventType, String comment, String k8sVersion) {
    if (!eventType || eventType == 'push' || eventType == 'pull_request') {
        return true
    }
    if (eventType == 'issue_comment') {
        if (comment =~ /(?m)\/(re)?test\s+all/) {
            return true
        }
        if (comment =~ /(?m)\/(re)?test\s+centos-ci\/sink-clustered\/mini-k8s\s*$/) {
            return true
        }
        def m = comment =~ /(?m)\/(re)?test\s+centos-ci\/sink-clustered\/mini-k8s-([^\s]+)/
        if (m.find()) {
            return m.group(2) == k8sVersion
        }
        return false
    }
    return true
}

@NonCPS
def isAuthorizedUser(String author) {
    def admins = ['obnoxxx', 'phlogistonjohn', 'gd', 'spuiuk', 'raghavendra-talur', 'synarete', 'anoopcs9']
    if (!author) {
        return true
    }
    return admins.contains(author)
}

@NonCPS
def parseJson(String text) {
    return new JsonSlurper().parseText(text)
}

def notifyGitHub(String state, String context, String description) {
    if (!env.COMMIT_SHA) {
        return
    }
    env.GH_STATUS_STATE = state
    env.GH_STATUS_CONTEXT = context
    env.GH_STATUS_DESC = description
    withCredentials([string(credentialsId: 'github-status-token', variable: 'GITHUB_TOKEN')]) {
        sh '''
            json=$(printf '{"state":"%s","context":"%s","description":"%s","target_url":"%s"}' \
                "$GH_STATUS_STATE" "$GH_STATUS_CONTEXT" "$GH_STATUS_DESC" "$BUILD_URL")
            curl -s -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$json" \
                "https://api.github.com/repos/samba-in-kubernetes/samba-operator/statuses/${COMMIT_SHA}"
        '''
    }
}

def resolveTriggerContext() {
    if (env.WEBHOOK_PR_ACTION in ['opened', 'synchronize']) {
        env.WEBHOOK_EVENT_TYPE = 'pull_request'
        env.PULL_REQUEST_ID    = env.WEBHOOK_PR_NUMBER
        env.TARGET_BRANCH      = env.WEBHOOK_TARGET_BRANCH ?: 'master'
        env.COMMIT_SHA         = env.WEBHOOK_COMMIT_SHA
    } else if (env.WEBHOOK_COMMENT_BODY) {
        env.WEBHOOK_EVENT_TYPE = 'issue_comment'
        env.PULL_REQUEST_ID    = env.WEBHOOK_COMMENT_PR_NUM
        env.TARGET_BRANCH      = 'master'
        withCredentials([string(credentialsId: 'github-status-token', variable: 'GITHUB_TOKEN')]) {
            def prData = sh(
                script: '''curl -s -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/repos/samba-in-kubernetes/samba-operator/pulls/${PULL_REQUEST_ID}"''',
                returnStdout: true
            ).trim()
            def prJson = parseJson(prData)
            env.COMMIT_SHA    = prJson.head.sha
            env.TARGET_BRANCH = prJson.base.ref
        }
    } else if (env.WEBHOOK_PUSH_REF == 'refs/heads/master') {
        env.WEBHOOK_EVENT_TYPE = 'push'
        env.PULL_REQUEST_ID    = ''
        env.TARGET_BRANCH      = ''
        env.COMMIT_SHA         = env.WEBHOOK_PUSH_HEAD_SHA
    } else {
        env.WEBHOOK_EVENT_TYPE = ''
        env.PULL_REQUEST_ID    = ''
        env.TARGET_BRANCH      = ''
        env.COMMIT_SHA         = ''
    }

    if (env.WEBHOOK_EVENT_TYPE == 'issue_comment' && !isAuthorizedUser(env.WEBHOOK_COMMENT_AUTHOR ?: '')) {
        currentBuild.result = 'NOT_BUILT'
        error("User ${env.WEBHOOK_COMMENT_AUTHOR} is not authorized to trigger builds")
    }

    if (env.PULL_REQUEST_ID && env.TARGET_BRANCH != 'master') {
        currentBuild.result = 'NOT_BUILT'
        error("PR targets branch '${env.TARGET_BRANCH}', not 'master'. Skipping.")
    }
}

@NonCPS
def filterContains(String filter, String value) {
    for (def item in filter.split(',')) {
        if (item.trim() == value) return true
    }
    return false
}

def shouldRunCell(String k8sVersion) {
    def filter = params.K8S_VARIANT_FILTER
    if (filter && filter != 'all' && !filterContains(filter, k8sVersion)) {
        return false
    }
    if (currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause')) {
        return true
    }
    if (env.WEBHOOK_EVENT_TYPE in ['pull_request', 'issue_comment']) {
        if (k8sVersion != 'latest') {
            return false
        }
    }
    return matchCell(env.WEBHOOK_EVENT_TYPE, env.WEBHOOK_COMMENT_BODY ?: '', k8sVersion)
}

def buildCell(String k8sVersion) {
    def ctx = "centos-ci/sink-clustered/mini-k8s-${k8sVersion}"
    def cellName = "samba_sink-mini-k8s-${k8sVersion}-clustered"

    node('cico-workspace') {
        checkout([$class: 'GitSCM',
            branches: scm.branches,
            userRemoteConfigs: scm.userRemoteConfigs,
        ])

        withEnv([
            "KUBE_VERSION=${k8sVersion}",
            "CENTOS_VERSION=9s",
            "OS_ARCH=x86_64",
            "DUFFY_POOL_TYPE=metal",
            "ROOK_VERSION=1.17",
        ]) {
            withCredentials([
                usernamePassword(credentialsId: 'samba-container-registry-auth',
                    usernameVariable: 'IMG_REGISTRY_AUTH_USR',
                    passwordVariable: 'IMG_REGISTRY_AUTH_PASSWD'),
            ]) {
                try {
                    if (env.PULL_REQUEST_ID) {
                        notifyGitHub('pending', ctx, 'Build started')
                    }

                    stage("${cellName} - Provision Node") {
                        sh 'jobs/scripts/common/get-node.sh'
                    }

                    stage("${cellName} - Build") {
                        sh """
                            jobs/scripts/common/bootstrap.sh \
                                \$WORKSPACE/jobs/scripts/sink-clustered-deployment/sink-clustered-deployment.sh \
                                "BUILD_GIT_REPO=\${BUILD_GIT_REPO} PULL_REQUEST_ID=\${PULL_REQUEST_ID} TARGET_BRANCH=\${TARGET_BRANCH} ACTUAL_COMMIT=\${COMMIT_SHA} CENTOS_VERSION=\${CENTOS_VERSION} IMG_REGISTRY_AUTH_USR=\${IMG_REGISTRY_AUTH_USR} IMG_REGISTRY_AUTH_PASSWD=\${IMG_REGISTRY_AUTH_PASSWD} KUBE_VERSION=\${KUBE_VERSION} ROOK_VERSION=\${ROOK_VERSION}"
                        """
                    }

                    if (env.PULL_REQUEST_ID) {
                        notifyGitHub('success', ctx, 'Build passed')
                    }
                } catch (err) {
                    currentBuild.result = 'FAILURE'
                    if (env.PULL_REQUEST_ID) {
                        notifyGitHub('failure', ctx, 'Build failed')
                    }
                    emailext(
                        to: 'anoopcs@samba.org',
                        replyTo: '$DEFAULT_REPLYTO',
                        subject: "${cellName} - Build # ${env.BUILD_NUMBER} - \${BUILD_STATUS}!",
                        body: '$DEFAULT_CONTENT',
                        mimeType: 'text/plain',
                        attachLog: true
                    )
                    throw err
                } finally {
                    stage("${cellName} - Return Node") {
                        sh 'jobs/scripts/common/return-node.sh'
                    }
                }
            }
        }
    }
}

properties([
    buildDiscarder(logRotator(daysToKeepStr: '7', artifactDaysToKeepStr: '7')),
    parameters([
        string(name: 'BUILD_GIT_REPO', defaultValue: 'https://github.com/samba-in-kubernetes/samba-operator',
               description: 'Git repo URL of samba-operator (for manual triggers)'),
        string(name: 'BUILD_GIT_BRANCH', defaultValue: 'master',
               description: 'Branch of samba-operator to build from (for manual triggers)'),
        string(name: 'K8S_VARIANT_FILTER', defaultValue: 'all',
               description: 'Run a specific k8s version (e.g. latest, 1.33) or all'),
    ]),
    pipelineTriggers([
        cron('H 2 * * *'),
        [$class: 'GenericTrigger',
            genericVariables: [
                [key: 'WEBHOOK_PR_NUMBER',      value: '$.pull_request.number',   defaultValue: ''],
                [key: 'WEBHOOK_TARGET_BRANCH',  value: '$.pull_request.base.ref', defaultValue: ''],
                [key: 'WEBHOOK_COMMIT_SHA',     value: '$.pull_request.head.sha', defaultValue: ''],
                [key: 'WEBHOOK_PR_ACTION',      value: '$.action',                defaultValue: ''],
                [key: 'WEBHOOK_COMMENT_BODY',   value: '$.comment.body',          defaultValue: ''],
                [key: 'WEBHOOK_COMMENT_AUTHOR', value: '$.comment.user.login',    defaultValue: ''],
                [key: 'WEBHOOK_COMMENT_PR_NUM', value: '$.issue.number',          defaultValue: ''],
                [key: 'WEBHOOK_PUSH_REF',       value: '$.ref',                   defaultValue: ''],
                [key: 'WEBHOOK_PUSH_HEAD_SHA',  value: '$.after',                 defaultValue: ''],
                [key: 'WEBHOOK_REPO_FULL_NAME', value: '$.repository.full_name',  defaultValue: ''],
            ],
            token: 'samba-sink-clustered-trigger',
            tokenCredentialId: '',
            causeString: 'Triggered by GitHub webhook on $WEBHOOK_REPO_FULL_NAME',
            printContributedVariables: true,
            printPostContent: false,
            regexpFilterText: '$WEBHOOK_PR_ACTION $WEBHOOK_COMMENT_BODY $WEBHOOK_PUSH_REF',
            regexpFilterExpression: '^(opened|synchronize|created|edited).*/(re)?test\\s+(all|centos-ci/sink-clustered(/[^\\s]*)?).*|^(opened|synchronize).*|^.*refs/heads/master.*$',
        ]
    ])
])

node('cico-workspace') {
    stage('Resolve Trigger Context') {
        resolveTriggerContext()
    }
}

def cells = [:]
for (def ver in K8S_VERSIONS) {
    def k8sVersion = ver
    if (shouldRunCell(k8sVersion)) {
        cells["k8s-${k8sVersion}"] = { buildCell(k8sVersion) }
    }
}

if (cells.isEmpty()) {
    echo 'No matching cells to build'
} else {
    parallel cells
}
