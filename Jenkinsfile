pipeline {
  agent any
  parameters {
    string(name: "INTEGRATION_BRANCH", defaultValue: "master", description: "Integration project branch to build with")
    string(name: "CELL_NUMBER", defaultValue: "1", description: "Number of cells to deploy")
  }
  stages {
    stage("Retrieve build environment") {
      steps {
        script {
          GIT_BRANCH = sh(returnStdout: true, script: "git rev-parse --abbrev-ref HEAD").trim()
          GIT_COMMIT = sh(returnStdout: true, script: "git rev-parse HEAD").trim()
        }
      }
    }
    stage("Integration tests") {
      steps {
        script {
          build job: "integration/${INTEGRATION_BRANCH}", parameters: [
            string(name: "HACK_BRANCH", value: GIT_BRANCH),
            string(name: "CELL_NUMBER", value: CELL_NUMBER)
          ]
        }
      }
    }
  }
}