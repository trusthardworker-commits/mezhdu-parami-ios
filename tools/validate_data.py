"""Data/fixture checks runnable on Windows. Swift engine tests are in Tests/."""
import json
import unittest
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT/"ScheduleApp/Resources/schedule.json").read_text(encoding="utf-8"))
GROUPS = {g["id"]:g for g in DATA["groups"]}

def lessons(group, day):
    key = day.isoformat()
    week = next(w["kind"] for w in DATA["weeks"] if w["start"] <= key <= w["end"])
    rows = []
    for row in GROUPS[group]["lessons"]:
        if row["weekday"] != day.isoweekday(): continue
        if key < row.get("startsOn", "0000") or key > row.get("endsOn", "9999"): continue
        if key in row.get("excludedDates", []): continue
        if "onlyDates" in row:
            if key not in row["onlyDates"]: continue
        elif row["week"] not in ("both", week): continue
        rows.append(row)
    explicit = {r["period"] for r in rows if "onlyDates" in r}
    return sorted((r for r in rows if "onlyDates" in r or r["period"] not in explicit), key=lambda r:r["period"])

class DataTests(unittest.TestCase):
    def test_all_pdf_columns(self):
        self.assertEqual(set(GROUPS), set("26ПИжб 26ИТб 26УСб 25ПИб 25ПИжб 25ИТб 25УСб 24ПИб 24ПИжб 24ИТб 24УСб 23ПИб 23ПИжб 23ИТб 23УСб 26Эб 26Мб 25ГУб 24ГУб 23Эб 23Мб".split()))

    def test_calendar_covers_exact_pdf_range(self):
        self.assertEqual(len(DATA["weeks"]), 53)
        self.assertEqual(DATA["weeks"][0]["start"], "2026-08-31")
        self.assertEqual(DATA["weeks"][-1]["end"], "2027-09-05")
        for i, week in enumerate(DATA["weeks"]):
            start, end = date.fromisoformat(week["start"]), date.fromisoformat(week["end"])
            self.assertEqual(start.isoweekday(), 1)
            self.assertEqual(end-start, timedelta(days=6))
            self.assertEqual(week["kind"], "lower" if i%2 else "upper")
            if i: self.assertEqual(start-date.fromisoformat(DATA["weeks"][i-1]["end"]), timedelta(days=1))

    def test_schema_dates_ids_and_periods(self):
        ids = set()
        for group in DATA["groups"]:
            self.assertIn(group["sourcePage"], [1,2,3,4])
            self.assertGreaterEqual(group["validThrough"], group["validFrom"])
            for row in group["lessons"]:
                self.assertNotIn(row["id"], ids)
                ids.add(row["id"])
                self.assertIn(row["weekday"], range(1,7))
                self.assertIn(row["period"], range(0,7))
                self.assertIn(row["week"], ["upper","lower","both"])
                self.assertTrue(row["title"] and row["details"])
                for key in ["startsOn", "endsOn"]:
                    if key in row: date.fromisoformat(row[key])
                for key in ["onlyDates", "excludedDates"]:
                    for value in row.get(key, []): date.fromisoformat(value)

    def test_no_conflicting_periods_for_any_group_or_date(self):
        for group in GROUPS:
            day = date(2026,11,9)
            while day <= date.fromisoformat(GROUPS[group]["validThrough"]):
                periods = [r["period"] for r in lessons(group, day)]
                self.assertEqual(len(periods), len(set(periods)), (group, day, periods))
                day += timedelta(days=1)

    def test_23pizh_verified_cells(self):
        for day, periods in [("2026-11-09",[2,3]), ("2026-11-10",[]), ("2026-11-11",[1,2]),
                             ("2026-11-12",[3,4]), ("2026-11-13",[3,4]), ("2026-11-14",[]),
                             ("2026-11-16",[3,4]), ("2026-11-17",[2,3,4]), ("2026-11-18",[2]),
                             ("2026-11-20",[]), ("2026-11-25",[1,2,3])]:
            self.assertEqual([r["period"] for r in lessons("23ПИжб",date.fromisoformat(day))], periods, day)

    def test_explicit_dates_cross_parity(self):
        for day in [9,16]:
            rows = [r for r in lessons("25ИТб", date(2026,11,day)) if r["period"]==2]
            self.assertEqual([r["title"] for r in rows], ["ЗИ"])
        self.assertEqual([r["period"] for r in lessons("26УСб",date(2026,11,14))], [1,2,3])
        self.assertEqual([r["period"] for r in lessons("26УСб",date(2026,11,21))], [3])

    def test_ambiguous_source_dates_are_flagged(self):
        self.assertTrue(GROUPS["24ГУб"]["warning"])
        self.assertTrue(GROUPS["23Мб"]["warning"])

    def test_original_pdfs_bundled(self):
        for name in ["timetable", "academic-weeks"]:
            self.assertTrue((ROOT/f"ScheduleApp/Resources/{name}.pdf").read_bytes().startswith(b"%PDF"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
