pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        AWS_CREDENTIALS_ID   = 'aws-jenkins-creds'
        TF_DIR               = 'terraform/dev'
        STORAGECLASS_FILE    = 'k8s/storageclass-gp3.yaml'
        MILVUS_TEMPLATE_FILE = 'helm/milvus-dev.yaml.tpl'
        MILVUS_RENDERED_FILE = 'helm/milvus-dev-rendered.yaml'
        K8S_NAMESPACE        = 'milvus'
    }

    parameters {
        choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action')
        booleanParam(name: 'DEPLOY_MILVUS', defaultValue: true, description: 'Deploy or upgrade Milvus after Terraform apply')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify Tools') {
            steps {
                sh '''
                    set -e
                    aws --version
                    terraform version
                    kubectl version --client
                    helm version
                    eksctl version
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_DIR}") {
                    sh '''
                        set -e
                        terraform init
                        terraform validate
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            when {
                anyOf {
                    expression { params.ACTION == 'plan' }
                    expression { params.ACTION == 'apply' }
                }
            }
            steps {
                dir("${TF_DIR}") {
                    sh '''
                        set -e
                        terraform plan -out=tfplan
                    '''
                }
            }
        }

        stage('Terraform Apply Approval') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                input message: 'Apply Terraform for shared EKS + S3 + IRSA?', ok: 'Apply'
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}"
                ]]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set -e
                            terraform apply -auto-approve tfplan
                        '''
                    }
                }
            }
        }

        stage('Terraform Destroy Approval') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                input message: 'Destroy Terraform resources?', ok: 'Destroy'
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}"
                ]]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set -e
                            terraform destroy -auto-approve
                        '''
                    }
                }
            }
        }

        stage('Load Terraform Outputs') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                script {
                    env.AWS_REGION_VALUE = sh(script: "cd ${TF_DIR} && terraform output -raw aws_region", returnStdout: true).trim()
                    env.CLUSTER_NAME_VALUE = sh(script: "cd ${TF_DIR} && terraform output -raw cluster_name", returnStdout: true).trim()
                    env.VPC_ID_VALUE = sh(script: "cd ${TF_DIR} && terraform output -raw vpc_id", returnStdout: true).trim()
                    env.S3_BUCKET_NAME_VALUE = sh(script: "cd ${TF_DIR} && terraform output -raw s3_bucket_name", returnStdout: true).trim()
                    env.MILVUS_IRSA_ROLE_ARN_VALUE = sh(script: "cd ${TF_DIR} && terraform output -raw milvus_irsa_role_arn", returnStdout: true).trim()
                }
            }
        }

        stage('Configure kubectl') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}"
                ]]) {
                    sh '''
                        set -e
                        aws eks update-kubeconfig --region ${AWS_REGION_VALUE} --name ${CLUSTER_NAME_VALUE}
                        kubectl config current-context
                        kubectl get nodes
                    '''
                }
            }
        }

        stage('Install AWS Load Balancer Controller') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}"
                ]]) {
                    sh '''
                        set -e

                        POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn | [0]" --output text)

                        if [ "$POLICY_ARN" = "None" ] || [ -z "$POLICY_ARN" ]; then
                          curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
                          POLICY_ARN=$(aws iam create-policy \
                            --policy-name AWSLoadBalancerControllerIAMPolicy \
                            --policy-document file://iam_policy.json \
                            --query 'Policy.Arn' \
                            --output text)
                        fi

                        eksctl utils associate-iam-oidc-provider \
                          --region ${AWS_REGION_VALUE} \
                          --cluster ${CLUSTER_NAME_VALUE} \
                          --approve

                        eksctl create iamserviceaccount \
                          --cluster=${CLUSTER_NAME_VALUE} \
                          --namespace=kube-system \
                          --name=aws-load-balancer-controller \
                          --attach-policy-arn=$POLICY_ARN \
                          --override-existing-serviceaccounts \
                          --region=${AWS_REGION_VALUE} \
                          --approve

                        helm repo add eks https://aws.github.io/eks-charts || true
                        helm repo update eks

                        wget -q https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml -O crds.yaml
                        kubectl apply -f crds.yaml

                        helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
                          -n kube-system \
                          --set clusterName=${CLUSTER_NAME_VALUE} \
                          --set serviceAccount.create=false \
                          --set serviceAccount.name=aws-load-balancer-controller \
                          --set region=${AWS_REGION_VALUE} \
                          --set vpcId=${VPC_ID_VALUE} \
                          --version 1.14.0

                        kubectl get deployment -n kube-system aws-load-balancer-controller
                    '''
                }
            }
        }

        stage('Create Namespace and StorageClass') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                sh '''
                    set -e
                    kubectl get namespace ${K8S_NAMESPACE} || kubectl create namespace ${K8S_NAMESPACE}
                    kubectl apply -f ${STORAGECLASS_FILE}
                '''
            }
        }

        stage('Render Milvus Values') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                sh '''
                    set -e
                    sed \
                      -e "s|__MILVUS_IRSA_ROLE_ARN__|${MILVUS_IRSA_ROLE_ARN_VALUE}|g" \
                      -e "s|__AWS_REGION__|${AWS_REGION_VALUE}|g" \
                      -e "s|__S3_BUCKET_NAME__|${S3_BUCKET_NAME_VALUE}|g" \
                      ${MILVUS_TEMPLATE_FILE} > ${MILVUS_RENDERED_FILE}

                    cat ${MILVUS_RENDERED_FILE}
                '''
            }
        }

        stage('Deploy Milvus') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                sh '''
                    set -e
                    helm repo add milvus https://zilliztech.github.io/milvus-helm/ || true
                    helm repo update

                    helm upgrade --install milvus-demo milvus/milvus \
                      -n ${K8S_NAMESPACE} \
                      -f ${MILVUS_RENDERED_FILE}
                '''
            }
        }

        stage('Verify Milvus') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_MILVUS }
                }
            }
            steps {
                sh '''
                    set -e
                    kubectl get pods -n ${K8S_NAMESPACE}
                    kubectl get svc -n ${K8S_NAMESPACE}
                '''
            }
        }
    }

    post {
        always {
            sh '''
                kubectl get pods -n ${K8S_NAMESPACE} || true
                kubectl get svc -n ${K8S_NAMESPACE} || true
            '''
        }
    }
}
