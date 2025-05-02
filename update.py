#!/usr/bin/env -S nix develop .#update-script --command python
import tomlkit
import os
import subprocess
import json

script_dir = os.path.dirname(os.path.realpath(__file__))

with open(os.path.join(script_dir, "lock.toml"), "r") as f:
    lock = tomlkit.load(f)

version = lock["talos"]["version"]

images_by_ref = {}
for image, details in lock["talos"]["images"].items():
    images_by_ref[details["ref"]] = image

refs = [ref for ref in images_by_ref.keys()]
verify = subprocess.run([
  "cosign", "verify",
  "--certificate-identity-regexp", "@siderolabs\\.com$",
  "--certificate-oidc-issuer", "https://accounts.google.com",
  *map(lambda ref: f"{ref}:{version}", refs)
], check=True, encoding='utf-8', stdout=subprocess.PIPE)

verifications = []
for line in verify.stdout.splitlines():
    if line.strip() == "":
        continue

    verifications.extend(json.loads(line))

for verification in verifications:
    ref = verification["critical"]["identity"]["docker-reference"]
    digest = verification["critical"]["image"]["docker-manifest-digest"]
    lock["talos"]["images"][images_by_ref[ref]]["digest"] = digest

with open(os.path.join(script_dir, "lock.toml"), "w") as f:
    tomlkit.dump(lock, f)
