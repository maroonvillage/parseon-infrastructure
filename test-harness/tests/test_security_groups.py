import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    region = outputs["aws_region"]["value"]
    ec2 = boto3.client("ec2", region_name=region)

    alb_sg_id = outputs["alb_security_group_id"]["value"]
    ecs_api_sg_id = outputs["ecs_api_security_group_id"]["value"]
    rds_sg_id = outputs["rds_security_group_id"]["value"]

    container_port = int(outputs.get("container_port", {}).get("value", 8000))
    db_port = int(outputs.get("db_port", {}).get("value", 5432))

    print("Checking security groups")
    print(f"ALB SG: {alb_sg_id}")
    print(f"ECS API SG: {ecs_api_sg_id}")
    print(f"RDS SG: {rds_sg_id}")

    sg_ids = [alb_sg_id, ecs_api_sg_id, rds_sg_id]

    response = ec2.describe_security_groups(GroupIds=sg_ids)
    groups = {sg["GroupId"]: sg for sg in response["SecurityGroups"]}

    assert alb_sg_id in groups, f"ALB security group not found: {alb_sg_id}"
    assert ecs_api_sg_id in groups, f"ECS api security group not found: {ecs_api_sg_id}"
    assert rds_sg_id in groups, f"RDS security group not found: {rds_sg_id}"

    print("✅ Security groups exist")

    alb_sg = groups[alb_sg_id]
    ecs_api_sg = groups[ecs_api_sg_id]
    rds_sg = groups[rds_sg_id]

    # ALB should allow inbound HTTP and/or HTTPS from the internet.
    alb_allows_http = _allows_cidr_ingress(
        alb_sg,
        port=80,
        cidr="0.0.0.0/0",
    )

    alb_allows_https = _allows_cidr_ingress(
        alb_sg,
        port=443,
        cidr="0.0.0.0/0",
    )

    assert (
        alb_allows_http or alb_allows_https
    ), "ALB security group does not allow inbound HTTP or HTTPS from 0.0.0.0/0"

    print("✅ ALB allows public HTTP/HTTPS ingress")

    # ECS should allow inbound traffic only from ALB SG on the app/container port.
    ecs_allows_alb = _allows_sg_ingress(
        ecs_api_sg,
        port=container_port,
        source_sg_id=alb_sg_id,
    )

    assert (
        ecs_allows_alb
    ), f"ECS security group does not allow ALB SG on port {container_port}"

    print(f"✅ ECS allows ALB ingress on port {container_port}")

    ecs_public_ingress = _has_public_ingress(ecs_api_sg)
    assert not ecs_public_ingress, "ECS security group has public ingress"

    print("✅ ECS is not publicly reachable")

    # RDS should allow inbound traffic only from ECS SG on the DB port.
    rds_allows_ecs = _allows_sg_ingress(
        rds_sg,
        port=db_port,
        source_sg_id=ecs_api_sg_id,
    )

    assert rds_allows_ecs, f"RDS security group does not allow ECS SG on port {db_port}"

    print(f"✅ RDS allows ECS ingress on port {db_port}")

    rds_public_ingress = _has_public_ingress(rds_sg)
    assert not rds_public_ingress, "RDS security group has public ingress"

    print("✅ RDS is not publicly reachable")

    # Confirm all security groups are in the same VPC.
    vpc_ids = {
        alb_sg["VpcId"],
        ecs_api_sg["VpcId"],
        rds_sg["VpcId"],
    }

    assert len(vpc_ids) == 1, f"Security groups are not in the same VPC: {vpc_ids}"

    print(f"✅ Security groups are in the same VPC: {list(vpc_ids)[0]}")

    print("✅ Security group test passed")


def _allows_cidr_ingress(security_group, port, cidr):
    for permission in security_group.get("IpPermissions", []):
        if not _permission_matches_port(permission, port):
            continue

        for ip_range in permission.get("IpRanges", []):
            if ip_range.get("CidrIp") == cidr:
                return True

    return False


def _allows_sg_ingress(security_group, port, source_sg_id):
    for permission in security_group.get("IpPermissions", []):
        if not _permission_matches_port(permission, port):
            continue

        for pair in permission.get("UserIdGroupPairs", []):
            if pair.get("GroupId") == source_sg_id:
                return True

    return False


def _permission_matches_port(permission, port):
    ip_protocol = permission.get("IpProtocol")

    if ip_protocol == "-1":
        return True

    from_port = permission.get("FromPort")
    to_port = permission.get("ToPort")

    if from_port is None or to_port is None:
        return False

    return from_port <= port <= to_port


def _has_public_ingress(security_group):
    for permission in security_group.get("IpPermissions", []):
        for ip_range in permission.get("IpRanges", []):
            if ip_range.get("CidrIp") == "0.0.0.0/0":
                return True

        for ipv6_range in permission.get("Ipv6Ranges", []):
            if ipv6_range.get("CidrIpv6") == "::/0":
                return True

    return False
