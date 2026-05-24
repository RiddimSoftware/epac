"""S3 publishing helpers for backend statistics pipelines."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from typing import Protocol


ARTIFACT_PREFIX = "statistics/v1"
BUCKET_ENV_VAR = "ARTIFACTS_BUCKET"
CACHE_CONTROL = "public,max-age=31536000,immutable"
CONTENT_TYPE = "application/json"

CONTEXT_FIELDS = (
    "generated_at",
    "source",
    "sources",
    "datasets",
    "statcan_tables",
    "reference_month",
    "reference_fiscal_year",
    "reference_academic_year",
    "tuition_reference_year",
    "history_years",
)


class S3Client(Protocol):
    def put_object(self, **kwargs: object) -> object:
        """Upload one object to S3."""


@dataclass(frozen=True)
class PublishedArtifact:
    key: str
    content_hash_sha256: str
    size_bytes: int


def statistics_artifact_key(pipeline_name: str, dataset_name: str) -> str:
    return f"{ARTIFACT_PREFIX}/{pipeline_name}/{dataset_name}.json"


def build_statistics_datasets(payload: object) -> dict[str, object]:
    datasets = {"all": payload}
    if not isinstance(payload, dict):
        return datasets

    context = {key: payload[key] for key in CONTEXT_FIELDS if key in payload}

    if isinstance(payload.get("national"), dict):
        datasets["national"] = {**context, "national": payload["national"]}
    if isinstance(payload.get("national_summary"), dict):
        datasets["national"] = {**context, "national_summary": payload["national_summary"]}

    _add_province_datasets(datasets, context, payload.get("provinces"))

    road = payload.get("road")
    if isinstance(road, dict):
        if isinstance(road.get("national"), list):
            datasets["road-national"] = {**context, "road": {"national": road["national"]}}
        _add_province_datasets(datasets, context, road.get("provinces"), dataset_prefix="road-province")

    return datasets


def publish_statistics_payload(
    pipeline_name: str,
    payload: object,
    *,
    bucket: str | None = None,
    s3_client: S3Client | None = None,
    datasets: dict[str, object] | None = None,
) -> list[PublishedArtifact]:
    target_bucket = bucket or os.getenv(BUCKET_ENV_VAR)
    if not target_bucket:
        raise ValueError(f"S3 bucket is required: pass --s3-bucket or set {BUCKET_ENV_VAR}")

    client = s3_client or _default_s3_client()
    published: list[PublishedArtifact] = []
    for dataset_name, dataset_payload in (datasets or build_statistics_datasets(payload)).items():
        body = _json_body(dataset_payload)
        content_hash = hashlib.sha256(body).hexdigest()
        key = statistics_artifact_key(pipeline_name, dataset_name)
        client.put_object(
            Bucket=target_bucket,
            Key=key,
            Body=body,
            ContentType=CONTENT_TYPE,
            CacheControl=CACHE_CONTROL,
            Metadata={"content-hash-sha256": content_hash},
        )
        published.append(
            PublishedArtifact(
                key=key,
                content_hash_sha256=content_hash,
                size_bytes=len(body),
            )
        )
    return published


def _add_province_datasets(
    datasets: dict[str, object],
    context: dict[str, object],
    provinces: object,
    *,
    dataset_prefix: str = "province",
) -> None:
    if not isinstance(provinces, list):
        return
    for province in provinces:
        if not isinstance(province, dict):
            continue
        code = province.get("province_code")
        if not isinstance(code, str) or not code:
            continue
        datasets[f"{dataset_prefix}-{code.lower()}"] = {**context, "province": province}


def _json_body(payload: object) -> bytes:
    return (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _default_s3_client() -> S3Client:
    import boto3

    return boto3.client("s3")
