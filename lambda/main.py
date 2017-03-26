#!/usr/bin/env python

import os
import json
import boto3

r53client = boto3.client('route53')

def find_zone_id(dnsname):
    ''' Return zoneid of the given HostedZone NAME '''
    response = r53client.list_hosted_zones_by_name(
            DNSName=dnsname
        )
    return response['HostedZones'][0]['Id'].split('/')[-1]

def update_route53(source, target):
    return

def check_matching(dnsrecord, cfdistro):
    '''
    If 'dnsrecord' matches the 'match' then return true
    otherwise, return false
    '''
    response = r53client.list_resource_record_sets(
        HostedZoneId=find_zone_id(os.environ['HostedZoneName']),
        StartRecordName=dnsrecord,
        MaxItems='1'
    )
    dns = response['ResourceRecordSets'][0]['AliasTarget']['DNSName']
    if dns == cfdistro:
        return True
    else:
        return False

def lambda_handler(event, context):
    # If an event comes in:
    #   If the event is from the site that matches the CNAME, then switch it
    #   If the event is from the site that doesn't match the CNAME, exit
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    print(sns_message)
    endpoint = sns_message['AlarmDescription']
    print(endpoint)
    if check_matching(os.environ['PrimaryUrl'], endpoint ):
        # update_route53()
        print("I should change the DNS record now")
    else:
        # publish to SNS?
        print("Nothing to do here, exiting")
