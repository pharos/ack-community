#!/usr/bin/env bash

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$THIS_DIR/../../.."
SCRIPTS_DIR="$ROOT_DIR/scripts"

source "$SCRIPTS_DIR/lib/common.sh"
source "$SCRIPTS_DIR/lib/k8s.sh"
source "$SCRIPTS_DIR/lib/aws/iam.sh"
source "$SCRIPTS_DIR/lib/testutil.sh"

test_name="$( filenoext "${BASH_SOURCE[0]}" )"
service_name="iam"
ack_ctrl_pod_id=$( controller_pod_id )
debug_msg "executing test: $service_name/$test_name"

role_name="ack-test-smoke-role-$service_name"
# TODO: the roles SDK resource clashes with the RBAC roles resource
resource_role_name="roles.iam.services.k8s.aws/$role_name"

policy_name="ack-test-smoke-policy-$service_name"
resource_policy_name="policies.iam.services.k8s.aws/$policy_name"
policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name"

# PRE-CHECKS
if role_exists "$role_name"; then
    echo "FAIL: expected $role_name to not exist in IAM roles. Did previous test run cleanup?"
    exit 1
fi

if k8s_resource_exists "$resource_role_name"; then
    echo "FAIL: expected $resource_role_name to not exist. Did previous test run cleanup?"
    exit 1
fi

if policy_exists "$policy_arn"; then
    echo "FAIL: expected $policy_arn to not exist in IAM roles. Did previous test run cleanup?"
    exit 1
fi

if k8s_resource_exists "$resource_policy_name"; then
    echo "FAIL: expected $resource_policy_name to not exist. Did previous test run cleanup?"
    exit 1
fi

# CREATE/UPDATE ROLE

cat <<EOF | kubectl apply -f -
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Role
metadata:
  name: $role_name
  annotations:
    iam.amazonaws.com/irsa-service-account: $role_name
spec:
  assumeRolePolicyDocument: >
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "$ACK_TEST_PRINCIPAL_ARN"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  roleName: $role_name
EOF

sleep 20

debug_msg "checking role $role_name created in IAM"
if ! role_exists "$role_name"; then
    echo "FAIL: expected $role_name to have been created in IAM"
    kubectl logs -n ack-system "$ack_ctrl_pod_id"
    exit 1
fi

cat <<EOF | kubectl apply -f -
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Role
metadata:
  name: $role_name
  annotations:
    iam.amazonaws.com/irsa-service-account: $role_name
spec:
  assumeRolePolicyDocument: >
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "$ACK_TEST_PRINCIPAL_ARN"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  description: "Smoke test role description"
  permissionsBoundary: arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
  roleName: $role_name
EOF

sleep 5

debug_msg "checking role $role_name has been updated"
aws_return=$(daws iam get-role --role-name $role_name | jq -r '.Role.Description')
assert_equal "Smoke test role description" "$aws_return" "Expected $role_name to have description" || exit 1
aws_return=$(daws iam get-role --role-name $role_name | jq -r '.Role.PermissionsBoundary.PermissionsBoundaryArn')
assert_equal "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess" "$aws_return" "Expected $role_name to have permission boundary" || exit 1

## CREATE MANAGED POLICY

cat <<EOF | kubectl apply -f -
apiVersion: iam.services.k8s.aws/v1alpha1
kind: Policy
metadata:
  name: $policy_name
spec:
  policyDocument: >
    {
      "Version": "2012-10-17",
      "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords",
                "xray:GetSamplingRules",
                "xray:GetSamplingTargets",
                "xray:GetSamplingStatisticSummaries"
            ],
            "Resource": [ "*" ]
        }
      ]
    }
  policyName: $policy_name
EOF

debug_msg "checking policy $policy_arn created in IAM"
if ! policy_exists "$policy_arn"; then
    echo "FAIL: expected $policy_arn to have been created in IAM"
    kubectl logs -n ack-system "$ack_ctrl_pod_id"
    exit 1
fi

## ATTACH/DEATTACH MANAGED POLICY to ROLE

cat <<EOF | kubectl apply -f -
apiVersion: iam.services.k8s.aws/v1alpha1
kind: RolePolicyAttachment
metadata:
  name: $policy_name
spec:
  roleName: $role_name
  policyARN: $policy_arn
EOF

debug_msg "checking policy $policy_name is attached to role $role_name"
aws_return=$(daws iam list-attached-role-policies --role-name $role_name | jq -r '.AttachedPolicies[0].PolicyName')
assert_equal "$policy_name" "$aws_return" "Expected $role_name to have attached policy $policy_name" || exit 1

kubectl delete "rolepolicyattachment.iam.services.k8s.aws/$policy_name" 2>/dev/null
assert_equal "0" "$?" "Expected success from kubectl delete but got $?" || exit 1

## INLNE ROLE POLICY




## CLEAN UP

kubectl delete "$resource_policy_name" 2>/dev/null
assert_equal "0" "$?" "Expected success from kubectl delete but got $?" || exit 1

if policy_exists "$policy_arn"; then
    echo "FAIL: expected $policy_name to be deleted in IAM"
    kubectl logs -n ack-system "$ack_ctrl_pod_id"
    exit 1
fi

kubectl delete "$resource_role_name" 2>/dev/null
assert_equal "0" "$?" "Expected success from kubectl delete but got $?" || exit 1

if role_exists "$role_name"; then
    echo "FAIL: expected $role_name to be deleted in IAM"
    kubectl logs -n ack-system "$ack_ctrl_pod_id"
    exit 1
fi

assert_pod_not_restarted $ack_ctrl_pod_id