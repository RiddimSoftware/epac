#!/usr/bin/env python3
import os
import sys
import re
import json
import argparse
import urllib.request
from html.parser import HTMLParser

class SenateHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_tbody = False
        self.in_row = False
        self.in_cell = False
        self.current_cell_index = -1
        self.rows = []
        self.current_row = []
        self.current_cell_data = ""
        self.current_link = ""
        self.cell_attrs = {}

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == "tbody":
            self.in_tbody = True
        elif tag == "tr" and self.in_tbody:
            self.in_row = True
            self.current_row = []
            self.current_cell_index = -1
        elif tag == "td" and self.in_row:
            self.in_cell = True
            self.current_cell_index += 1
            self.current_cell_data = ""
            self.current_link = ""
            self.cell_attrs = attrs_dict
        elif tag == "a" and self.in_cell:
            if "href" in attrs_dict:
                self.current_link = attrs_dict["href"]

    def handle_data(self, data):
        if self.in_cell:
            self.current_cell_data += data

    def handle_endtag(self, tag):
        if tag == "tbody":
            self.in_tbody = False
        elif tag == "tr" and self.in_row:
            self.in_row = False
            self.rows.append(self.current_row)
        elif tag == "td" and self.in_cell:
            self.in_cell = False
            text = self.current_cell_data.strip()
            self.current_row.append({
                "text": text,
                "link": self.current_link,
                "attrs": self.cell_attrs
            })

def split_name(name_str):
    name_str = name_str.strip()
    if ',' in name_str:
        parts = name_str.split(',', 1)
        last_name = parts[0].strip()
        first_name = parts[1].strip()
    else:
        parts = name_str.rsplit(' ', 1)
        if len(parts) == 2:
            first_name = parts[0].strip()
            last_name = parts[1].strip()
        else:
            first_name = name_str
            last_name = ""
    return first_name, last_name

def clean_pm(pm_str):
    pm_str = pm_str.strip()
    # Remove party abbreviation in parentheses, e.g., (Lib.) or (PC)
    pm_str = re.sub(r'\s*\([^)]*\)', '', pm_str).strip()
    if ',' in pm_str:
        parts = pm_str.split(',', 1)
        last = parts[0].strip()
        first = parts[1].strip()
        return f"{first} {last}"
    return pm_str

def clean_province(prov_str):
    # Remove anything in parentheses, e.g. "Quebec (Grandville)" -> "Quebec"
    prov_str = re.sub(r'\s*\([^)]*\)', '', prov_str).strip()
    known = {
        "british columbia", "alberta", "saskatchewan", "manitoba", "ontario",
        "quebec", "québec", "new brunswick", "nova scotia", "prince edward island",
        "newfoundland and labrador", "northwest territories", "nunavut", "yukon"
    }
    for k in known:
        if prov_str.lower() == k:
            return prov_str
    return prov_str.title()

def main():
    parser = argparse.ArgumentParser(description="Fetch and parse Senate list of Canada.")
    parser.add_argument("--output", "-o", required=True, help="Path to write senators/v1/all.json output")
    args = parser.parse_args()

    url = "https://sencanada.ca/umbraco/surface/SenatorsAjax/GetSenators?displayFor=senatorslist&Lang=en"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            html = response.read().decode("utf-8")
    except Exception as e:
        print(f"Error fetching senators list: {e}", file=sys.stderr)
        sys.exit(1)

    html_parser = SenateHTMLParser()
    html_parser.feed(html)

    items = []
    for r in html_parser.rows:
        if len(r) < 6:
            continue

        name_info = r[0]
        name_str = name_info["text"]
        link_str = name_info["link"]
        if link_str.startswith("/"):
            link_str = "https://sencanada.ca" + link_str

        first_name, last_name = split_name(name_str)
        caucus_short = r[1]["text"].strip()
        if caucus_short == "C":
            caucus_short = "CPC"

        caucus_full = caucus_short
        caucus_map = {
            "CPC": "Conservative Party of Canada",
            "CSG": "Canadian Senators Group",
            "ISG": "Independent Senators Group",
            "PSG": "Progressive Senate Group",
            "GRO": "Government Representative's Office",
            "Non-affiliated": "Non-affiliated"
        }
        if caucus_short in caucus_map:
            caucus_full = caucus_map[caucus_short]

        province_raw = r[2]["attrs"].get("data-order", r[2]["text"]).strip()
        province_full = clean_province(province_raw)

        nom_date_str = r[3]["text"].strip()
        match = re.match(r'^\d{4}-\d{2}-\d{2}$', nom_date_str)
        if not match:
            order_attr = r[3]["attrs"].get("data-order", "")
            match = re.match(r'^(\d{4}-\d{2}-\d{2})', order_attr)
            if match:
                nom_date_str = match.group(1)
            else:
                nom_date_str = None

        pm_raw = r[5]["text"].strip()
        appointing_pm = clean_pm(pm_raw)

        item = {
            "PersonOfficialFirstName": first_name,
            "PersonOfficialLastName": last_name,
            "ProvinceNameEn": province_full,
            "CaucusAbbreviationEn": caucus_short,
            "CaucusNameEn": caucus_full,
            "PersonPageUrl": link_str,
        }

        if nom_date_str:
            item["appointment"] = {
                "appointment_date": nom_date_str,
                "appointing_prime_minister": appointing_pm,
                "source_url": "https://pco-bcp.gc.ca/oic-ddc",
                "declared_affiliation": caucus_short
            }
        items.append(item)

    # Write output directory
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    payload = {"items": items}
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    print(f"Ingested {len(items)} senators and saved to {args.output}")

if __name__ == "__main__":
    main()
