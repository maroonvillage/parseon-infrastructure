# utils/terraform.py

import subprocess


def run(cmd, cwd):
    result = subprocess.run(cmd, shell=True, cwd=cwd)
    if result.returncode != 0:
        raise Exception(f"Command failed: {cmd}")


def init(terraform_dir):
    run("terraform init -input=false", terraform_dir)


def apply(terraform_dir):
    run("terraform apply -auto-approve", terraform_dir)


def destroy(terraform_dir):
    run("terraform destroy -auto-approve", terraform_dir)


def output(terraform_dir):
    result = subprocess.check_output(
        "terraform output -json", shell=True, cwd=terraform_dir
    )
    return result.decode()
