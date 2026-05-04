import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)
    region = outputs["aws_region"]["value"]
    ssm = boto3.client("ssm", region_name=region)
    secretsmanager = boto3.client("secretsmanager", region_name=region)

    parameter_names = outputs["parameter_names"]["value"]
    parameter_arns = outputs["parameter_arns"]["value"]
    secret_arn = outputs["secret_arn"]["value"]

    print("Checking config and secrets slice")
    print(f"SSM parameters: {len(parameter_names)}")
    print(f"Secret ARN: {secret_arn}")

    _check_ssm_parameters_exist(ssm, parameter_names, parameter_arns)
    print("✅ SSM parameters exist and ARNs match")

    _check_ssm_parameter_values(ssm, parameter_names)
    print("✅ SSM parameter values are readable")

    _check_secret_exists(secretsmanager, secret_arn)
    print("✅ Secrets Manager secret exists")

    _check_secret_value(secretsmanager, secret_arn)
    print("✅ Secret value is readable")

    _check_secret_metadata(secretsmanager, secret_arn)
    print("✅ Secret metadata check passed")

    print("✅ Config and secrets test passed")


def _check_ssm_parameters_exist(ssm, parameter_names, parameter_arns):
    assert isinstance(parameter_names, list), "parameter_names output must be a list"
    assert len(parameter_names) > 0, "No SSM parameter names provided"

    response = ssm.get_parameters(
        Names=parameter_names,
        WithDecryption=True,
    )

    found_parameters = response.get("Parameters", [])
    invalid_parameters = response.get("InvalidParameters", [])

    assert (
        len(invalid_parameters) == 0
    ), f"Invalid or missing SSM parameters: {invalid_parameters}"

    found_by_name = {param["Name"]: param for param in found_parameters}

    for name in parameter_names:
        assert name in found_by_name, f"SSM parameter not found: {name}"

    if isinstance(parameter_arns, dict):
        for key, arn in parameter_arns.items():
            matched = [param for param in found_parameters if param["ARN"] == arn]

            assert len(matched) == 1, (
                f"SSM parameter ARN from output not found. " f"Key={key}, ARN={arn}"
            )

    elif isinstance(parameter_arns, list):
        found_arns = {param["ARN"] for param in found_parameters}

        for arn in parameter_arns:
            assert arn in found_arns, f"SSM parameter ARN not found: {arn}"


def _check_ssm_parameter_values(ssm, parameter_names):
    response = ssm.get_parameters(
        Names=parameter_names,
        WithDecryption=True,
    )

    parameters = response["Parameters"]

    for param in parameters:
        name = param["Name"]
        value = param.get("Value")

        assert value is not None, f"SSM parameter has no value: {name}"
        assert value != "", f"SSM parameter value is empty: {name}"

        assert param["Type"] in [
            "String",
            "SecureString",
        ], f"Unexpected SSM parameter type for {name}: {param['Type']}"


def _check_secret_exists(secretsmanager, secret_arn):
    response = secretsmanager.describe_secret(
        SecretId=secret_arn,
    )

    assert (
        response["ARN"] == secret_arn
    ), f"Secret ARN mismatch. Expected {secret_arn}, got {response['ARN']}"

    assert (
        response.get("DeletedDate") is None
    ), f"Secret is scheduled for deletion: {secret_arn}"


def _check_secret_value(secretsmanager, secret_arn):
    response = secretsmanager.get_secret_value(
        SecretId=secret_arn,
    )

    assert "SecretString" in response, "Secret does not contain SecretString"

    secret_value = response["SecretString"]

    assert secret_value is not None, "SecretString is None"
    assert secret_value != "", "SecretString is empty"


def _check_secret_metadata(secretsmanager, secret_arn):
    response = secretsmanager.describe_secret(
        SecretId=secret_arn,
    )

    assert response.get("Name"), "Secret has no name"
    assert response.get("CreatedDate"), "Secret has no CreatedDate"

    rotation_enabled = response.get("RotationEnabled", False)

    if rotation_enabled:
        assert response.get(
            "RotationRules"
        ), "Secret rotation is enabled but RotationRules are missing"

    print(f"ℹ️ Secret rotation enabled: {rotation_enabled}")
