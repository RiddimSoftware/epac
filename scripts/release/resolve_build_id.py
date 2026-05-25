#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time

import jwt
import requests

def get_asc_secret():
    env = os.environ.copy()
    env["AWS_PROFILE"] = os.environ.get("AWS_PROFILE", "riddim-agent")
    res = subprocess.run(
        [
            "aws", "secretsmanager", "get-secret-value", 
            "--secret-id", "appstore/connect-api", 
            "--region", "us-east-1", 
            "--query", "SecretString", 
            "--output", "text"
        ], 
        check=True, 
        capture_output=True, 
        text=True,
        env=env
    )
    secret = json.loads(res.stdout)
    return secret["key_id"], secret["issuer_id"], secret.get("key") or secret.get("private_key")

def get_token(key_id, issuer_id, key):
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": key_id})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    args = parser.parse_args()

    key_id, issuer_id, key = get_asc_secret()
    token = get_token(key_id, issuer_id, key)
    headers = {"Authorization": f"Bearer {token}"}
    
    url = "https://api.appstoreconnect.apple.com/v1/builds"
    params = {
        "filter[app]": args.app_id,
        "filter[version]": args.build_number,
        "fields[builds]": "version,processingState",
        "include": "preReleaseVersion",
        "limit": 50,
        "sort": "-uploadedDate"
    }
    
    # Retry logic just in case the build isn't instantly available in the API
    for attempt in range(5):
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        
        vmap = {
            inc["id"]: inc["attributes"]["version"] 
            for inc in data.get("included", []) 
            if inc.get("type") == "preReleaseVersions"
        }
        
        for b in data.get("data", []):
            prv_id = b.get("relationships", {}).get("preReleaseVersion", {}).get("data", {}).get("id")
            if vmap.get(prv_id) == args.version:
                out = os.environ.get("GITHUB_OUTPUT")
                if out:
                    with open(out, "a") as f:
                        f.write(f"build_id={b['id']}\n")
                print(b["id"])
                sys.exit(0)
        
        print(f"Build not found yet (attempt {attempt+1}/5). Waiting 15s...")
        time.sleep(15)
        
    print("Build not found after retries.")
    sys.exit(1)

if __name__ == "__main__":
    main()
