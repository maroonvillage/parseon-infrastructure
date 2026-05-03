import boto3
import json


def run(outputs_raw):
    outputs = json.loads(outputs_raw)

    region = outputs["aws_region"]["value"]
    ec2 = boto3.client("ec2", region_name=region)

    vpc_id = outputs["vpc_id"]["value"]
    public_subnet_ids = outputs["public_subnet_ids"]["value"]
    private_subnet_ids = outputs["private_subnet_ids"]["value"]

    print(f"Checking VPC: {vpc_id}")

    # Check VPC exists
    vpcs = ec2.describe_vpcs(VpcIds=[vpc_id])["Vpcs"]
    assert len(vpcs) == 1, f"VPC not found: {vpc_id}"

    vpc = vpcs[0]
    assert vpc["State"] == "available", f"VPC is not available: {vpc['State']}"

    print("✅ VPC exists and is available")

    # Check public subnets
    public_subnets = ec2.describe_subnets(SubnetIds=public_subnet_ids)["Subnets"]
    assert len(public_subnets) == len(public_subnet_ids), "Not all public subnets found"

    for subnet in public_subnets:
        assert (
            subnet["State"] == "available"
        ), f"Public subnet not available: {subnet['SubnetId']}"
        assert (
            subnet["MapPublicIpOnLaunch"] is True
        ), f"Public subnet does not map public IPs on launch: {subnet['SubnetId']}"

    print("✅ Public subnets exist and auto-assign public IPs")

    # Check private subnets
    private_subnets = ec2.describe_subnets(SubnetIds=private_subnet_ids)["Subnets"]
    assert len(private_subnets) == len(
        private_subnet_ids
    ), "Not all private subnets found"

    for subnet in private_subnets:
        assert (
            subnet["State"] == "available"
        ), f"Private subnet not available: {subnet['SubnetId']}"
        assert (
            subnet["MapPublicIpOnLaunch"] is False
        ), f"Private subnet should not map public IPs on launch: {subnet['SubnetId']}"

    print("✅ Private subnets exist and do not auto-assign public IPs")

    # Check Internet Gateway attached to VPC
    igws = ec2.describe_internet_gateways(
        Filters=[
            {
                "Name": "attachment.vpc-id",
                "Values": [vpc_id],
            }
        ]
    )["InternetGateways"]

    assert len(igws) > 0, f"No Internet Gateway attached to VPC: {vpc_id}"

    print("✅ Internet Gateway attached")

    # Check NAT Gateways exist
    nat_gateways = ec2.describe_nat_gateways(
        Filters=[
            {
                "Name": "vpc-id",
                "Values": [vpc_id],
            },
            {
                "Name": "state",
                "Values": ["available"],
            },
        ]
    )["NatGateways"]

    assert len(nat_gateways) > 0, f"No available NAT Gateway found in VPC: {vpc_id}"

    print(f"✅ NAT Gateway available: {len(nat_gateways)} found")

    # Check route tables
    route_tables = ec2.describe_route_tables(
        Filters=[
            {
                "Name": "vpc-id",
                "Values": [vpc_id],
            }
        ]
    )["RouteTables"]

    assert len(route_tables) > 0, f"No route tables found for VPC: {vpc_id}"

    print("✅ Route tables found")

    # Validate public route table has route to Internet Gateway
    public_route_found = False

    for rt in route_tables:
        for route in rt.get("Routes", []):
            if route.get("DestinationCidrBlock") == "0.0.0.0/0" and route.get(
                "GatewayId", ""
            ).startswith("igw-"):
                public_route_found = True

    assert public_route_found, "No public route table route to Internet Gateway found"

    print("✅ Public route to Internet Gateway exists")

    # Validate private route table has route to NAT Gateway
    private_nat_route_found = False

    for rt in route_tables:
        for route in rt.get("Routes", []):
            if route.get("DestinationCidrBlock") == "0.0.0.0/0" and route.get(
                "NatGatewayId", ""
            ).startswith("nat-"):
                private_nat_route_found = True

    assert private_nat_route_found, "No private route table route to NAT Gateway found"

    print("✅ Private route to NAT Gateway exists")

    # Validate subnets are distributed across availability zones
    all_subnets = public_subnets + private_subnets
    azs = {subnet["AvailabilityZone"] for subnet in all_subnets}

    assert (
        len(azs) >= 2
    ), "Subnets are not distributed across at least two Availability Zones"

    print(f"✅ Subnets span multiple Availability Zones: {', '.join(sorted(azs))}")

    print("✅ Networking test passed")
