#!/usr/bin/env python

import os
import json
import time
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
def get_r53_stack_from_cfn(stackname, region='ca-central-1'):
    print("get_r53_stack_from_cfn args: {0} {1}".format(stackname, region))
    outputs = get_cloudformation_outputs(stackname, region)
    for i in outputs:
        if i['OutputKey'] == "Route53StackName":
            return i['OutputValue']

def lambda_handler(event, context):
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    print(sns_message)
    alarm_cfendpoint = str(sns_message['AlarmDescription'])
    print(alarm_cfendpoint)

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
        # Non-Live Distro gets a temp cname
        otherdistro = get_cf_id_from_cfn(os.environ['OtherInfraStackName'],
                region=os.environ['OtherInfraStackRegion'])
        update_cf_cname(otherdistro, "temp.com")

        # Live CNAME becomes Non-Live ("automatically-fixed")
        # This is an odd thing to do because the Route53 stack is nested so it
        # would automatically update. The problem is... there is a race
        # condition between the two stacks and both route53 records are trying
        # to become eachother. Further, since it is a nested stack, it will
        # update again to what we expect. Seems elegant despite the kludge
        myr53stackname = get_r53_stack_from_cfn(os.environ['MyInfraStackName'],
                os.environ['MyInfraStackRegion'])
        update_stack(myr53stackname,
            "automatically-fixed."+os.environ['HostedZoneName'].strip('.'),
            os.environ['MyInfraStackRegion']
            )
        # Live Distro becomes Non-Live
        update_stack(os.environ['MyInfraStackName'],
            os.environ['StandbyUrl'],
            os.environ['MyInfraStackRegion']
            )

        # Hopefully this is enough time to let the Route53 race settle
        print("Sleeping 20 seconds...")
        time.sleep(20)

        # Non-Live CNAME becomes Live
        # Nested stack WOULD get updated eventually but the kicker is that
        # cloudformation won't update it until the CF Distro is done updating.
        # Despite the CF "Deploying" Status, it is serving traffic right away.
        # Therefore, we break out of the nested stack paradigm and update the
        # stack right away
        otherr53stackname = get_r53_stack_from_cfn(os.environ['OtherInfraStackName'],
                os.environ['OtherInfraStackRegion'])
        update_stack(otherr53stackname,
            os.environ['PrimaryUrl'],
            os.environ['OtherInfraStackRegion']
            )
        # Non-Live Distro becomes Live
        update_stack(os.environ['OtherInfraStackName'],
            os.environ['PrimaryUrl'],
            os.environ['OtherInfraStackRegion']
            )

    else:
        # This means, the Standby Url is down which is bad but not worth
        # making the stacks 'dirty'
        # publish to SNS?
        print("Nothing to do here, exiting")
