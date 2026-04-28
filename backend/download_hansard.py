import os
import sys
import time
import requests
import csv
import argparse
import re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from observability.logger import get_logger

logger = get_logger("download_hansard")

def get_latest_sitting(folder):
    max_val = (0, 0, 0)
    if not os.path.exists(folder):
        return max_val
    
    pattern = re.compile(r"^(\d+)-(\d+)-HAN(\d+)-E\.XML$")
    for filename in os.listdir(folder):
        match = pattern.match(filename)
        if match:
            p, s, sit = map(int, match.groups())
            if (p, s, sit) > max_val:
                max_val = (p, s, sit)
    return max_val

def download_file(url, session_str, sitting_num, folder):
    sitting_padded = f"{sitting_num:03d}"
    filename = f"{session_str}-HAN{sitting_padded}-E.XML"
    filepath = os.path.join(folder, filename)
    
    if os.path.exists(filepath):
        return True, 200

    try:
        headers = {'User-Agent': 'HansardDownloader/1.0 (Civic Engagement Tool; contact: sunny)'}
        response = requests.get(url, timeout=30, headers=headers)
        if response.status_code == 200:
            # Check if it's actually XML (not an error page that returned 200)
            if 'text/xml' in response.headers.get('Content-Type', ''):
                with open(filepath, 'wb') as f:
                    f.write(response.content)
                return True, 200
            else:
                return False, 404
        else:
            return False, response.status_code
    except Exception:
        # Surface exception details — silent return masked transient
        # failures and made retries opaque in production.
        logger.exception("download.failed", extra={"url": url, "filename": filename})
        return False, 500

def main():
    parser = argparse.ArgumentParser(description='Download Hansard XML files.')
    parser.add_argument('--output', '-o', default='hansard', help='Directory to save downloaded files and logs')
    args = parser.parse_args()

    started = time.monotonic()
    downloaded = 0
    failed = 0
    logger.info("pipeline.start", extra={"output_dir": args.output})

    hansard_dir = args.output
    if not os.path.exists(hansard_dir):
        os.makedirs(hansard_dir)
    
    failures_log = os.path.join(hansard_dir, 'failures.log')
    
    latest_p, latest_s, latest_sit = get_latest_sitting(hansard_dir)
    
    all_sessions = []
    if os.path.exists('sessions.csv'):
        with open('sessions.csv', 'r') as f:
            all_sessions = [line.strip() for line in f if line.strip()]
    
    target_sessions = []
    for s in all_sessions:
        try:
            parts = s.split('-')
            parl = int(parts[0])
            sess = int(parts[1])
            if parl > 34 or (parl == 34 and sess >= 1):
                if (parl, sess) >= (latest_p, latest_s):
                    target_sessions.append((parl, sess, s))
        except:
            continue
    
    # Sort chronological: oldest first
    target_sessions.sort()

    with open(failures_log, 'a') as log_file:
        for parl, sess, session_str in target_sessions:
            session_code = f"{parl}{sess}"
            
            consecutive_404s = 0
            max_consecutive_404s = 3
            downloaded_any = False
            
            start_sitting = 1
            if (parl, sess) == (latest_p, latest_s):
                start_sitting = latest_sit + 1
            
            for sitting in range(start_sitting, 1000):
                sitting_padded = f"{sitting:03d}"
                url = f"https://www.ourcommons.ca/Content/House/{session_code}/Debates/{sitting_padded}/HAN{sitting_padded}-E.XML"
                
                success, status_code = download_file(url, session_str, sitting, hansard_dir)
                
                if success:
                    consecutive_404s = 0
                    downloaded_any = True
                    downloaded += 1
                else:
                    if status_code == 404 or status_code == 302:
                        consecutive_404s += 1
                        # Log if we expected data (sitting 1) or if it's a gap
                        if not downloaded_any and sitting == 1:
                             log_file.write(f"{session_str},{sitting},{url}\n")
                             log_file.flush()

                        if consecutive_404s >= max_consecutive_404s:
                            break
                    else:
                        log_file.write(f"{session_str},{sitting},{url}\n")
                        log_file.flush()
                        consecutive_404s = 0
                        failed += 1
                        logger.error("download.http_error", extra={
                            "url": url,
                            "status_code": status_code,
                            "session": session_str,
                            "sitting": sitting,
                        })

                time.sleep(0.05)

    duration_ms = int((time.monotonic() - started) * 1000)
    logger.info("pipeline.done", extra={
        "records_processed": downloaded,
        "failed": failed,
        "duration_ms": duration_ms,
    })

if __name__ == "__main__":
    main()

if __name__ == "__main__":
    main()