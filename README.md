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
```text
.
├── app/
│   ├── main.go
│   ├── go.mod
│   └── go.sum
├── infra/
│   └── template.yaml
├── test/
│   └── run-challenge-tests.sh
├── output/
│   └── (generated)
├── .github/
│   └── workflows/
│       ├── build.yaml
│       └── deploy.yaml
├── Dockerfile
└── README.md
```

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
- create it manually first (ECR repo is outside of CloudFormation scope here)
```bash
aws ecr create-repository \                            
  --repository-name "${STACK_NAME}" \                                                              
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_REGION}"
```

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


---


## Acceptance tests

`test/run-challenge-tests.sh` is a bash smoke test against a **deployed** stack. It uses the AWS CLI (same credentials as your terminal) and `curl`.

**What it checks**

1. CloudFormation stack is in a steady state and writes `describe-stacks` JSON under `output/`.
2. CloudFront URL: `GET /` without `?key=` → **400**.
3. CloudFront URL: `GET ?key=<missing object>` → **404** (requires Lambda role `s3:ListBucket` on the bucket so S3 returns “not found” instead of **403**).
4. Uploads a small object to `S3_BUCKET_NAME`, then `GET ?key=...` via CloudFront → **200** and body match.
5. Direct Lambda Function URL without SigV4 → **403** (`AWS_IAM`).

**Run** (from repo root; adjust exports to match your account):

```bash
chmod +x test/run-challenge-tests.sh
export AWS_REGION=ap-southeast-1
export CFN_STACK_NAME=secure-serverless-asset-proxy
export S3_BUCKET_NAME=your-bucket-name
export ECR_REPOSITORY=your-ecr-repo-name   # optional; echoed for parity
./test/run-challenge-tests.sh
```