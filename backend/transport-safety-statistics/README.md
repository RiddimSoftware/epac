# Transport Safety Statistics

Fetches national TSB air, marine, and rail occurrence summaries plus Transport Canada road casualty rates by province.

```bash
python3 transport_safety_statistics.py --output ../../ios/epac/transport-safety-statistics.json
python3 -m unittest test_transport_safety_statistics.py
```

Sources:

- Transportation Safety Board of Canada annual statistics
- Transport Canada Canadian Motor Vehicle Traffic Collision Statistics
