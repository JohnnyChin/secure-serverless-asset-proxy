# S3 Lambda CDN Challenge

A secure, automated AWS solution that retrieves private assets from S3 through a Go-based Lambda function and serves them globally via CloudFront.

---

## 🚀 Overview

This project demonstrates:

- Infrastructure as Code (CloudFormation)
- Secure private asset retrieval via Lambda
- Go backend using AWS SDK v2
- Lambda container deployment via ECR
- CloudFront CDN with Origin Access Control (OAC)
- GitHub Actions CI/CD with immutable deployments

---

## 🏗️ Architecture

User
↓
CloudFront (CDN)
↓
Lambda Function URL (AWS_IAM + SigV4 via OAC)
↓
Lambda (Go, container)
↓
Private S3 Bucket


---

## 🔄 Request Flow

1. Client sends request to CloudFront with `?key=...`
2. CloudFront checks cache
3. On cache miss → forwards request to Lambda Function URL
4. CloudFront signs request using SigV4 (OAC)
5. Lambda fetches object from private S3
6. Lambda returns object (base64-encoded)
7. CloudFront caches and returns response

---

## 🔐 Security Design

### Private S3 Bucket
- Fully private
- Public access blocked

### Least Privilege IAM
Lambda role allows only:
- `s3:GetObject`
- CloudWatch logging

### Protected Lambda URL
- No public access
- Only signed requests allowed

### CloudFront Origin Access Control (OAC)
- CloudFront signs all origin requests
- Prevents direct Lambda URL access

### Immutable Deployments
- No `latest` tag
- Uses commit SHA tags
- ECR repository set to immutable

---

## 📁 Repository Structure
.
├── app/
│ ├── main.go
│ ├── go.mod
│ └── go.sum
├── infra/
│ └── template.yaml
├── .github/
│ └── workflows/
│ ├── build.yml
│ └── deploy.yml
├── Dockerfile
└── README.md


---

## ⚙️ Prerequisites

- AWS Account
- AWS CLI v2
- Docker
- GitHub repository
- IAM permissions for:
  - Lambda
  - S3
  - ECR
  - CloudFront
  - IAM
  - CloudWatch


---


## One-time bootstrap

### 1. Create the ECR repo and initial stack prerequisites

You can either:
- create the ECR repository from the CloudFormation template after the first deploy, or
- create it manually first

### 2. Configure GitHub secrets

- AWS_ROLE_ARN
- AWS_REGION
- ECR_REPOSITORY
- CFN_STACK_NAME
- S3_BUCKET_NAME
- WORKFLOW_DISPATCH_TOKEN

## Deploy

Push to `main`.

The `build-and-push` workflow will:
- build the Go binary
- build and push an immutable image tagged with the Git commit SHA
- dispatch `deploy.yml`

The deploy workflow will:
- deploy/update the CloudFormation stack
- print stack outputs including the CloudFront domain name

## Upload a test object

```bash
aws s3 cp ./sample.png s3://$S3_BUCKET_NAME/assets/sample.png