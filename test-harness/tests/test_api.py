import requests
import json
import time


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    url = f"http://{outputs['alb_dns']['value']}"

    print(f"Testing endpoint: {url}")

    # ALB needs time to warm up
    for i in range(10):
        try:
            res = requests.get(url, timeout=5)
            if res.status_code == 200:
                print("✅ API reachable")
                return
        except Exception:
            pass

        print(f"Retry {i+1}...")
        time.sleep(10)

    raise Exception("❌ API test failed")
