# utils/terraform.py

import subprocess
import time


def run(cmd, cwd):
    result = subprocess.run(cmd, shell=True, cwd=cwd)
    if result.returncode != 0:
        raise Exception(f"Command failed: {cmd}")


def init(terraform_dir):
    run("terraform init -input=false", terraform_dir)


def apply(terraform_dir):
    run("terraform apply -auto-approve", terraform_dir)


# def destroy(terraform_dir):
#     run("terraform destroy -auto-approve", terraform_dir)


def destroy(terraform_dir, retries=5, delay=60):
    for attempt in range(1, retries + 1):
        result = subprocess.run(
            "terraform destroy -auto-approve", shell=True, cwd=terraform_dir
        )
        if result.returncode == 0:
            return
        if attempt < retries:
            print(f"Destroy attempt {attempt} failed, retrying in {delay}s...")
            time.sleep(delay)
    raise Exception("terraform destroy failed after all retries")


def output(terraform_dir):
    result = subprocess.check_output(
        "terraform output -json", shell=True, cwd=terraform_dir
    )
    return result.decode()
