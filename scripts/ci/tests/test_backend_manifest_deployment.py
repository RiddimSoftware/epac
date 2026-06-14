import importlib.util
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "check_backend_manifest_deployment.py"


def load_module():
    spec = importlib.util.spec_from_file_location("check_backend_manifest_deployment", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FakeAws:
    def __init__(
        self,
        *,
        lambda_arn="arn:aws:lambda:us-east-1:123456789012:function:epac-bills-staging",
        variables=None,
        policy=None,
        objects=None,
    ):
        self.lambda_arn = lambda_arn
        self.variables = variables if variables is not None else {"EPAC_ARTIFACT_BUCKET": "bucket"}
        self.policy = policy if policy is not None else {
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "lambda:InvokeFunction",
                    "Principal": {"Service": "apigateway.amazonaws.com"},
                    "Condition": {"ArnLike": {"AWS:SourceArn": "arn:aws:execute-api:us-east-1:123456789012:api123/*/*"}},
                }
            ]
        }
        self.objects = objects if objects is not None else {"bills/v1/manifest.json", "bills/v1/index.sqlite"}

    def lambda_function(self, function_name):
        return {"Configuration": {"FunctionArn": self.lambda_arn}}

    def lambda_configuration(self, function_name):
        return {"Environment": {"Variables": self.variables}}

    def lambda_policy(self, function_name):
        return self.policy

    def object_exists(self, bucket, key):
        return key in self.objects


def test_select_s3_http_services_scopes_to_artifact_backed_http_services():
    checker = load_module()
    manifest = {
        "services": [
            {"name": "live-vote-poller", "deploy": {"staging": True}, "sync": {"staging": {"artifact": True}}},
            {
                "name": "bills",
                "deploy": {"staging": True},
                "http": {"payload_format_version": "1.0", "routes": {"staging": [{"method": "GET", "path": "/api/v1/bills"}]}},
                "sync": {"staging": {"artifact": True}},
            },
            {
                "name": "telemetry",
                "deploy": {"staging": True},
                "http": {"routes": {"staging": [{"method": "POST", "path": "/api/v1/telemetry"}]}},
                "sync": {"staging": {"artifact": False}},
            },
            {
                "name": "lobbying",
                "deploy": {"staging": True},
                "http": {"payload_format_version": "2.0", "routes": {"staging": [{"method": "GET", "path": "/api/v1/lobbying/organizations"}]}},
                "sync": {"staging": {"artifact": True}},
            },
        ]
    }

    selected = checker.select_s3_http_services(manifest, "staging")

    assert [service.name for service in selected] == ["bills", "lobbying"]
    assert selected[0].routes[0].payload_format_version == "1.0"


def test_unknown_s3_http_service_requires_an_explicit_contract():
    checker = load_module()
    manifest = {
        "services": [
            {
                "name": "new-artifact-service",
                "deploy": {"staging": True},
                "http": {"routes": {"staging": [{"method": "GET", "path": "/api/v1/new"}]}},
                "sync": {"staging": {"artifact": True}},
            }
        ]
    }

    with pytest.raises(checker.DeploymentCheckError, match="no artifact contract"):
        checker.select_s3_http_services(manifest, "staging")


def test_openapi_manifest_consistency_requires_documented_bills_diff_route():
    checker = load_module()
    openapi = {
        "paths": {
            "/api/v1/bills": {"get": {"tags": ["Bills"]}},
            "/api/v1/bills/{id}": {"get": {"tags": ["Bills"]}},
            "/api/v1/bills/{id}/committee-stage": {"get": {"tags": ["Bills"]}},
            "/api/v1/bills/{id}/diff": {"get": {"tags": ["Bills"]}},
            "/api/v1/bills/{legisinfo_id}/lobbying-context": {"get": {"tags": ["Bills", "Lobbying"]}},
        }
    }
    manifest = {
        "services": [
            {
                "name": "bills",
                "deploy": {"staging": True},
                "http": {
                    "routes": {
                        "staging": [
                            {"method": "GET", "path": "/api/v1/bills"},
                            {"method": "GET", "path": "/api/v1/bills/{id}"},
                            {"method": "GET", "path": "/api/v1/bills/{id}/committee-stage"},
                        ]
                    }
                },
            }
        ]
    }

    failures = checker.check_openapi_manifest_consistency(manifest, openapi, "staging")

    assert failures == [
        "bills: OpenAPI GET /api/v1/bills/{id}/diff is missing from staging deployment manifest"
    ]


def test_openapi_manifest_consistency_reports_method_or_path_drift():
    checker = load_module()
    openapi = {
        "paths": {
            "/api/v1/bills": {"get": {"tags": ["Bills"]}},
            "/api/v1/bills/{id}": {"get": {"tags": ["Bills"]}},
        }
    }
    manifest = {
        "services": [
            {
                "name": "bills",
                "deploy": {"production": True},
                "http": {
                    "routes": {
                        "production": [
                            {"method": "GET", "path": "/api/v1/bills"},
                            {"method": "POST", "path": "/api/v1/bills/{id}"},
                        ]
                    }
                },
            }
        ]
    }

    failures = checker.check_openapi_manifest_consistency(manifest, openapi, "production")

    assert failures == [
        "bills: OpenAPI GET /api/v1/bills/{id} is missing from production deployment manifest",
        "bills: manifest route POST /api/v1/bills/{id} is not documented by OpenAPI Bills service contract",
    ]


def test_policy_allows_api_gateway_when_source_arn_matches_api_id():
    checker = load_module()
    policy = {
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "lambda:InvokeFunction",
                "Principal": {"Service": "apigateway.amazonaws.com"},
                "Condition": {"ArnLike": {"AWS:SourceArn": "arn:aws:execute-api:us-east-1:123:api123/*/*"}},
            }
        ]
    }

    assert checker.policy_allows_api_gateway(policy, "api123")
    assert not checker.policy_allows_api_gateway(policy, "other-api")


def test_ready_check_passes_for_default_prefix_service_without_prefix_env(monkeypatch):
    checker = load_module()
    monkeypatch.delenv("BILLS_INDEX_PREFIX", raising=False)
    monkeypatch.delenv("EPAC_BILLS_INDEX_PREFIX", raising=False)
    service = checker.ServiceContract(
        name="bills",
        routes=(checker.RouteContract("GET", "/api/v1/bills", "1.0"),),
        artifact=checker.ARTIFACT_CONTRACTS["bills"],
    )
    lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:epac-bills-staging"
    routes = [{"RouteKey": "GET /api/v1/bills", "Target": "integrations/int1"}]
    integrations = [{"IntegrationId": "int1", "IntegrationUri": lambda_arn, "PayloadFormatVersion": "1.0"}]

    failures = checker.check_service(
        service,
        env_name="staging",
        api_id="api123",
        artifact_bucket="bucket",
        phase="ready",
        aws=FakeAws(lambda_arn=lambda_arn),
        routes=routes,
        integrations=integrations,
    )

    assert failures == []


def test_ready_check_requires_lobbying_prefix_env(monkeypatch):
    checker = load_module()
    monkeypatch.setenv("LOBBYING_INDEX_PREFIX", "lobbying-index/v1")
    service = checker.ServiceContract(
        name="lobbying",
        routes=(checker.RouteContract("GET", "/api/v1/lobbying/organizations", "2.0"),),
        artifact=checker.ARTIFACT_CONTRACTS["lobbying"],
    )
    lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:epac-lobbying-staging"
    routes = [{"RouteKey": "GET /api/v1/lobbying/organizations", "Target": "integrations/int1"}]
    integrations = [{"IntegrationId": "int1", "IntegrationUri": lambda_arn, "PayloadFormatVersion": "2.0"}]

    failures = checker.check_service(
        service,
        env_name="staging",
        api_id="api123",
        artifact_bucket="bucket",
        phase="ready",
        aws=FakeAws(
            lambda_arn=lambda_arn,
            variables={"EPAC_ARTIFACT_BUCKET": "bucket"},
            objects={"lobbying-index/v1/manifest.json", "lobbying-index/v1/index.sqlite"},
        ),
        routes=routes,
        integrations=integrations,
    )

    assert "lobbying: missing prefix env (LOBBYING_INDEX_PREFIX) for expected prefix 'lobbying-index/v1'" in failures


def test_route_payload_mismatch_is_reported():
    checker = load_module()
    service = checker.ServiceContract(
        name="bills",
        routes=(checker.RouteContract("GET", "/api/v1/bills", "1.0"),),
        artifact=checker.ARTIFACT_CONTRACTS["bills"],
    )
    failures = checker.check_routes(
        service,
        "api123",
        "arn:aws:lambda:us-east-1:123:function:epac-bills-staging",
        routes=[{"RouteKey": "GET /api/v1/bills", "Target": "integrations/int1"}],
        integrations=[
            {
                "IntegrationId": "int1",
                "IntegrationUri": "arn:aws:lambda:us-east-1:123:function:epac-bills-staging",
                "PayloadFormatVersion": "2.0",
            }
        ],
    )

    assert failures == ["bills: route GET /api/v1/bills payload format 2.0, want 1.0"]


def test_write_summary_writes_to_github_step_summary(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("NO_COLOR", "1")
    checker = load_module()
    summary_file = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

    service = checker.ServiceContract(
        name="bills",
        routes=(checker.RouteContract("GET", "/api/v1/bills", "1.0"),),
        artifact=checker.ARTIFACT_CONTRACTS["bills"],
    )

    checker.write_summary(
        env_name="staging",
        phase="ready",
        failures=["bills: missing prefix env"],
        checked=[service]
    )

    # Verify file was written
    assert summary_file.exists()
    content = summary_file.read_text(encoding="utf-8")
    assert "## Backend manifest deployment check (staging, ready)" in content
    assert "| bills | FAIL |" in content

    # Verify clean console stdout was printed
    captured = capsys.readouterr()
    assert "Backend manifest deployment check (staging, ready):" in captured.out
    assert "[FAIL] bills" in captured.out
    assert "Failures:" in captured.out
    assert "- bills: missing prefix env" in captured.out
    # Raw markdown table should NOT be in console stdout
    assert "| Service | Result |" not in captured.out
