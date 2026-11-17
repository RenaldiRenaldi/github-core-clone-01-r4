#!/bin/sh
set -eu
BASE=${BASE:-http://127.0.0.1:39041}
TOKEN=${MAKEFUN_SHOP_TOKEN:-forge-demo}
api(){ curl -fsS -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' "$@"; }
DIR=$(mktemp -d)
echo "Workspace: $DIR (fresh server required)"
api -X POST "$BASE/api/v3/user/repos" -d '{"name":"demo","auto_init":true}'
REMOTE=$(printf '%s' "$BASE" | sed "s|http://|http://demo:$TOKEN@|")/adaiversen/demo.git
git clone "$REMOTE" "$DIR/work"
cd "$DIR/work"
git config user.email demo@example.test
git config user.name Demo
git checkout -b feature
printf 'Fast, correct, native Go.\n' > feature.txt
git add feature.txt
git commit -m 'Demonstrate native Go smart HTTP'
git push origin feature
api -X PUT "$BASE/api/v3/repos/adaiversen/demo/branches/main/protection" -d '{"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true}}'
api -X POST "$BASE/api/v3/repos/adaiversen/demo/pulls" -d '{"title":"Native Go delivery","head":"feature","base":"main"}'
api -X POST "$BASE/api/v3/repos/adaiversen/demo/pulls/1/reviews" -d '{"event":"APPROVE","body":"Verified the file"}'
api -X PUT "$BASE/api/v3/repos/adaiversen/demo/pulls/1/merge" -d '{"merge_method":"squash"}'
git fetch origin
git show origin/main:feature.txt
curl -fsS "$BASE/adaiversen/demo" | head -c 100
printf '\nPASS: clone, push, review, protected merge, fetch and UI.\n'
