# These variables need to be changed
STACKNAME_BASE="s3-staticsite-multiregion"
PRIMARY_REGION="ca-central-1"
STANDBY_REGION="us-west-2"
PRIMARY_URL="static-site.jolexa.us"
STANDBY_URL="static-site-standby.jolexa.us"
ZONE="jolexa.us."
BUCKET_US_EAST1="s3-staticsite-multiregion-artifacts"
# These are helper variables
PRIMARY_STACKNAME="$(STACKNAME_BASE)-primary"
STANDBY_STACKNAME="$(STACKNAME_BASE)-standby"

deploy-all: deploy-standby deploy-primary

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
	# It is easiest, though not impossible to do otherwise, to put the lambda in
	# the same region as the SNS topic
	aws cloudformation deploy \
		--template-file standby-region-alarms.yml \
		--stack-name $(STANDBY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "StandbyHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key StandbyHealthCheckId --stack-name $(STANDBY_STACKNAME)-infra)" \
		"CloudFrontDistributionDomainName=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key CloudFrontDistributionDomainName --stack-name $(STANDBY_STACKNAME)-infra)" \
		"HostedZoneName=$(ZONE)" \
		"PrimaryUrl=$(PRIMARY_URL)" \
		"StandbyUrl=$(STANDBY_URL)" \
		"MyInfraStackName=$(STANDBY_STACKNAME)-infra" \
		"MyInfraStackRegion=$(STANDBY_REGION)" \
		"OtherInfraStackName=$(PRIMARY_STACKNAME)-infra" \
		"OtherInfraStackRegion=$(PRIMARY_REGION)" \
		"DeploymentBucket=$(BUCKET_US_EAST1)" \
		--capabilities CAPABILITY_IAM || exit 0

prep:
	aws s3 cp --acl public-read ./nested-route53.yml s3://$(BUCKET_US_EAST1)/
	cd lambda && zip -r9 deployment.zip main.py && \
		aws s3 cp ./deployment.zip s3://$(BUCKET_US_EAST1)/ && \
		rm -f deployment.zip

deploy-acm: prep
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

deploy-primary: deploy-primary-infra
	# Cloudwatch alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	# It is easiest, though not impossible to do otherwise, to put the lambda in
	# the same region as the SNS topic
	aws cloudformation deploy \
		--template-file primary-region-alarms.yml \
		--stack-name $(PRIMARY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "PrimaryHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key PrimaryHealthCheckId --stack-name $(PRIMARY_STACKNAME)-infra)" \
		"CloudFrontDistributionDomainName=$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key CloudFrontDistributionDomainName --stack-name $(PRIMARY_STACKNAME)-infra)" \
		"HostedZoneName=$(ZONE)" \
		"PrimaryUrl=$(PRIMARY_URL)" \
		"StandbyUrl=$(STANDBY_URL)" \
		"MyInfraStackName=$(PRIMARY_STACKNAME)-infra" \
		"MyInfraStackRegion=$(PRIMARY_REGION)" \
		"OtherInfraStackName=$(STANDBY_STACKNAME)-infra" \
		"OtherInfraStackRegion=$(STANDBY_REGION)" \
		"DeploymentBucket=$(BUCKET_US_EAST1)" \
		--capabilities CAPABILITY_IAM || exit 0


push-html-primary-bucket:
	aws s3 sync --sse --acl public-read --storage-class REDUCED_REDUNDANCY html/ \
		s3://$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key PrimaryS3BucketName --stack-name $(PRIMARY_STACKNAME)-infra)/
	scripts/invalidate-all.py $(PRIMARY_URL)
