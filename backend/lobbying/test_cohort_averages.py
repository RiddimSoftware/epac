from __future__ import annotations

import unittest
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional, Sequence

from cohort_averages import (
    CohortAverage,
    MemberCommunicationTotal,
    ParliamentMember,
    build_comparison_row,
    compare_mp_lobbying_to_cohort,
    precompute_cohort_averages,
    quote_identifier,
)


class FixtureRepository:
    def __init__(
        self,
        members: Sequence[ParliamentMember],
        totals: Sequence[MemberCommunicationTotal],
    ) -> None:
        self.members = list(members)
        self.totals = list(totals)
        self.averages: list[CohortAverage] = []
        self.replaced_parliaments: list[int] = []

    def list_current_members(self) -> Sequence[ParliamentMember]:
        return self.members

    def list_member_communication_totals(self, parliament: Optional[int] = None) -> Sequence[MemberCommunicationTotal]:
        if parliament is None:
            return self.totals
        return [total for total in self.totals if total.parliament == parliament]

    def replace_cohort_averages(
        self,
        averages: Sequence[CohortAverage],
        parliaments: Optional[Sequence[int]] = None,
    ) -> None:
        self.averages = list(averages)
        self.replaced_parliaments = list(parliaments or [])

    def member_total(self, parliament: int, member_id: str) -> int:
        return sum(
            total.total_communications
            for total in self.totals
            if total.parliament == parliament and total.member_id == member_id
        )

    def member_party(self, member_id: str) -> Optional[str]:
        for member in self.members:
            if member.member_id == member_id:
                return member.party
        return None

    def cohort_average(self, parliament: int, party: Optional[str]) -> Optional[Decimal]:
        for average in self.averages:
            if average.parliament == parliament and average.party == party:
                return average.avg_communications
        return None


class CohortAverageTests(unittest.TestCase):
    def test_computes_party_and_national_averages_from_fixture_data(self) -> None:
        computed_at = datetime(2026, 6, 3, tzinfo=timezone.utc)
        repo = FixtureRepository(
            members=[
                ParliamentMember("lib-1", "Lib"),
                ParliamentMember("lib-2", "Lib"),
                ParliamentMember("lib-3", "Lib"),
                ParliamentMember("lib-4", "Lib"),
                ParliamentMember("lib-5", "Lib"),
                ParliamentMember("cpc-1", "CPC"),
                ParliamentMember("cpc-2", "CPC"),
                ParliamentMember("cpc-3", "CPC"),
                ParliamentMember("cpc-4", "CPC"),
                ParliamentMember("cpc-5", "CPC"),
            ],
            totals=[
                MemberCommunicationTotal(45, "lib-1", 10),
                MemberCommunicationTotal(45, "lib-2", 20),
                MemberCommunicationTotal(45, "lib-3", 30),
                MemberCommunicationTotal(45, "lib-4", 40),
                MemberCommunicationTotal(45, "lib-5", 50),
                MemberCommunicationTotal(45, "cpc-1", 5),
                MemberCommunicationTotal(45, "cpc-2", 5),
                MemberCommunicationTotal(45, "cpc-3", 5),
                MemberCommunicationTotal(45, "cpc-4", 5),
                MemberCommunicationTotal(45, "cpc-5", 5),
            ],
        )

        averages = precompute_cohort_averages(repo, computed_at=computed_at)

        by_party = {average.party: average for average in averages}
        self.assertEqual(by_party[None].avg_communications, Decimal("17.5"))
        self.assertEqual(by_party["Lib"].avg_communications, Decimal("30"))
        self.assertEqual(by_party["CPC"].avg_communications, Decimal("5"))
        self.assertTrue(all(average.computed_at == computed_at for average in averages))
        self.assertEqual(repo.averages, averages)

    def test_party_average_is_null_when_fewer_than_five_mps_have_communications(self) -> None:
        repo = FixtureRepository(
            members=[
                ParliamentMember("ndp-1", "NDP"),
                ParliamentMember("ndp-2", "NDP"),
                ParliamentMember("ndp-3", "NDP"),
                ParliamentMember("ndp-4", "NDP"),
                ParliamentMember("ndp-5", "NDP"),
            ],
            totals=[
                MemberCommunicationTotal(45, "ndp-1", 8),
                MemberCommunicationTotal(45, "ndp-2", 12),
                MemberCommunicationTotal(45, "ndp-3", 20),
                MemberCommunicationTotal(45, "ndp-4", 0),
            ],
        )

        averages = precompute_cohort_averages(repo)

        by_party = {average.party: average for average in averages}
        self.assertEqual(by_party[None].avg_communications, Decimal("13.33333333333333333333333333"))
        self.assertIsNone(by_party["NDP"].avg_communications)

    def test_empty_party_edge_case_keeps_null_party_average_row(self) -> None:
        repo = FixtureRepository(
            members=[
                ParliamentMember("green-1", "Green"),
                ParliamentMember("lib-1", "Lib"),
                ParliamentMember("lib-2", "Lib"),
                ParliamentMember("lib-3", "Lib"),
                ParliamentMember("lib-4", "Lib"),
                ParliamentMember("lib-5", "Lib"),
            ],
            totals=[
                MemberCommunicationTotal(45, "lib-1", 1),
                MemberCommunicationTotal(45, "lib-2", 2),
                MemberCommunicationTotal(45, "lib-3", 3),
                MemberCommunicationTotal(45, "lib-4", 4),
                MemberCommunicationTotal(45, "lib-5", 5),
            ],
        )

        averages = precompute_cohort_averages(repo)

        by_party = {average.party: average for average in averages}
        self.assertIn("Green", by_party)
        self.assertIsNone(by_party["Green"].avg_communications)

    def test_scoped_empty_parliament_run_replaces_that_parliament(self) -> None:
        repo = FixtureRepository(
            members=[ParliamentMember("lib-1", "Lib")],
            totals=[MemberCommunicationTotal(44, "lib-1", 10)],
        )

        averages = precompute_cohort_averages(repo, parliament=45)

        self.assertEqual(averages, [])
        self.assertEqual(repo.replaced_parliaments, [45])

    def test_compare_use_case_returns_ratios(self) -> None:
        repo = FixtureRepository(
            members=[
                ParliamentMember("lib-1", "Lib"),
                ParliamentMember("lib-2", "Lib"),
                ParliamentMember("lib-3", "Lib"),
                ParliamentMember("lib-4", "Lib"),
                ParliamentMember("lib-5", "Lib"),
            ],
            totals=[
                MemberCommunicationTotal(45, "lib-1", 30),
                MemberCommunicationTotal(45, "lib-2", 10),
                MemberCommunicationTotal(45, "lib-3", 20),
                MemberCommunicationTotal(45, "lib-4", 30),
                MemberCommunicationTotal(45, "lib-5", 10),
            ],
        )
        precompute_cohort_averages(repo)

        comparison = compare_mp_lobbying_to_cohort(repo, parliament=45, member_id="lib-1")

        self.assertEqual(comparison.mp_total, 30)
        self.assertEqual(comparison.party_avg, Decimal("20"))
        self.assertEqual(comparison.national_avg, Decimal("20"))
        self.assertEqual(comparison.ratio_vs_party, Decimal("1.5"))
        self.assertEqual(comparison.as_response_row()["ratio_vs_national"], 1.5)


class RatioTests(unittest.TestCase):
    def test_ratio_is_null_for_missing_or_zero_average(self) -> None:
        missing = build_comparison_row(mp_total=10, party_avg=None, national_avg=Decimal("0"))

        self.assertIsNone(missing.ratio_vs_party)
        self.assertIsNone(missing.ratio_vs_national)


class IdentifierTests(unittest.TestCase):
    def test_quote_identifier_accepts_schema_qualified_names(self) -> None:
        self.assertEqual(quote_identifier("public.lobbying_totals"), '"public"."lobbying_totals"')

    def test_quote_identifier_rejects_unsafe_names(self) -> None:
        with self.assertRaises(ValueError):
            quote_identifier("lobbying_totals;drop table members")


if __name__ == "__main__":
    unittest.main()
