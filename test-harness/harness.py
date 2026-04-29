# harness.py
import os
import yaml
import argparse
from utils import terraform
import importlib


def load_config():
    # This always finds config/modules.yaml next to harness.py regardless of where you invoke the script from.
    config_path = os.path.join(os.path.dirname(__file__), "config", "modules.yaml")
    with open(config_path) as f:
        return yaml.safe_load(f)


def run_tests(test_names, outputs):
    for test in test_names:
        module = importlib.import_module(f"tests.{test}")
        module.run(outputs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--module", required=True)
    parser.add_argument("--destroy", action="store_true")
    args = parser.parse_args()

    config = load_config()
    module_config = config["modules"][args.module]

    tf_dir = os.path.join(os.path.dirname(__file__), module_config["terraform_dir"])

    print(f"\n🚀 Deploying module: {args.module}")
    terraform.init(tf_dir)
    terraform.apply(tf_dir)

    outputs = terraform.output(tf_dir)

    # Add timing metrics

    import time

    start = time.time()
    # run tests
    print(f"Time: {time.time() - start}")

    print("\n🧪 Running tests...")

    for _ in range(5):
        try:
            # test call
            run_tests(module_config["tests"], outputs)
            break
        except Exception as e:
            print(f"Test attempt failed: {e}")
            time.sleep(5)

    if args.destroy:
        print("\n🔥 Destroying infrastructure...")
        terraform.destroy(tf_dir)


if __name__ == "__main__":
    main()
