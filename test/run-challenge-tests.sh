#!/usr/bin/env bash
#
# =============================================================================
# Secure Serverless Asset Proxy (challenge acceptance tests for s3-lambda-cdn-challenge)
# =============================================================================
#
# What this script exercises:
#   1. CloudFormation stack describable; JSON written under output/
#   2. CloudFront: GET without ?key= → 400
#   3. CloudFront: GET ?key=<missing object> → 404
#   4. CloudFront: GET ?key=<uploaded test object> → 200 + body
#   5. Direct Lambda Function URL without SigV4 → 403 (AWS_IAM)
#
# Env (defaults below; export to override):
#   AWS_REGION, CFN_STACK_NAME, S3_BUCKET_NAME, ECR_REPOSITORY
#   CF_DOMAIN, LAMBDA_FUNCTION_URL — optional overrides
#   TEST_OBJECT_KEY — default challenge-test/hello.txt
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${OUTPUT_DIR}/challenge-test-${RUN_ID}.log"

export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export CFN_STACK_NAME="${CFN_STACK_NAME:-secure-serverless-asset-proxy}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME:-johnny-s3-lambda-cdn-challenge-mar2026}"
export ECR_REPOSITORY="${ECR_REPOSITORY:-secure-serverless-asset-proxy}"
export CF_DOMAIN="${CF_DOMAIN:-}"
export LAMBDA_FUNCTION_URL="${LAMBDA_FUNCTION_URL:-}"
export TEST_OBJECT_KEY="${TEST_OBJECT_KEY:-challenge-test/hello.txt}"
export TEST_OBJECT_BODY="${TEST_OBJECT_BODY:-hello from challenge test ${RUN_ID}}"

PASSED=0
FAILED=0
pass() { echo "PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED + 1)); }

mkdir -p "${OUTPUT_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "Challenge tests — ${RUN_ID} | log: ${LOG_FILE}"
echo "AWS_REGION=${AWS_REGION} CFN_STACK_NAME=${CFN_STACK_NAME} S3_BUCKET_NAME=${S3_BUCKET_NAME} ECR_REPOSITORY=${ECR_REPOSITORY}"

echo "[1] CloudFormation → output/"
aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" --output json \
  > "${OUTPUT_DIR}/cfn-stack-describe-${RUN_ID}.json"
aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
  --query 'Stacks[0].Outputs' --output json \
  > "${OUTPUT_DIR}/cfn-stack-outputs-${RUN_ID}.json"
cp -f "${OUTPUT_DIR}/cfn-stack-describe-${RUN_ID}.json" "${OUTPUT_DIR}/cfn-stack-describe.json"
cp -f "${OUTPUT_DIR}/cfn-stack-outputs-${RUN_ID}.json" "${OUTPUT_DIR}/cfn-stack-outputs.json"

STACK_STATUS="$(aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
  --query 'Stacks[0].StackStatus' --output text)"
if [[ "${STACK_STATUS}" == CREATE_COMPLETE ]] || [[ "${STACK_STATUS}" == UPDATE_COMPLETE ]]; then
  pass "stack status ${STACK_STATUS}"
else
  fail "stack status ${STACK_STATUS}"
fi

[[ -z "${CF_DOMAIN}" ]] && CF_DOMAIN="$(aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" --output text)"
[[ -z "${LAMBDA_FUNCTION_URL}" ]] && LAMBDA_FUNCTION_URL="$(aws cloudformation describe-stacks --stack-name "${CFN_STACK_NAME}" --region "${AWS_REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionUrl'].OutputValue" --output text)"

if [[ -z "${CF_DOMAIN}" || "${CF_DOMAIN}" == "None" ]]; then
  fail "empty CloudFrontDomainName"; echo "Passed ${PASSED} Failed ${FAILED}"; exit 1
fi

CF_BASE_URL="https://${CF_DOMAIN}"
http_code() { curl -sS -o /dev/null -w "%{http_code}" -L --max-time 30 "$1"; }
body_file="$(mktemp)"; trap 'rm -f "${body_file}"' EXIT

echo "[2] GET / → 400"
c="$(http_code "${CF_BASE_URL}/")"; [[ "$c" == "400" ]] && pass "GET / → $c" || fail "GET / → $c (want 400)"

echo "[3] missing key → 404"
c="$(http_code "${CF_BASE_URL}/?key=nonexistent-${RUN_ID}.txt")"; [[ "$c" == "404" ]] && pass "missing object → $c" || fail "missing object → $c (want 404)"

echo "[4] upload + GET → 200"
printf '%s' "${TEST_OBJECT_BODY}" | aws s3 cp - "s3://${S3_BUCKET_NAME}/${TEST_OBJECT_KEY}" --region "${AWS_REGION}"
curl -sS -o "${body_file}" "${CF_BASE_URL}/?key=${TEST_OBJECT_KEY}"
c="$(http_code "${CF_BASE_URL}/?key=${TEST_OBJECT_KEY}")"
[[ "$c" == "200" ]] && grep -qF "${TEST_OBJECT_BODY}" "${body_file}" && pass "object round-trip" || fail "round-trip code=$c"

echo "[5] Lambda URL direct → 403"
if [[ -n "${LAMBDA_FUNCTION_URL}" && "${LAMBDA_FUNCTION_URL}" != "None" ]]; then
  c="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 30 "${LAMBDA_FUNCTION_URL}")"
  [[ "$c" == "403" ]] && pass "Lambda URL $c" || fail "Lambda URL $c (want 403)"
else
  fail "empty LambdaFunctionUrl"
fi

echo "Done. Log: ${LOG_FILE} | Passed: ${PASSED} Failed: ${FAILED}"
[[ "${FAILED}" -eq 0 ]] || exit 1