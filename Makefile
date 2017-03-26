STACKNAME_BASE="static-s3-region-failure"
PRIMARY_REGION="ca-central-1"
PRIMARY_STACKNAME="$(STACKNAME_BASE)-primary"
STANDBY_REGION="us-west-2"
STANDBY_STACKNAME="$(STACKNAME_BASE)-standby"
PRIMARY_URL="static-site.jolexa.us"
STANDBY_URL="static-site-standby.jolexa.us"
ZONE="jolexa.us."

deploy-all: deploy-standby deploy-primary deploy-route53

deploy-standby-infra: deploy-acm
	aws cloudformation deploy \
		--template-file standby-region-infra.yml \
		--stack-name $(STANDBY_STACKNAME)-infra \
		--region $(STANDBY_REGION) \
		--parameter-overrides "ACMCertArn=$(shell scripts/find-cfn-output-value.py --region us-east-1 --stack-name $(STACKNAME_BASE)-acm-certs --output-key ACMCertArn)" \
		"ZoneName=$(ZONE)" \
		"SiteURL=$(STANDBY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-standby: deploy-standby-infra
	# Cloudwatch alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	# It is easiest, though not impossible to do otherwise, to put the lambda in
	# the same region as the SNS topic
	aws cloudformation package \
		--template-file standby-region-alarms.yml \
		--s3-bucket static-s3-region-failure-artifacts \
		--output-template-file new-standby-region-alarms.yml
	aws cloudformation deploy \
		--template-file new-standby-region-alarms.yml \
		--stack-name $(STANDBY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "StandbyHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key StandbyHealthCheckId --stack-name $(STANDBY_STACKNAME)-infra)" \
		"StandbyCloudFrontDistributionDomainName=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key StandbyCloudFrontDistributionDomainName --stack-name $(STANDBY_STACKNAME)-infra)" \
		"HostedZoneName=$(ZONE)" \
		"StandbyUrl=$(PRIMARY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0
	rm -f new-standby-region-alarms.yml

deploy-acm:
	# HACK: ACM Must be in us-east-1 for CloudFront distros
	aws cloudformation deploy \
		--template-file acm-certs.yml \
		--stack-name $(STACKNAME_BASE)-acm-certs \
		--region us-east-1 \
		--parameter-overrides "ACMUrl=$(PRIMARY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary-infra: deploy-acm
	aws cloudformation deploy \
		--template-file primary-region-infra.yml \
		--stack-name $(PRIMARY_STACKNAME)-infra \
		--region $(PRIMARY_REGION) \
		--parameter-overrides "StandbyReplBucketArn=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key StandbyReplBucketArn --stack-name $(STANDBY_STACKNAME)-infra)" \
		"ACMCertArn=$(shell scripts/find-cfn-output-value.py --region us-east-1 --stack-name $(STACKNAME_BASE)-acm-certs --output-key ACMCertArn)" \
		"SiteURL=$(PRIMARY_URL)" \
		"ZoneName=$(ZONE)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-route53: deploy-primary-infra deploy-standby-infra
	aws cloudformation deploy \
		--template-file primary-route53.yml \
		--stack-name $(PRIMARY_STACKNAME)-route53 \
		--region $(PRIMARY_REGION) \
		--parameter-overrides \
		"PrimarySiteURL=$(PRIMARY_URL)" \
		"ZoneName=$(ZONE)" \
		--capabilities CAPABILITY_IAM || exit 0
	aws cloudformation deploy \
		--template-file standby-route53.yml \
		--stack-name $(STANDBY_STACKNAME)-route53 \
		--region $(STANDBY_REGION) \
		--parameter-overrides \
		"StandbySiteURL=$(STANDBY_URL)" \
		"ZoneName=$(ZONE)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary: deploy-primary-infra
	# Cloudwatch alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	# It is easiest, though not impossible to do otherwise, to put the lambda in
	# the same region as the SNS topic
	aws cloudformation package \
		--template-file primary-region-alarms.yml \
		--s3-bucket static-s3-region-failure-artifacts \
		--output-template-file new-primary-region-alarms.yml
	aws cloudformation deploy \
		--template-file new-primary-region-alarms.yml \
		--stack-name $(PRIMARY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "PrimaryHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key PrimaryHealthCheckId --stack-name $(PRIMARY_STACKNAME)-infra)" \
		"PrimaryCloudFrontDistributionDomainName=$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key PrimaryCloudFrontDistributionDomainName --stack-name $(PRIMARY_STACKNAME)-infra)" \
		"HostedZoneName=$(ZONE)" \
		"PrimaryUrl=$(PRIMARY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0
	rm -f new-primary-region-alarms.yml
