@testable import epac
import Foundation
import Testing

struct TransportSafetyStatisticsTests {
    @Test func decodesTransportSafetySnapshot() throws {
        let json = """
        {
          "generated_at": "2026-04-28T23:16:52Z",
          "history_years": {
            "tsb": [2020, 2021, 2022, 2023, 2024],
            "road": [2019, 2020, 2021, 2022, 2023]
          },
          "source": {
            "title": "TSB Annual Statistics and Transport Canada Road Safety",
            "url": "https://tsb.gc.ca/eng/stats/aviation/stats.html",
            "note": "TSB and Transport Canada source note."
          },
          "datasets": [
            {
              "id": "tsb-annual-statistics",
              "title": "Transportation Safety Board of Canada Annual Statistics",
              "url": "https://tsb.gc.ca/eng/stats/aviation/stats.html"
            }
          ],
          "modes": {
            "air": [
              {
                "year": 2024,
                "occurrences": 1010,
                "accidents": 193,
                "incidents": 817,
                "fatalities": 46,
                "source_url": "https://www.tsb.gc.ca/eng/stats/aviation/2024/ssea-ssao-2024.html"
              }
            ],
            "rail": [],
            "marine": []
          },
          "road": {
            "national": [
              {
                "year": 2023,
                "fatalities": 1964,
                "serious_injuries": 9261,
                "total_injuries": 118838,
                "source_url": "https://tc.canada.ca/en/road-transportation/statistics-data/canadian-motor-vehicle-traffic-collision-statistics/2023/canadian-motor-vehicle-traffic-collision-statistics-2023"
              }
            ],
            "provinces": [
              {
                "province": "Ontario",
                "province_code": "ON",
                "reference_year": 2023,
                "fatalities_per_100k": 3.9,
                "injuries_per_100k": 231.0,
                "fatalities_per_billion_vkt": 3.4,
                "history": [
                  {
                    "year": 2023,
                    "fatalities_per_100k": 3.9,
                    "injuries_per_100k": 231.0,
                    "fatalities_per_billion_vkt": 3.4,
                    "injuries_per_billion_vkt": 198.7,
                    "fatalities_per_100k_licensed_drivers": 5.3,
                    "injuries_per_100k_licensed_drivers": 312.5,
                    "source_url": "https://tc.canada.ca/en/road-transportation/statistics-data/canadian-motor-vehicle-traffic-collision-statistics/2023/canadian-motor-vehicle-traffic-collision-statistics-2023"
                  }
                ]
              }
            ]
          }
        }
        """

        let snapshot = try TransportSafetyStatisticsDatabase.decode(data: Data(json.utf8))

        #expect(snapshot.historyYears.tsb == [2020, 2021, 2022, 2023, 2024])
        #expect(snapshot.modes["air"]?.first?.accidents == 193)
        #expect(snapshot.road.national.first?.fatalities == 1_964)
        #expect(snapshot.road.provinces.first?.provinceCode == "ON")
        #expect(snapshot.road.provinces.first?.fatalitiesPer100k == 3.9)
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(TransportSafetyStatisticsDatabase.snapshot())

        #expect(snapshot.historyYears.tsb.count == 5)
        #expect(snapshot.historyYears.road.count == 5)
        #expect(snapshot.road.provinces.count == 13)
        #expect(TransportSafetyStatisticsDatabase.roadStatistic(for: "on")?.province == "Ontario")
        #expect(TransportSafetyStatisticsDatabase.latestModeYear("air")?.year == 2024)
        #expect((TransportSafetyStatisticsDatabase.latestRoadNational()?.fatalities ?? 0) > 1_000)
    }

    @Test func formatsRateLabel() {
        #expect(TransportSafetyStatisticsDatabase.rateLabel(3.94, unit: "per 100k") == "3.9 per 100k")
    }
}
