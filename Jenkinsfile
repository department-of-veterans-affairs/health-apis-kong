pipeline {
  options {
    buildDiscarder(logRotator(numToKeepStr: '99', artifactNumToKeepStr: '99'))
    retry(0)
    timeout(time: 1440, unit: 'MINUTES')
    timestamps()
  }
  environment {
    registry = "vasdvp/health-apis-kong"
    registryCredential = 'DOCKER_USERNAME_PASSWORD'
    dockerImage = ''
  }
  agent any
  stages {
    stage('Cloning Git') {
      steps {
        checkout scm
      }
    }
    stage('Building health-apis-kong image') {
      steps{
        script {
          dockerImage = docker.build registry + ":1.0.$BUILD_NUMBER"
        }
      }
    }
    stage('Deploy health-apis-kong image') {
      steps{
        script {
          if (env.BRANCH_NAME == 'master') {
            docker.withRegistry( '', registryCredential) {
                dockerImage.push()
            }
          }
        }
      }
    }
    stage('Remove Unused docker image') {
      steps{
        sh "docker rmi $registry:1.0.$BUILD_NUMBER"
      }
    }
  }
}