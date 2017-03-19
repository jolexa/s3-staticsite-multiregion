ACCOUNT=$(shell aws sts get-caller-identity --query Account --output text)
PRIMARY_REGION="ca-central-1"
STANDBY_REGION="us-west-2"

deploy-all: deploy-primary deploy-standby

deploy-standby-infra:
	aws cloudformation deploy \
		--template-file backup-region-infra.yml \
		--stack-name static-s3-region-failure-standby-infra \
		--region $(STANDBY_REGION) \
		--capabilities CAPABILITY_IAM || exit 0

deploy-standby: deploy-standby-infra
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file backup-region-alarms.yml \
		--stack-name static-s3-region-failure-standby-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell aws cloudformation --region $(STANDBY_REGION) describe-stacks --stack-name static-s3-region-failure-standby-infra --query Stacks[0].Outputs[0].OutputValue --output text)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary-infra:
	aws cloudformation deploy \
		--template-file primary-region-infra.yml \
		--stack-name static-s3-region-failure-primary-infra \
		--region $(PRIMARY_REGION) \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary: deploy-primary-infra
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file primary-region-alarms.yml \
		--stack-name static-s3-region-failure-primary-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell aws cloudformation --region $(PRIMARY_REGION) describe-stacks --stack-name static-s3-region-failure-primary-infra --query Stacks[0].Outputs[0].OutputValue --output text)" \
		--capabilities CAPABILITY_IAM || exit 0
