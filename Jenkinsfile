/*
 * (C) Copyright 2019 Nuxeo (http://nuxeo.com/) and others.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Contributors:
 *     Antoine Taillefer <ataillefer@nuxeo.com>
 *     Nelson Silva <nsilva@nuxeo.com>
 */
 properties([
  [$class: 'GithubProjectProperty', projectUrlStr: 'https://github.com/nuxeo/jx-webui-env/'],
  [$class: 'BuildDiscarderProperty', strategy: [$class: 'LogRotator', daysToKeepStr: '60', numToKeepStr: '60', artifactNumToKeepStr: '5']],
  disableConcurrentBuilds(),
])

void setGitHubBuildStatus(String context, String message, String state) {
  step([
    $class: 'GitHubCommitStatusSetter',
    reposSource: [$class: 'ManuallyEnteredRepositorySource', url: 'https://github.com/nuxeo/jx-webui-env'],
    contextSource: [$class: 'ManuallyEnteredCommitContextSource', context: context],
    statusResultSource: [$class: 'ConditionalStatusResultSource', results: [[$class: 'AnyBuildResult', message: message, state: state]]],
  ])
}

String getTargetNamespace() {
  return BRANCH_NAME == 'master' ? 'webui' : 'webui-staging'
}

String getDryRun() {
  return BRANCH_NAME == 'master' ? 'false' : 'true'
}

pipeline {
  agent {
    label 'jenkins-jx-base'
  }
  environment {
    DRY_RUN = getDryRun()
    SERVICE_ACCOUNT = 'jenkins'
    NAMESPACE = getTargetNamespace()
  }
  stages {
    stage('Upgrade Jenkins X platform') {
      steps {
        setGitHubBuildStatus('upgrade', 'Upgrade Jenkins X platform', 'PENDING')
        container('jx-base') {
          echo "Upgrade Jenkins X ${NAMESPACE} platform"
          script {
            // get the existing docker config
            def dockerConfig = sh(
              script: "jx step credential -s jenkins-docker-cfg -k config.json | tr -d '\\n'",
              returnStdout: true
            ).trim();

            // get the existing npm token
            def npmToken = sh(
              script: 'jx step credential -s jenkins-npm-token -k token',
              returnStdout: true
            ).trim();

            // get the existing nexus password
            def packagesPassword = sh(
              script: "jx step credential -s packages.nuxeo.com-auth -k password",
              returnStdout: true
            ).trim();

            withEnv([
              "INTERNAL_DOCKER_REGISTRY=${DOCKER_REGISTRY}",
              "DOCKER_REGISTRY_CONFIG=${dockerConfig}",
              "NPM_TOKEN=${npmToken}",
              "PACKAGES_PASSWORD=${packagesPassword}",
            ]) {
              sh """
              # initialize Helm without installing Tiller
              helm init --client-only --service-account ${SERVICE_ACCOUNT}

              # add local chart repository
              helm repo add jenkins-x http://chartmuseum.jenkins-x.io

              # replace env vars in values.yaml
              # specify them explicitly to not replace DOCKER_REGISTRY which needs to be relative to the upgraded namespace:
              # webui-staging (PR) or webui (master)
              envsubst '\${NAMESPACE} \${INTERNAL_DOCKER_REGISTRY} \${DOCKER_REGISTRY_CONFIG} \${NPM_TOKEN} \${PACKAGES_PASSWORD} \${DRY_RUN}' < values.yaml > myvalues.yaml

              # upgrade Jenkins X platform
              jx upgrade platform --namespace=${NAMESPACE} \
                --version 2.0.1824 \
                --local-cloud-environment \
                --always-upgrade \
                --cleanup-temp-files=true \
                --batch-mode

              # restart Jenkins pod
              kubectl scale deployment jenkins -n ${NAMESPACE} --replicas 0
              kubectl scale deployment jenkins -n ${NAMESPACE} --replicas 1
            """
            }
          }
        }
      }
      post {
        success {
          setGitHubBuildStatus('upgrade', 'Upgrade Jenkins X platform', 'SUCCESS')
        }
        failure {
          setGitHubBuildStatus('upgrade', 'Upgrade Jenkins X platform', 'FAILURE')
        }
      }
    }
    stage('Perform Git release') {
      // TODO: skip if no changes since latest tag, to be able to manually run the pipeline on the master branch
      // in order to revert a bad "jx upgrade platform" launched by a PR. This would run "jx upgrade platform"
      // on the latest (stable) tag, aka master, without adding add an extra Git tag.
      when {
        branch 'master'
      }
      steps {
        setGitHubBuildStatus('release', 'Release', 'PENDING')
        container('jx-base') {
          script {
            VERSION = sh(returnStdout: true, script: 'jx-release-version')
          }
          withEnv(["VERSION=${VERSION}"]) {
            sh """
              # ensure we're not on a detached head
              git checkout master

              # create the Git credentials
              jx step git credentials
              git config credential.helper store

              # Git tag
              jx step tag -v ${VERSION}

              # Git release
              jx step changelog -v v${VERSION}
            """
          }
        }
      }
      post {
        always {
          step([$class: 'JiraIssueUpdater', issueSelector: [$class: 'DefaultIssueSelector'], scm: scm])
        }
        success {
          setGitHubBuildStatus('release', 'Release', 'SUCCESS')
        }
        failure {
          setGitHubBuildStatus('release', 'Release', 'FAILURE')
        }
      }
    }
  }
}
