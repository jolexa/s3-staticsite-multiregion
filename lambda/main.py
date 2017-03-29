#!/usr/bin/env python

import os
import json
import boto3

r53client = boto3.client('route53')
cfrontclient = boto3.client('cloudfront')

def find_zone_id(dnsname):
    ''' Return zoneid of the given HostedZone NAME '''
    response = r53client.list_hosted_zones_by_name(
            DNSName=dnsname
        )
    return response['HostedZones'][0]['Id'].split('/')[-1]

def update_route53(url, zonename, aliastarget):
    '''
    url = www.example.com
    zonename = example.com
    aliastaget = cloudfront distro, 'asdf1234.cloudfront.net'
    '''
    response = r53client.change_resource_record_sets(
        HostedZoneId=find_zone_id(zonename),
        ChangeBatch={
            'Changes': [
                {
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': url,
                        'Type': 'A',
                        'AliasTarget': {
                            'HostedZoneId': 'Z2FDTNDATAQYW2',
                            'DNSName': aliastarget,
                            'EvaluateTargetHealth': False
                        }
                    }
                },
            ]
        }
    )

def update_cf_cname(distroid, newcname):
    print("update_cf_cname args: {0}, {1}".format(distroid, newcname))
    # Fetch the DistributionConfig
    response = cfrontclient.get_distribution_config(
            Id=distroid
        )
    config = response['DistributionConfig']
    # Take the object and change the Alias (CNAME)
    config['Aliases']['Items'][0] = newcname
    etag = response['ETag']
    response = cfrontclient.update_distribution(
        Id=distroid,
        IfMatch=etag,
        DistributionConfig=config
    )
    return response

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
    aliastarget = response['ResourceRecordSets'][0]['AliasTarget']['DNSName'].rstrip('.')
    if aliastarget == cfdistro:
        return True
    else:
        return False

def get_id(url):
    print("get_id args: {0}".format(url))
    # url: asdf.cloudfront.net
    # return: E2134123ASDF
    # where E2134123ASDF is the id of asdf.cloudfront.net
    paginator = cfrontclient.get_paginator('list_distributions')
    response_iterator = paginator.paginate()
    for i in response_iterator:
        for j in i['DistributionList']['Items']:
            if j['DomainName'] == url:
                return j['Id']

def lambda_handler(event, context):
    # If an event comes in:
    #   If the event is from the site that matches the CNAME, then switch it
    #   If the event is from the site that doesn't match the CNAME, exit
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    print(sns_message)
    alarm_cfendpoint = str(sns_message['AlarmDescription'])
    print(alarm_cfendpoint)
    pdistro = os.environ['PrimaryCloudFrontDistributionDomainName']
    sdistro = os.environ['StandbyCloudFrontDistributionDomainName']
    purl = os.environ['PrimaryUrl']
    surl = os.environ['StandbyUrl']
    print(purl)
    print(surl)
    print(pdistro)
    print(sdistro)
    zonename = os.environ['HostedZoneName']

    if check_matching(purl, alarm_cfendpoint):
        # This means our site is down because the primary url is down!
        '''
        0) update update_cf_cname(standby_cfendpoint, fake.url)
        1) update update_cf_cname(alarm_cfendpoint, standby.url)
        2) update update_cf_cname(standby_cfendpoint, primary.url)
        3) update_route53(primry.url, standby_cfendpoint)
        4) update_route53(standby.url, alarm_cfendpoint)
        5) Send a 'this is dirty mesage' to SNS?
        '''

        # if the alarm is for the primary distro
        if alarm_cfendpoint.lower() == pdistro.lower(): # 'Primary' Context
            # standby distro now responds to fake url (CNAMEAlreadyExists error)
            update_cf_cname(get_id(sdistro), "fake.com")
            # primary distro now responds to standby url (cname)
            update_cf_cname(get_id(pdistro), surl)
            # standby distro now responds to primary url (cname)
            update_cf_cname(get_id(sdistro), purl)
            # primary url is now aliased to standby distro
            update_route53(purl, zonename, sdistro)
            # standby url is now aliased to primary distro
            update_route53(surl, zonename, pdistro)
            '''
            The end result here is that, since the primary distro WAS serving
            the live site, go to a 'dirty' state. That is, deviate from the
            initial stack and serve primary url -> standby distro and serve
            standby url -> primary distro (so you can check to see if the
            primary region is back online, in theory)

            '''

        # If the alarm is for the 'standby' distro.
        # Really the live site because that is the only way to be in this code
        # block
        if alarm_cfendpoint.lower() == sdistro.lower(): # 'Standby' Context
            # primary distro now responds to fake url (CNAMEAlreadyExists error)
            update_cf_cname(get_id(pdistro), "fake.com")
            # standby distro now responds to standby url (cname)
            update_cf_cname(get_id(sdistro), surl)
            # primary distro now responds to primary url (cname)
            update_cf_cname(get_id(pdistro), purl)
            # primary url is now aliased to primary distro
            update_route53(purl, zonename, pdistro)
            # standby url is now aliased to standby distro
            update_route53(surl, zonename, sdistro)
            '''
            The end result here is that, since the standby distro WAS serving
            the live site, go back to state0. That is, primary url -> primary
            distro, standby url -> standby distro
            Very Confusing to wrap head around because I don't think this
            condition will be met very often, UNLESS the stack is left in a
            dirty state after an outage.
            '''

    else:
        # This means, the Standby Url is down which is bad but not worth
        # making the stacks 'dirty'
        # publish to SNS?
        print("Nothing to do here, exiting")
