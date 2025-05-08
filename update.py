#!/usr/bin/env -S nix develop .#update-script --command python
import tomlkit
import os
import subprocess
import json
from git.repo.base import Repo
import tempfile
import shutil

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

with tempfile.TemporaryDirectory() as repo_dir:
  repo = Repo.init(repo_dir)
  origin = repo.create_remote("origin", f"https://github.com/{lock["talos"]["talosctl"]["package"]}.git")
  origin.fetch(version, depth=1)
  repo.git.checkout("FETCH_HEAD")
  repo.close()
  shutil.rmtree(os.path.join(repo_dir, ".git"))

  hash = subprocess.run([
    "nix-hash", "--sri", "--type", "sha256", repo_dir
  ], check=True, encoding='utf-8', stdout=subprocess.PIPE)
  lock["talos"]["talosctl"]["srcHash"] = hash.stdout.strip()
  lock["talos"]["imager"]["srcHash"] = hash.stdout.strip()

  # TODO: because this can depend on the environment, this is
  #       not as reproducible as I'd like...
  vendor_env = os.environ.copy()
  vendor_env['GOWORK'] = 'off'
  vendor = subprocess.run([
    "go", "mod", "vendor"
  ], env=vendor_env, cwd=repo_dir, check=True)
  hash = subprocess.run([
    "nix-hash", "--sri", "--type", "sha256", os.path.join(repo_dir, "vendor")
  ], check=True, encoding='utf-8', stdout=subprocess.PIPE)

  lock["talos"]["talosctl"]["vendorHash"] = hash.stdout.strip()
  lock["talos"]["imager"]["vendorHash"] = hash.stdout.strip()

with open(os.path.join(script_dir, "lock.toml"), "w") as f:
    tomlkit.dump(lock, f)
