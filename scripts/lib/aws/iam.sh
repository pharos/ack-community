#!/usr/bin/env bash

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$THIS_DIR/../../.."
SCRIPTS_DIR="$ROOT_DIR/scripts"

. $SCRIPTS_DIR/lib/common.sh
. $SCRIPTS_DIR/lib/aws.sh

# role_exists() returns 0 if a IAM role with the supplied name
# exists, 1 otherwise.
#
# Usage:
#
#   if ! role_exists "$role_name"; then
#       echo "IAM $role_name does not exist!"
#   fi
role_exists() {
    __repo_name="$1"
    daws iam get-role --role-name "$role_name" --output json >/dev/null 2>&1
    if [[ $? -eq 254 ]]; then
        return 1
    else
        return 0
    fi
}

# policy_exists() returns 0 if a IAM policy with the supplied arn
# exists, 1 otherwise.
#
# Usage:
#
#   if ! policy_exists "$policy_arn"; then
#       echo "IAM $policy_arn does not exist!"
#   fi
policy_exists() {
    __repo_name="$1"
    daws iam get-policy --policy-arn $policy_arn --output json >/dev/null 2>&1
    if [[ $? -eq 254 ]]; then
        return 1
    else
        return 0
    fi
}