#!/usr/bin/env bash
# Functional tests for kms-vault against floci. Usage: test_suite.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TF="terraform -chdir=$ROOT/terraform output -raw"
API=$($TF api_id)
URL="http://$API.execute-api.localhost.floci.io:4566"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-southeast-7
KMS="aws kms --endpoint-url http://localhost:4566"
KEY_A=$(terraform -chdir=$ROOT/terraform output -json key_ids | python3 -c 'import json,sys;print(json.load(sys.stdin)["tenant_a"])')

pass=0; fail=0
post() { curl -s -m 60 -w '\n%{http_code}' -X POST "$URL$1" -H 'content-type: application/json' -d "$2"; }
body() { echo "$1" | sed '$d'; }
code() { echo "$1" | tail -1; }
jget() { python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('$2',''))" "$1"; }
check() { # name, ok(0/1), detail
  if [ "$2" = 0 ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  -> $3"; fi
}

R=$(post /encrypt '{"tenant":"a","record_id":"t1","plaintext":"secret-123"}')
check "1  encrypt returns 200" $([ "$(code "$R")" = 200 ] && echo 0 || echo 1) "$R"
R=$(post /decrypt '{"tenant":"a","id":"t1"}')
check "1  decrypt returns original plaintext" $([ "$(jget "$(body "$R")" plaintext)" = "secret-123" ] && echo 0 || echo 1) "$R"

R=$(post /decrypt '{"tenant":"b","id":"t1"}')
check "2  wrong tenant (encryption context) is refused" $([ "$(code "$R")" != 200 ] && echo 0 || echo 1) "$R"
echo "      -> $(code "$R") $(jget "$(body "$R")" error)"

OLD=$(post /encrypt '{"tenant":"a","record_id":"t4","plaintext":"before-rotate"}')
R=$(post /rotate/t4 '{"tenant":"a"}')
check "4  rotate returns 200" $([ "$(code "$R")" = 200 ] && echo 0 || echo 1) "$R"
R=$(post /decrypt '{"tenant":"a","id":"t4"}')
check "4  decrypt works after rotate" $([ "$(jget "$(body "$R")" plaintext)" = "before-rotate" ] && echo 0 || echo 1) "$R"

$KMS disable-key --key-id "$KEY_A" >/dev/null
R=$(post /decrypt '{"tenant":"a","id":"t1"}')
check "5  decrypt fails while key disabled" $([ "$(code "$R")" != 200 ] && echo 0 || echo 1) "$R"
echo "      -> $(code "$R") $(jget "$(body "$R")" error)"
$KMS enable-key --key-id "$KEY_A" >/dev/null
R=$(post /decrypt '{"tenant":"a","id":"t1"}')
check "5  decrypt works again after enable" $([ "$(jget "$(body "$R")" plaintext)" = "secret-123" ] && echo 0 || echo 1) "$R"

R=$(post /sign '{"message":"pay 100 to bob"}')
SIG=$(jget "$(body "$R")" signature)
check "6  sign returns signature" $([ -n "$SIG" ] && echo 0 || echo 1) "$R"
R=$(post /verify "{\"message\":\"pay 100 to bob\",\"signature\":\"$SIG\"}")
check "6  verify accepts original message" $([ "$(jget "$(body "$R")" valid)" = True ] && echo 0 || echo 1) "$R"
R=$(post /verify "{\"message\":\"pay 900 to bob\",\"signature\":\"$SIG\"}")
check "6  verify rejects tampered message" $([ "$(jget "$(body "$R")" valid)" != True ] && echo 0 || echo 1) "$R"

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
