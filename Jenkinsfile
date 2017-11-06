pipeline {
  agent any
  parameters {
    string(name: "INTEGRATION_COMMIT", defaultValue: "master", description: "Integration project commit to build with")
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
    stage("Run integration tests") {
      steps {
        script {
          build job: "integration/master", parameters: [
            string(name: "INTEGRATION_COMMIT", value: INTEGRATION_COMMIT),
            string(name: "HACK_COMMIT", value: GIT_COMMIT)
          ]
        }
      }
    }
  }
}