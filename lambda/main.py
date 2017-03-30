#!/usr/bin/env python

import os
import json
import boto3

def find_zone_id(dnsname):
    ''' Return zoneid of the given HostedZone NAME '''
    r53client = boto3.client('route53')
    response = r53client.list_hosted_zones_by_name(
            DNSName=dnsname
        )
    return response['HostedZones'][0]['Id'].split('/')[-1]

def is_live_site(cfdistro):
    '''
    if 'cfdistro' is the target of the PrimaryUrl
        return True
    '''
    r53client = boto3.client('route53')
    response = r53client.list_resource_record_sets(
        HostedZoneId=find_zone_id(os.environ['HostedZoneName']),
        StartRecordName=os.environ['PrimaryUrl'],
        MaxItems='1'
    )
    aliastarget = response['ResourceRecordSets'][0]['AliasTarget']['DNSName'].rstrip('.')
    if aliastarget == cfdistro:
        return True
    else:
        return False

def update_cf_cname(distroid, newcname):
    '''
    It is ok to do this outside of cloudformation because resource can
    still be managed with cloudformation
    '''
    print("update_cf_cname args: {0}, {1}".format(distroid, newcname))
    cfrontclient = boto3.client('cloudfront')
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

def get_cloudformation_params(stackname, region='ca-central-1'):
    cfn = boto3.client('cloudformation', region_name=region)
    return cfn.describe_stacks(StackName=stackname)['Stacks'][0]['Parameters']

def get_cloudformation_outputs(stackname, region='ca-central-1'):
    cfn = boto3.client('cloudformation', region_name=region)
    return cfn.describe_stacks(StackName=stackname)['Stacks'][0]['Outputs']

def get_cloudformation_template(stackname, region='ca-central-1'):
    cfn = boto3.client('cloudformation', region_name=region)
    return cfn.get_template(StackName=stackname)['TemplateBody']

def update_stack(stackname, siteurl, region='ca-central-1'):
    cfn = boto3.client('cloudformation', region_name=region)
    #template = get_cloudformation_template(stackname, region)
    params = get_cloudformation_params(stackname, region)
    # change the Param for SiteURL
    for i in params:
        if i['ParameterKey'] == "SiteURL":
            i['ParameterValue'] = siteurl
    # Issue update stack command
    cfn.update_stack(
        StackName=stackname,
        UsePreviousTemplate=True,
        Parameters=params,
        Capabilities=['CAPABILITY_IAM']
        )

def get_cf_id_from_cfn(stackname, region='ca-central-1'):
    print("get_cf_id_from_cfn args: {0} {1}".format(stackname, region))
    outputs = get_cloudformation_outputs(stackname, region)
    for i in outputs:
        if i['OutputKey'] == "CloudFrontDistributionID":
            return i['OutputValue']

def lambda_handler(event, context):
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    print(sns_message)
    alarm_cfendpoint = str(sns_message['AlarmDescription'])
    print(alarm_cfendpoint)
    purl = os.environ['PrimaryUrl']
    surl = os.environ['StandbyUrl']

    if is_live_site(alarm_cfendpoint):
        # This means our site is down because the primary url is down!
        # In other words, this alert is actionable
        '''
        This lambda function only triggers for one healthcheck. It is a 1:1
        mapping. So, at this point in time:
            Live = "MyStack"
            Non-Live = "OtherStack"
        which will be reversed at the end of this sequence

        1) Update the Non-Live CF Distro with SiteUrl = "temp.com"
            This should be done in boto because we don't want the cfn stack to
            site In_Progress for 15 mins, yet
        2) Update the Live stack with SiteUrl = StandbyUrl
            - This makes is non-live
            - This is in cfn because we can tolerate the stack being In_Progress
              for some time
        3) Update the Non-Live stack with SiteUrl = PrimaryUrl
            - This is in cfn because we can tolerate the stack being In_Progress
              for some time
        4) That Should be it
        '''
        otherdistro = get_cf_id_from_cfn(os.environ['OtherInfraStackName'],
                region=os.environ['OtherInfraStackRegion'])
        update_cf_cname(otherdistro, "temp.com")

        update_stack(os.environ['MyInfraStackName'],
            os.environ['StandbyUrl'],
            os.environ['MyInfraStackRegion']
            )
        update_stack(os.environ['OtherInfraStackName'],
            os.environ['PrimaryUrl'],
            os.environ['OtherInfraStackRegion']
            )

    else:

        # This means, the Standby Url is down which is bad but not worth
        # making the stacks 'dirty'
        # publish to SNS?
        print("Nothing to do here, exiting")
