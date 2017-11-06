pipeline {
  agent any
  stages {
    stage("Run integration tests") {
      steps {
        script {
          build job: "integration/master"
        }
      }
    }
  }
}