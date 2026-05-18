import hashlib
import json
import unittest

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from transport_safety_statistics import (
    build_payload,
    parse_mode_year,
    parse_road_year,
    publish_payload,
)


class FakeS3Client:
    def __init__(self):
        self.calls = []

    def put_object(self, **kwargs):
        self.calls.append(kwargs)


class TransportSafetyStatisticsTests(unittest.TestCase):
    def test_parse_air_summary(self):
        text = (
            "The TSB received 1010 reports of air occurrences in 2024 "
            "(193 accidents and 817 incidents), including 46 fatalities."
        )

        record = parse_mode_year("air", 2024, text, "https://example.test/air")

        self.assertEqual(record.occurrences, 1010)
        self.assertEqual(record.accidents, 193)
        self.assertEqual(record.incidents, 817)
        self.assertEqual(record.fatalities, 46)

    def test_parse_road_year(self):
        text = (
            "Collisions and Casualties - 2004-2023 Collisions Victims "
            "Year Fatal Personal Injury Fatalities Serious Injuries Injuries (Total) "
            "2023 1,768 89,982 1,964 9,261 118,838 "
            "Casualty Rates - 2023 Per 100,000 Population Per Billion Vehicle-Kilometres "
            "Per 100,000 Licensed Drivers Fatalities Injuries Fatalities Injuries Fatalities Injuries "
            "Canada 4.9 296.5 4.5 273.9 6.9 415.8 "
            "NL 7.8 408.2 8.3 437.4 10.6 556.8 "
            "PE 8.1 287.3 8.4 299.2 10.8 383.8 "
            "NS 5.3 567.6 4.6 496.8 6.9 738.1 "
            "NB 8.5 257.5 8.1 245.7 12.8 386.7 "
            "QC 4.3 317.1 4.7 345.1 6.4 473.9 "
            "ON 3.9 231.0 3.4 198.7 5.3 312.5 "
            "MB 5.4 517.7 4.7 458.1 8.1 786.4 "
            "SK 7.6 445.9 5.9 345.5 11.0 644.9 "
            "AB 6.4 379.9 4.9 291.1 8.4 502.4 "
            "BC 5.5 230.7 6.2 261.2 7.9 334.5 "
            "YT 19.8 589.5 11.0 328.0 27.0 804.5 "
            "NT 9.0 190.2 8.0 171.0 14.9 316.9 "
            "NU 2.5 39.3 20.8 333.4 9.2 146.7"
        )

        national, provinces = parse_road_year(2023, text, "https://example.test/road")

        self.assertEqual(national.fatalities, 1964)
        self.assertEqual(national.serious_injuries, 9261)
        self.assertEqual(provinces["ON"].fatalities_per_100k, 3.9)
        self.assertEqual(provinces["BC"].fatalities_per_billion_vkt, 6.2)

    def test_build_payload_composes_five_year_snapshot(self):
        def fetcher(url):
            if "aviation" in url:
                year = int(url.split("/")[-2])
                return (
                    f"The TSB received {year - 1014} reports of air occurrences in {year} "
                    f"({year - 1831} accidents and {year - 1207} incidents), "
                    f"including {year - 1978} fatalities."
                )
            if "marine" in url:
                year = int(url.split("/")[-2])
                return (
                    f"In {year}, the TSB received {year - 1073} reports of marine occurrences. "
                    f"Of these, {year - 1811} were accidents that resulted in a total of "
                    f"{year - 2012} fatalities."
                )
            if "rail" in url:
                year = int(url.split("/")[-2])
                return (
                    f"In {year}, the TSB received {year - 826} reports of rail occurrences. "
                    f"Of these, {year - 1128} were accidents. There were {year - 1955} fatalities."
                )

            year = int(url.split("/")[-2])
            return (
                f"Collisions and Casualties - 2004-{year} Collisions Victims "
                "Year Fatal Personal Injury Fatalities Serious Injuries Injuries (Total) "
                f"{year} 1,700 88,000 {year - 59} {year + 7000} {year + 116000} "
                f"Casualty Rates - {year} Per 100,000 Population Per Billion Vehicle-Kilometres "
                "Per 100,000 Licensed Drivers Fatalities Injuries Fatalities Injuries Fatalities Injuries "
                "NL 7.8 408.2 8.3 437.4 10.6 556.8 "
                "PE 8.1 287.3 8.4 299.2 10.8 383.8 "
                "NS 5.3 567.6 4.6 496.8 6.9 738.1 "
                "NB 8.5 257.5 8.1 245.7 12.8 386.7 "
                "QC 4.3 317.1 4.7 345.1 6.4 473.9 "
                "ON 3.9 231.0 3.4 198.7 5.3 312.5 "
                "MB 5.4 517.7 4.7 458.1 8.1 786.4 "
                "SK 7.6 445.9 5.9 345.5 11.0 644.9 "
                "AB 6.4 379.9 4.9 291.1 8.4 502.4 "
                "BC 5.5 230.7 6.2 261.2 7.9 334.5 "
                "YT 19.8 589.5 11.0 328.0 27.0 804.5 "
                "NT 9.0 190.2 8.0 171.0 14.9 316.9 "
                "NU 2.5 39.3 20.8 333.4 9.2 146.7"
            )

        payload = build_payload(fetcher=fetcher)

        self.assertEqual(payload["history_years"]["tsb"], [2020, 2021, 2022, 2023, 2024])
        self.assertEqual(payload["history_years"]["road"], [2019, 2020, 2021, 2022, 2023])
        self.assertEqual(len(payload["modes"]["air"]), 5)
        self.assertEqual(len(payload["road"]["provinces"]), 13)

    def test_publish_payload_writes_s3_artifacts_with_content_hash(self):
        payload = {
            "generated_at": "2026-05-01T00:00:00Z",
            "history_years": {"road": [2023]},
            "road": {
                "national": [{"year": 2023, "fatalities": 1964}],
                "provinces": [{"province": "Ontario", "province_code": "ON", "reference_year": 2023}],
            },
        }
        s3_client = FakeS3Client()

        published = publish_payload(payload, bucket="artifact-bucket", s3_client=s3_client)

        keys = [call["Key"] for call in s3_client.calls]
        self.assertEqual(published[0].key, "statistics/v1/transport-safety-statistics/all.json")
        self.assertIn("statistics/v1/transport-safety-statistics/road-national.json", keys)
        self.assertIn("statistics/v1/transport-safety-statistics/road-province-on.json", keys)
        call = s3_client.calls[0]
        self.assertEqual(json.loads(call["Body"].decode("utf-8")), payload)
        self.assertEqual(
            call["Metadata"]["content-hash-sha256"],
            hashlib.sha256(call["Body"]).hexdigest(),
        )


if __name__ == "__main__":
    unittest.main()
