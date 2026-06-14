#!/usr/bin/env python3
"""Verify deployed EPAC backend services against deployment-services.json.

V1 intentionally covers the current S3-backed HTTP Lambda shape:
manifest-deployed services with ``http`` routes and ``sync.<env>.artifact``.
It is a deployment contract checker, not an infrastructure state manager.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_REGION = "us-east-1"
DEFAULT_ARTIFACT_BUCKET = "epac-artifacts-227530433709"
OPENAPI_HTTP_METHODS = {"get", "post", "put", "patch", "delete", "head", "options"}
OPENAPI_MANIFEST_TAG_CONTRACTS = {
    "bills": "Bills",
}


class DeploymentCheckError(Exception):
    """Raised when an AWS read fails unexpectedly."""


@dataclass(frozen=True)
class ArtifactContract:
    env_names: tuple[str, ...]
    default_prefix: str
    required_files: tuple[str, ...] = ("manifest.json", "index.sqlite")
    require_prefix_env: bool = False


ARTIFACT_CONTRACTS: dict[str, ArtifactContract] = {
    "bills": ArtifactContract(("BILLS_INDEX_PREFIX", "EPAC_BILLS_INDEX_PREFIX"), "bills/v1"),
    "members": ArtifactContract(("MEMBERS_INDEX_PREFIX", "EPAC_MEMBERS_INDEX_PREFIX"), "members/v1"),
    "hansard-search": ArtifactContract(("EPAC_HANSARD_SEARCH_PREFIX",), "hansard-search/v1"),
    "lobbying": ArtifactContract(("LOBBYING_INDEX_PREFIX",), "lobbying-index/v1", require_prefix_env=True),
    "senators": ArtifactContract(("EPAC_SENATORS_PREFIX",), "senators/v1", required_files=("all.json",)),
}


@dataclass(frozen=True)
class RouteContract:
    method: str
    path: str
    payload_format_version: str

    @property
    def key(self) -> str:
        return f"{self.method} {self.path}"


@dataclass(frozen=True)
class ServiceContract:
    name: str
    routes: tuple[RouteContract, ...]
    artifact: ArtifactContract

    @property
    def source_path(self) -> Path:
        return repo_root() / "backend" / self.name / "go.mod"

    def function_name(self, env_name: str) -> str:
        return f"epac-{self.name}-{env_name}"


class AwsClient:
    def __init__(self, region: str) -> None:
        self.region = region

    def _run(self, args: list[str], *, allow_failure: bool = False) -> str:
        result = subprocess.run(
            ["aws", *args],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            if allow_failure:
                return ""
            stderr = (result.stderr or result.stdout).strip()
            raise DeploymentCheckError(f"aws {' '.join(args)} failed: {stderr}")
        return result.stdout

    def _json(self, args: list[str], *, allow_failure: bool = False) -> Any:
        raw = self._run(args + ["--output", "json"], allow_failure=allow_failure)
        if not raw.strip():
            return None
        return json.loads(raw)

    def lambda_function(self, function_name: str) -> dict[str, Any] | None:
        return self._json(["lambda", "get-function", "--function-name", function_name], allow_failure=True)

    def lambda_configuration(self, function_name: str) -> dict[str, Any] | None:
        return self._json(
            ["lambda", "get-function-configuration", "--function-name", function_name],
            allow_failure=True,
        )

    def lambda_policy(self, function_name: str) -> dict[str, Any] | None:
        response = self._json(["lambda", "get-policy", "--function-name", function_name], allow_failure=True)
        if not response:
            return None
        policy = response.get("Policy")
        if isinstance(policy, str):
            return json.loads(policy)
        if isinstance(policy, dict):
            return policy
        return None

    def routes(self, api_id: str) -> list[dict[str, Any]]:
        data = self._json(["apigatewayv2", "get-routes", "--api-id", api_id])
        return list(data.get("Items", []))

    def integrations(self, api_id: str) -> list[dict[str, Any]]:
        data = self._json(["apigatewayv2", "get-integrations", "--api-id", api_id])
        return list(data.get("Items", []))

    def object_exists(self, bucket: str, key: str) -> bool:
        result = subprocess.run(
            ["aws", "s3api", "head-object", "--bucket", bucket, "--key", key],
            check=False,
            capture_output=True,
            text=True,
        )
        return result.returncode == 0


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_openapi(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def check_openapi_manifest_consistency(
    manifest: dict[str, Any],
    openapi: dict[str, Any],
    env_name: str,
    service_filter: set[str] | None = None,
) -> list[str]:
    failures: list[str] = []
    for service_name, openapi_tag in OPENAPI_MANIFEST_TAG_CONTRACTS.items():
        if service_filter is not None and service_name not in service_filter:
            continue
        service = next((item for item in manifest.get("services", []) if item.get("name") == service_name), None)
        if service is None or service.get("deploy", {}).get(env_name) is not True:
            continue

        documented_routes = openapi_routes_for_exclusive_tag(openapi, openapi_tag)
        manifest_routes = {
            (str(route.get("method", "")).upper(), str(route.get("path", "")))
            for route in service.get("http", {}).get("routes", {}).get(env_name, [])
        }

        for method, path in sorted(documented_routes - manifest_routes):
            failures.append(
                f"{service_name}: OpenAPI {method} {path} is missing from {env_name} deployment manifest"
            )
        for method, path in sorted(manifest_routes - documented_routes):
            failures.append(
                f"{service_name}: manifest route {method} {path} is not documented by OpenAPI {openapi_tag} service contract"
            )
    return failures


def openapi_routes_for_exclusive_tag(openapi: dict[str, Any], tag: str) -> set[tuple[str, str]]:
    routes: set[tuple[str, str]] = set()
    paths = openapi.get("paths", {})
    if not isinstance(paths, dict):
        return routes
    for path, operations in paths.items():
        if not isinstance(path, str) or not isinstance(operations, dict):
            continue
        for method, operation in operations.items():
            method_name = str(method).lower()
            if method_name not in OPENAPI_HTTP_METHODS or not isinstance(operation, dict):
                continue
            tags = operation.get("tags", [])
            if isinstance(tags, list) and set(tags) == {tag}:
                routes.add((method_name.upper(), path))
    return routes


def select_s3_http_services(
    manifest: dict[str, Any],
    env_name: str,
    service_filter: set[str] | None = None,
) -> list[ServiceContract]:
    services: list[ServiceContract] = []
    for service in manifest.get("services", []):
        name = service.get("name", "")
        if service_filter is not None and name not in service_filter:
            continue
        if service.get("deploy", {}).get(env_name) is not True:
            continue
        if not service.get("http"):
            continue
        if service.get("sync", {}).get(env_name, {}).get("artifact") is not True:
            continue
        artifact = ARTIFACT_CONTRACTS.get(name)
        if artifact is None:
            raise DeploymentCheckError(
                f"{name}: S3 HTTP service is selected but has no artifact contract in "
                "scripts/ci/check_backend_manifest_deployment.py"
            )
        payload_version = str(service["http"].get("payload_format_version", "2.0"))
        routes = tuple(
            RouteContract(
                method=str(route["method"]),
                path=str(route["path"]),
                payload_format_version=payload_version,
            )
            for route in service["http"].get("routes", {}).get(env_name, [])
        )
        services.append(ServiceContract(name=name, routes=routes, artifact=artifact))
    return services


def parse_service_filter(raw: str) -> set[str] | None:
    raw = raw.strip()
    if not raw or raw == "all":
        return None
    return {part.strip() for part in raw.split(",") if part.strip()}


def expected_prefix(contract: ArtifactContract) -> str:
    for env_name in contract.env_names:
        value = os.environ.get(env_name, "").strip().strip("/")
        if value:
            return value
    return contract.default_prefix


def check_service(
    service: ServiceContract,
    *,
    env_name: str,
    api_id: str,
    artifact_bucket: str,
    phase: str,
    aws: AwsClient,
    routes: list[dict[str, Any]],
    integrations: list[dict[str, Any]],
) -> list[str]:
    failures: list[str] = []
    if not service.source_path.exists():
        failures.append(f"{service.name}: source missing at {service.source_path.relative_to(repo_root())}")

    function_name = service.function_name(env_name)
    function = aws.lambda_function(function_name)
    if not function:
        failures.append(f"{service.name}: Lambda {function_name} does not exist")
        return failures

    config = function.get("Configuration", {})
    lambda_arn = config.get("FunctionArn")
    if not lambda_arn:
        failures.append(f"{service.name}: Lambda {function_name} did not return FunctionArn")
        return failures

    route_failures = check_routes(service, api_id, str(lambda_arn), routes, integrations)
    failures.extend(route_failures)

    policy = aws.lambda_policy(function_name)
    if not policy_allows_api_gateway(policy, api_id):
        failures.append(f"{service.name}: Lambda policy does not allow API Gateway {api_id} to invoke {function_name}")

    if phase == "ready":
        runtime_config = aws.lambda_configuration(function_name) or {}
        variables = runtime_config.get("Environment", {}).get("Variables", {}) or {}
        failures.extend(check_runtime_env(service, variables, artifact_bucket))
        failures.extend(check_artifacts(service, artifact_bucket, aws))

    return failures


def check_routes(
    service: ServiceContract,
    api_id: str,
    lambda_arn: str,
    routes: list[dict[str, Any]],
    integrations: list[dict[str, Any]],
) -> list[str]:
    failures: list[str] = []
    integrations_by_id = {item.get("IntegrationId"): item for item in integrations}
    routes_by_key = {item.get("RouteKey"): item for item in routes}

    for route in service.routes:
        api_route = routes_by_key.get(route.key)
        if not api_route:
            failures.append(f"{service.name}: API {api_id} route {route.key} is missing")
            continue

        target = str(api_route.get("Target", ""))
        integration_id = target.removeprefix("integrations/")
        if not target.startswith("integrations/") or not integration_id:
            failures.append(f"{service.name}: route {route.key} target is not an integration: {target}")
            continue

        integration = integrations_by_id.get(integration_id)
        if not integration:
            failures.append(f"{service.name}: route {route.key} integration {integration_id} is missing")
            continue

        if integration.get("IntegrationUri") != lambda_arn:
            failures.append(
                f"{service.name}: route {route.key} points to {integration.get('IntegrationUri')}, want {lambda_arn}"
            )
        actual_payload = str(integration.get("PayloadFormatVersion", "2.0"))
        if actual_payload != route.payload_format_version:
            failures.append(
                f"{service.name}: route {route.key} payload format {actual_payload}, "
                f"want {route.payload_format_version}"
            )
    return failures


def check_runtime_env(service: ServiceContract, variables: dict[str, str], artifact_bucket: str) -> list[str]:
    failures: list[str] = []
    actual_bucket = variables.get("EPAC_ARTIFACT_BUCKET", "")
    if actual_bucket != artifact_bucket:
        failures.append(f"{service.name}: EPAC_ARTIFACT_BUCKET={actual_bucket!r}, want {artifact_bucket!r}")

    if "DATABASE_URL" in variables:
        failures.append(f"{service.name}: DATABASE_URL is present on an S3 artifact service")

    want_prefix = expected_prefix(service.artifact)
    found_prefix = ""
    found_name = ""
    for env_name in service.artifact.env_names:
        value = variables.get(env_name, "").strip().strip("/")
        if value:
            found_prefix = value
            found_name = env_name
            break

    if found_prefix and found_prefix != want_prefix:
        failures.append(f"{service.name}: {found_name}={found_prefix!r}, want {want_prefix!r}")
    if not found_prefix and (service.artifact.require_prefix_env or want_prefix != service.artifact.default_prefix):
        names = ", ".join(service.artifact.env_names)
        failures.append(f"{service.name}: missing prefix env ({names}) for expected prefix {want_prefix!r}")

    return failures


def check_artifacts(service: ServiceContract, artifact_bucket: str, aws: AwsClient) -> list[str]:
    failures: list[str] = []
    prefix = expected_prefix(service.artifact).strip("/")
    for filename in service.artifact.required_files:
        key = f"{prefix}/{filename}"
        if not aws.object_exists(artifact_bucket, key):
            failures.append(f"{service.name}: missing artifact s3://{artifact_bucket}/{key}")
    return failures


def policy_allows_api_gateway(policy: dict[str, Any] | None, api_id: str) -> bool:
    if not policy:
        return False
    statements = policy.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]
    for statement in statements:
        if statement.get("Effect") != "Allow":
            continue
        if not action_allows_invoke(statement.get("Action")):
            continue
        if not principal_is_api_gateway(statement.get("Principal")):
            continue
        condition = statement.get("Condition")
        if not condition:
            return True
        values = condition_values(condition)
        if any(api_id in value for value in values):
            return True
    return False


def action_allows_invoke(action: Any) -> bool:
    if isinstance(action, str):
        return action in {"lambda:InvokeFunction", "lambda:*", "*"}
    if isinstance(action, list):
        return any(action_allows_invoke(item) for item in action)
    return False


def principal_is_api_gateway(principal: Any) -> bool:
    if principal == "*":
        return True
    if isinstance(principal, str):
        return principal == "apigateway.amazonaws.com"
    if isinstance(principal, dict):
        service = principal.get("Service")
        if isinstance(service, str):
            return service == "apigateway.amazonaws.com"
        if isinstance(service, list):
            return "apigateway.amazonaws.com" in service
    return False


def condition_values(condition: Any) -> list[str]:
    values: list[str] = []
    if isinstance(condition, str):
        return [condition]
    if isinstance(condition, list):
        for item in condition:
            values.extend(condition_values(item))
    elif isinstance(condition, dict):
        for value in condition.values():
            values.extend(condition_values(value))
    return values


def write_summary(env_name: str, phase: str, failures: list[str], checked: list[ServiceContract]) -> None:
    lines = [
        f"## Backend manifest deployment check ({env_name}, {phase})",
        "",
        "| Service | Result |",
        "|---|---|",
    ]
    failed_services = {failure.split(":", 1)[0] for failure in failures}
    for service in checked:
        result = "FAIL" if service.name in failed_services else "PASS"
        lines.append(f"| {service.name} | {result} |")
    if failures:
        lines.extend(["", "### Failures", ""])
        lines.extend(f"- {failure}" for failure in failures)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    print("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("staging", "production"), required=True)
    parser.add_argument("--api-id", required=True)
    parser.add_argument("--artifact-bucket", default=os.environ.get("EPAC_ARTIFACT_BUCKET", DEFAULT_ARTIFACT_BUCKET))
    parser.add_argument("--manifest", type=Path, default=repo_root() / "backend" / "manifest" / "deployment-services.json")
    parser.add_argument("--openapi", type=Path, default=repo_root() / "backend" / "openapi" / "openapi.json")
    parser.add_argument("--phase", choices=("topology", "ready"), default="ready")
    parser.add_argument("--scope", choices=("s3-http",), default="s3-http")
    parser.add_argument("--services", default=os.environ.get("EPAC_BACKEND_MANIFEST_SERVICES", "all"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", DEFAULT_REGION))
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    openapi = load_openapi(args.openapi)
    service_filter = parse_service_filter(args.services)
    services = select_s3_http_services(
        manifest,
        args.environment,
        service_filter=service_filter,
    )
    if not services:
        print(f"No {args.environment} {args.scope} services selected.")
        return 0

    failures = check_openapi_manifest_consistency(manifest, openapi, args.environment, service_filter)
    if failures:
        write_summary(args.environment, args.phase, failures, services)
        for failure in failures:
            print(f"::error::{failure}", file=sys.stderr)
        return 1

    aws = AwsClient(args.region)
    routes = aws.routes(args.api_id)
    integrations = aws.integrations(args.api_id)

    failures: list[str] = []
    for service in services:
        failures.extend(
            check_service(
                service,
                env_name=args.environment,
                api_id=args.api_id,
                artifact_bucket=args.artifact_bucket,
                phase=args.phase,
                aws=aws,
                routes=routes,
                integrations=integrations,
            )
        )

    write_summary(args.environment, args.phase, failures, services)
    for failure in failures:
        print(f"::error::{failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
