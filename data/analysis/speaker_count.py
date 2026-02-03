import sys
import os
import xml.etree.ElementTree as ET
import glob
import csv
from collections import Counter

def clean_toc_text(text):
    if not text:
        return ""
    # Remove common prefixes (English and French)
    prefixes = [
        "Mr. ", "Ms. ", "Mrs. ", "Hon. ", "Right Hon. ", "The ",
        "M. ", "Mme ", "L'hon. ", "Le ", "La ", "S.E. ", "L'honorable "
    ]
    cleaned = text
    
    # Repeatedly remove prefixes in case they are nested (e.g. "Hon. Mr. ")
    changed = True
    while changed:
        changed = False
        for prefix in prefixes:
            if cleaned.startswith(prefix):
                cleaned = cleaned[len(prefix):]
                changed = True
    
    # Handle parentheticals like "MacKinnon (Gatineau)"
    if "(" in cleaned:
        cleaned = cleaned.split("(")[0].strip()
    
    return cleaned.strip()

def load_members(xml_path):
    """
    Loads member data from XML and returns two mapping dictionaries.
    """
    full_name_map = {}
    last_name_map = {}
    
    if not os.path.exists(xml_path):
        print(f"Warning: Member XML not found at {xml_path}", file=sys.stderr)
        return full_name_map, last_name_map

    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        seen_person_ids = set()
        unique_members = []

        # First pass: get unique persons
        for member in root.findall("MemberOfParliament"):
            person_id = member.findtext("PersonId")
            if not person_id or person_id in seen_person_ids:
                continue
            seen_person_ids.add(person_id)
            
            first_name = member.findtext("PersonOfficialFirstName")
            last_name = member.findtext("PersonOfficialLastName")
            if first_name and last_name:
                unique_members.append((person_id, first_name, last_name))
        
        # Second pass: build maps
        last_name_counts = Counter(m[2] for m in unique_members)
        
        for pid, first, last in unique_members:
            full_name = f"{first} {last}"
            full_name_map[full_name] = (pid, first, last)
            # Only map last name if it's unique across all members
            if last_name_counts[last] == 1:
                last_name_map[last] = (pid, first, last)

    except Exception as e:
        print(f"Error loading members: {e}", file=sys.stderr)
    
    return full_name_map, last_name_map

def count_speakers(hansard_dir):
    speaker_counts = Counter()
    xml_files = sorted(glob.glob(os.path.join(hansard_dir, "*.XML")))
    
    total_files = len(xml_files)
    print(f"Found {total_files} XML files. Processing...", file=sys.stderr, flush=True)

    for i, xml_file in enumerate(xml_files):
        if (i + 1) % 100 == 0:
            print(f"Processed {i+1}/{total_files} files...", file=sys.stderr, flush=True)
            
        try:
            # Use iterparse for memory efficiency
            context = ET.iterparse(xml_file, events=("start",))
            for event, elem in context:
                if elem.tag == "Intervention":
                    toc_text = elem.get("ToCText")
                    if toc_text:
                        cleaned_name = clean_toc_text(toc_text)
                        if cleaned_name:
                            speaker_counts[cleaned_name] += 1
                # Clear element to save memory
                elem.clear()
        except Exception as e:
            print(f"Error parsing {xml_file}: {e}", file=sys.stderr)

    return speaker_counts

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    
    # Default paths
    hansard_dir = os.path.join(project_root, "data", "hansard")
    members_xml = os.path.join(project_root, "data", "members", "all.xml")
    
    # Allow overriding hansard_dir via CLI
    if len(sys.argv) > 1:
        hansard_dir = sys.argv[1]
    
    if not os.path.exists(hansard_dir):
        # Fallback for common relative path
        hansard_dir = "data/hansard"
    
    if not os.path.exists(members_xml):
        # Fallback for common relative path
        members_xml = "data/members/all.xml"

    full_name_map, last_name_map = load_members(members_xml)
    raw_counts = count_speakers(hansard_dir)
    
    # Aggregate counts by PersonId
    # results: {person_id: {"first": first, "last": last, "count": count}}
    resolved_results = {}
    unresolved_counts = Counter()

    for name, count in raw_counts.items():
        pid, first, last = None, None, None
        
        if name in full_name_map:
            pid, first, last = full_name_map[name]
        elif name in last_name_map:
            pid, first, last = last_name_map[name]
        
        if pid:
            if pid not in resolved_results:
                resolved_results[pid] = {"first": first, "last": last, "count": 0}
            resolved_results[pid]["count"] += count
        else:
            unresolved_counts[name] += count

    writer = csv.writer(sys.stdout)
    writer.writerow(["ID", "FIRST_NAME", "LAST_NAME", "SPEECH_COUNT"])
    
    # Sort resolved members by count descending
    sorted_pids = sorted(resolved_results.keys(), key=lambda x: resolved_results[x]["count"], reverse=True)
    for pid in sorted_pids:
        res = resolved_results[pid]
        writer.writerow([pid, res["first"], res["last"], res["count"]])

    # Optionally print unresolved to stderr for debugging
    if unresolved_counts:
        print(f"\nUnresolved speakers: {len(unresolved_counts)}", file=sys.stderr)
        # for name, count in unresolved_counts.most_common(10):
        #     print(f"  {name}: {count}", file=sys.stderr)

if __name__ == "__main__":
    main()
