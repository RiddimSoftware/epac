import os
import xml.etree.ElementTree as ET
import glob
import random
import csv

# Target people and their identifiers in ToCText
# We'll use the last name as the key, but handle potential collisions
TARGET_PEOPLE = {
    "Mark Carney": "Carney",
    "Pierre Poilievre": "Poilievre",
    "Yves-François Blanchet": "Blanchet",
    "Steven MacKinnon": "MacKinnon",
    "Andrew Scheer": "Scheer",
    "Christine Normandin": "Normandin"
}

# Mapping of ToCText clean values to canonical names
TOCTEXT_MAP = {
    "Carney": "Mark Carney",
    "Poilievre": "Pierre Poilievre",
    "Blanchet": "Yves-François Blanchet",
    "MacKinnon": "Steven MacKinnon",
    "Scheer": "Andrew Scheer",
    "Normandin": "Christine Normandin"
}

def clean_toc_text(text):
    if not text:
        return ""
    # Remove common prefixes
    prefixes = ["Mr. ", "Ms. ", "Mrs. ", "Hon. ", "Right Hon. ", "The "]
    cleaned = text
    for prefix in prefixes:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):]
    
    # Handle parentheticals like "MacKinnon (Gatineau)"
    if "(" in cleaned:
        cleaned = cleaned.split("(")[0].strip()
    
    return cleaned.strip()

def get_speaker_match(toc_text):
    cleaned = clean_toc_text(toc_text)
    
    # Exact match for the surname-based key
    if cleaned in TOCTEXT_MAP:
        return TOCTEXT_MAP[cleaned]
    
    # Special check to avoid matching "Blanchette-Joncas" as "Blanchet"
    if cleaned.startswith("Blanchette"):
        return None
        
    # Check if cleaned starts with any of our keys (handling some variations)
    for key, canonical in TOCTEXT_MAP.items():
        if cleaned == key:
            return canonical
            
    return None

def extract_from_file(file_path):
    # Dictionary to hold speeches for this file
    speeches = {name: [] for name in TOCTEXT_MAP.values()}
    
    try:
        # Use iterparse for memory efficiency in large XML files
        context = ET.iterparse(file_path, events=("start", "end"))
        event, root = next(context)
        
        current_speaker = None
        current_text_fragments = []
        
        for event, elem in context:
            if event == "start":
                if elem.tag == "Intervention":
                    toc_text = elem.get("ToCText")
                    current_speaker = get_speaker_match(toc_text)
                    current_text_fragments = []
            
            elif event == "end":
                if elem.tag == "ParaText" and current_speaker:
                    if elem.text:
                        current_text_fragments.append(elem.text.strip())
                
                elif elem.tag == "Intervention":
                    if current_speaker and current_text_fragments:
                        full_speech = " ".join(current_text_fragments)
                        if full_speech.strip():
                            speeches[current_speaker].append(full_speech.strip())
                    current_speaker = None
                    current_text_fragments = []
                
                # Clear element from memory
                elem.clear()
        root.clear()
        
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
        
    return speeches

def main():
    hansard_dir = "hansard"
    leaders_dir = "leaders"
    bert_dir = "bert"
    
    os.makedirs(leaders_dir, exist_ok=True)
    os.makedirs(bert_dir, exist_ok=True)
    
    all_speeches = {name: [] for name in TOCTEXT_MAP.values()}
    
    xml_files = sorted(glob.glob(os.path.join(hansard_dir, "*.XML")))
    print(f"Found {len(xml_files)} XML files.")
    
    for i, xml_file in enumerate(xml_files):
        if (i + 1) % 50 == 0:
            print(f"Processed {i+1}/{len(xml_files)} files...")
        
        file_speeches = extract_from_file(xml_file)
        for name, texts in file_speeches.items():
            all_speeches[name].extend(texts)
            
    # Save per-leader files
    for name, texts in all_speeches.items():
        if not texts:
            print(f"No speeches found for {name}")
            continue
            
        print(f"Saving {len(texts)} speeches for {name}")
        safe_name = name.replace(" ", "_").replace("ç", "c")
        
        # Split into multiple files if more than 5000 entries
        chunk_size = 5000
        for chunk_idx, i in enumerate(range(0, len(texts), chunk_size)):
            chunk = texts[i:i + chunk_size]
            filename = f"{safe_name}_{chunk_idx + 1}.txt"
            with open(os.path.join(leaders_dir, filename), "w", encoding="utf-8") as f:
                f.write("\n".join(chunk))
                
    # Prepare BERT training/test datasets
    print("Preparing BERT datasets...")
    
    all_train_data = []
    all_test_data = []
    
    def write_csv(data, filename):
        path = os.path.join(bert_dir, filename)
        with open(path, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["text", "label"])
            writer.writeheader()
            writer.writerows(data)

    random.seed(42)
    
    for name, texts in all_speeches.items():
        # Filter speeches
        filtered_speeches = [{"text": t, "label": name} for t in texts if len(t.split()) > 8]
        
        if not filtered_speeches:
            continue
            
        # Shuffle speaker-specific data
        random.shuffle(filtered_speeches)
        
        # Split 80/20
        split_idx = int(len(filtered_speeches) * 0.8)
        speaker_train = filtered_speeches[:split_idx]
        speaker_test = filtered_speeches[split_idx:]
        
        # Save speaker-specific files
        safe_name = name.replace(" ", "_").replace("ç", "c")
        write_csv(speaker_train, f"{safe_name}_train.csv")
        write_csv(speaker_test, f"{safe_name}_test.csv")
        
        # Add to global datasets
        all_train_data.extend(speaker_train)
        all_test_data.extend(speaker_test)
        
    # Shuffle global datasets for better training
    random.shuffle(all_train_data)
    random.shuffle(all_test_data)
    
    write_csv(all_train_data, "train.csv")
    write_csv(all_test_data, "test.csv")
    
    print(f"Extraction complete.")
    print(f"Total speeches extracted: {sum(len(v) for v in all_speeches.values())}")
    print(f"Global BERT Train size: {len(all_train_data)}")
    print(f"Global BERT Test size: {len(all_test_data)}")

if __name__ == "__main__":
    main()
