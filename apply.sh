#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -a PLANS
mapfile -t PLANS < <(ls -1d "${BASEDIR}/plan-"*)

for PLAN in "${PLANS[@]}"; do
    cd "${PLAN}"
    [[ -s ./my.tfvars ]] && MYVARS="-var-file ./my.tfvars"
    terraform init -upgrade
    eval terraform apply "${MYVARS:-}" "${@}"
done