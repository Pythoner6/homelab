go mod tidy

cat <<EOF > main.go
package main

import (
$(go list k8s.io/api/... | awk '{print "  _ \"" $0 "\""}')
  _ "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
  _ "k8s.io/apimachinery/pkg/types"
)
EOF

go mod tidy
tmp=$(mktemp -d)
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
go mod vendor -o "$tmp"
jq -n --arg hash "$(nix-hash --sri --type sha256 "$tmp")" '{hash: $hash}' > vendor.json
