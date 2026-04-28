@testable import epac
import Foundation
import Testing

struct ConsumerPriceIndexStatisticsTests {
    @Test func decodesProvinceSnapshot() throws {
        let json = """
        {
          "reference_month": "2026-03",
          "source": {
            "title": "Statistics Canada — Consumer Price Index",
            "url": "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1810000401",
            "note": "Monthly CPI table 18-10-0004-01 is not seasonally adjusted."
          },
          "national": {
            "province": "Canada",
            "province_code": "CA",
            "reference_month": "2026-03",
            "all_items_index": 167.4,
            "all_items_yoy_percent": 2.4,
            "food_yoy_percent": 4.0,
            "shelter_yoy_percent": 2.8,
            "energy_yoy_percent": 3.9,
            "national_all_items_yoy_percent": 2.4,
            "months": []
          },
          "provinces": [
            {
              "province": "Ontario",
              "province_code": "ON",
              "reference_month": "2026-03",
              "all_items_index": 168.2,
              "all_items_yoy_percent": 1.9,
              "food_yoy_percent": 4.7,
              "shelter_yoy_percent": 0.1,
              "energy_yoy_percent": 3.1,
              "national_all_items_yoy_percent": 2.4,
              "months": [
                {
                  "ref_date": "2026-03",
                  "all_items_index": 168.2,
                  "all_items_yoy_percent": 1.9,
                  "food_yoy_percent": 4.7,
                  "shelter_yoy_percent": 0.1,
                  "energy_yoy_percent": 3.1
                }
              ]
            }
          ]
        }
        """

        let snapshot = try ConsumerPriceIndexStatisticsDatabase.decode(data: Data(json.utf8))

        #expect(snapshot.referenceMonth == "2026-03")
        #expect(snapshot.source.title == "Statistics Canada — Consumer Price Index")
        #expect(snapshot.national.allItemsYearOverYearPercent == 2.4)
        #expect(snapshot.provinces.first?.provinceCode == "ON")
        #expect(snapshot.provinces.first?.foodYearOverYearPercent == 4.7)
        #expect(snapshot.provinces.first?.months.first?.allItemsIndex == 168.2)
    }

    @Test func formatsReferenceMonthLabelAndDate() throws {
        #expect(ConsumerPriceIndexStatisticsDatabase.monthLabel("2026-03") == "March 2026")
        #expect(ConsumerPriceIndexStatisticsDatabase.monthLabel("bad-date") == "bad-date")
        let date = try #require(ConsumerPriceIndexStatisticsDatabase.date(for: "2026-03"))
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 1)
        #expect(ConsumerPriceIndexStatisticsDatabase.date(for: "bad-date") == nil)
    }

    @Test func loadsBundledSnapshot() throws {
        let snapshot = try #require(ConsumerPriceIndexStatisticsDatabase.snapshot())

        #expect(snapshot.referenceMonth == "2026-03")
        #expect(snapshot.provinces.count == 10)
        #expect(snapshot.provinces.allSatisfy { $0.months.count == 24 })
        #expect(ConsumerPriceIndexStatisticsDatabase.statistic(for: "on")?.province == "Ontario")
    }
}
