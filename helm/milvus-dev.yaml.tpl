cluster:
  enabled: true

service:
  type: LoadBalancer
  port: 19530
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"

serviceAccount:
  create: true
  name: milvus-s3-access-sa
  annotations:
    eks.amazonaws.com/role-arn: "__MILVUS_IRSA_ROLE_ARN__"

minio:
  enabled: false

externalS3:
  enabled: true
  host: "s3.__AWS_REGION__.amazonaws.com"
  port: "443"
  useSSL: true
  useIAM: true
  cloudProvider: "aws"
  region: "__AWS_REGION__"
  bucketName: "__S3_BUCKET_NAME__"

etcd:
  persistence:
    storageClassName: ebs-gp3-sc

pulsar:
  bookkeeper:
    volumes:
      journal:
        storageClassName: ebs-gp3-sc
      ledgers:
        storageClassName: ebs-gp3-sc
