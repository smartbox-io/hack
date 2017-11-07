pipeline {
  agent any
  parameters {
    string(name: "INTEGRATION_BRANCH", defaultValue: "master", description: "Integration project branch to build with")
    string(name: "CELL_NUMBER", defaultValue: "1", description: "Integration. Number of cells to deploy")
  }
  stages {
    stage("Retrieve build environment") {
      steps {
        script {
          GIT_COMMIT_MESSAGE = sh(returnStdout: true, script: "git rev-list --format=%B --max-count=1 ${GIT_COMMIT}").trim()
        }
      }
    }
    stage("Integration tests") {
      steps {
        script {
          build job: "integration/${INTEGRATION_BRANCH}", parameters: [
            string(name: "COMMIT_MESSAGE", value: GIT_COMMIT_MESSAGE),
            string(name: "HACK_BRANCH", value: GIT_BRANCH),
            string(name: "CELL_NUMBER", value: CELL_NUMBER)
          ]
        }
      }
    }
  }
}