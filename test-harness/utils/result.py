# utils/result.py

import json
import time
from datetime import datetime


def record_result(module, test_name, status, duration, details=""):
    result = {
        "module": module,
        "test": test_name,
        "status": status,
        "duration": duration,
        "timestamp": datetime.utcnow().isoformat(),
        "details": details,
    }

    with open("results.jsonl", "a") as f:
        f.write(json.dumps(result) + "\n")
