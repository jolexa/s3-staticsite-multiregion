#!/usr/bin/env python

import argparse
import boto3

parser = argparse.ArgumentParser(description='Find Output')
parser.add_argument("--stack-name", dest="stackname", required=True)
parser.add_argument("--region", dest="region", required=True)
args = parser.parse_args()

client = boto3.client('cloudformation', region_name=args.region)
response = client.describe_stacks(
    StackName=args.stackname
    )

# loop through outputs and find the correct one
for output in response['Stacks'][0]['Outputs']:
    if output['OutputKey'] == "StandbyReplBucketArn":
        print output['OutputValue']
