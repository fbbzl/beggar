#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/deploy-registry-stack.sh"
passed=0

output=$(DRY_RUN=1 bash "$script" --mysql)
grep -Fq -- '--version 12.3.5' <<< "$output"
! grep -Fq 'nacos-group' <<< "$output"
printf 'PASS: default chart version and on-demand repo\n'
passed=$((passed + 1))

output=$(DRY_RUN=1 bash "$script" --mysql --version-overrides mysql=14.0.3)
grep -Fq -- '--version 14.0.3' <<< "$output"
printf 'PASS: chart version override\n'
passed=$((passed + 1))

if DRY_RUN=1 bash "$script" --mysql --version-overrides unknown=1.0 >/dev/null 2>&1; then
  printf 'FAIL: unknown component accepted\n' >&2
  exit 1
fi
if DRY_RUN=1 bash "$script" --mysql --version-overrides mysql=1.0,mysql=2.0 >/dev/null 2>&1; then
  printf 'FAIL: duplicate component accepted\n' >&2
  exit 1
fi
output=$(DRY_RUN=1 bash "$script" --flink --version-overrides flink=1.20.2)
grep -Fq 'flink.yaml (image tags flink=1.20.2)' <<< "$output"
output=$(DRY_RUN=1 bash "$script" --mysql --shardingsphere --version-overrides mysql=14.0.3,image-mysql=8.4)
grep -Fq -- 'mysql bitnami/mysql --version 14.0.3' <<< "$output"
grep -Fq 'shardingsphere.yaml (image tags mysql=8.4,shardingsphere=5.5.0)' <<< "$output"
printf 'PASS: native image override contract\n'
passed=$((passed + 1))

if DRY_RUN=1 bash "$script" --mysql --version-overrides 'mysql=bad;touch' >/dev/null 2>&1; then
  printf 'FAIL: unsafe version override accepted\n' >&2
  exit 1
fi
printf 'PASS: unsafe version override rejected\n'
passed=$((passed + 1))

output=$(DRY_RUN=1 bash "$script" --nacos --tdengine)
grep -Fq 'Nacos 暂不执行' <<< "$output"
grep -Fq 'TDengine 暂不执行' <<< "$output"
printf 'PASS: unavailable chart sources are explicit\n'
passed=$((passed + 1))

printf '%s version cases passed.\n' "$passed"
