#!/bin/bash
####### AWS Credentials
### Environment Variables
# Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
IFS= read -r AWS_ACCESS_KEY_ID </dev/tty
readonly AWS_ACCESS_KEY_ID
export AWS_ACCESS_KEY_ID
IFS= read -r AWS_SECRET_ACCESS_KEY </dev/tty
readonly AWS_SECRET_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY
IFS= read -r AWS_DEFAULT_REGION </dev/tty
readonly AWS_DEFAULT_REGION
export AWS_DEFAULT_REGION
####### AWS S3API CLI
#### Create-Bucket
# Documentation: https://docs.aws.amazon.com/cli/latest/reference/s3api/create-bucket.html
# Bucket Naming requirements:
# * Start by a letter
# * Only contain lowercase characters and digits, no symbols, dashes.
# ERROR: 'An error occurred (InvalidBucketName) when calling the CreateBucket operation: The specified bucket is not valid.'
# SOLUTION: Follow Bucket Naming requirements
set -x
S3_BUCKET_NAME="$(tr -dc a-z0-9 </dev/urandom | head -c 11)"
{ set +x; } 2>/dev/null
readonly S3_BUCKET_NAME
set -x
aws --region="${AWS_DEFAULT_REGION}" s3api create-bucket --bucket "${S3_BUCKET_NAME}" --acl public-read --output text | cat
# ERROR: 'An error occurred (IllegalLocationConstraintException) when calling the CreateBucket operation: The unspecified location constraint is incompatible for the region specific endpoint this request was sent to.'
# SOLUTION: Add specification flag --region
# Your user may have permissions to access at a specific region only
# + aws s3api create-bucket --bucket dtfgrg734a4 --acl public-read --output text
# /dtfgrg734a4
{ set +x; } 2>/dev/null
# public-access-block documentation: https://stackoverflow.com/questions/63389666/block-all-objects-public-access-in-s3-by-cli
# get-public-access-block
aws --region="${AWS_DEFAULT_REGION}" s3api get-public-access-block --bucket "${S3_BUCKET_NAME}" --output json | jq
# ERROR: An error occurred (NoSuchPublicAccessBlockConfiguration) when calling the GetPublicAccessBlock operation: The public access block configuration was not found
# SOLUTION: Execute the following command to set public-access-block for bucket
aws --region="${AWS_DEFAULT_REGION}" s3api put-public-access-block \
--bucket "${S3_BUCKET_NAME}" \
--public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
# SILENT SUCCESS: No output given
# public-access-block documentation: https://stackoverflow.com/questions/63389666/block-all-objects-public-access-in-s3-by-cli
aws --region="${AWS_DEFAULT_REGION}" s3api get-public-access-block --bucket "${S3_BUCKET_NAME}" --output json | jq
# {
#   "PublicAccessBlockConfiguration": {
#     "BlockPublicAcls": false,
#     "IgnorePublicAcls": false,
#     "BlockPublicPolicy": false,
#     "RestrictPublicBuckets": false
#   }
# }
##### Upload a folder's contents
# clone project folder
git clone https://github.com/tia-la/ccp.git
cd ccp || exit
aws --region="${AWS_DEFAULT_REGION}" s3 sync ./ "s3://${S3_BUCKET_NAME}"
##### Create lifecycle transition to Glacier S3 objects of prefix pinehead
cat<<EOF>pinehead_lifecycle.json
{
    "Rules": [
        {
            "ID": "sample-s3-to-glacier-rule",
            "Filter": {
                "Prefix": "pinehead"
            },
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 15,
                    "StorageClass": "DEEP_ARCHIVE",
                    "NewerNoncurrentVersions": 1
                }
            ],
            "Expiration": {
                    "Days": 730
            }
        }
    ]
}
EOF
aws --region="${AWS_DEFAULT_REGION}" s3api put-bucket-lifecycle-configuration --bucket "${S3_BUCKET_NAME}" --lifecycle-configuration file://pinehead_lifecycle.json
# SILENT SUCCESS: No output given
aws --region="${AWS_DEFAULT_REGION}" s3api get-bucket-lifecycle-configuration --bucket "${S3_BUCKET_NAME}" | cat
# RULES   sample-s3-to-glacier-rule   Enabled
# EXPIRATION  730
# FILTER  pinehead
# NONCURRENTVERSIONTRANSITIONS    1   15  DEEP_ARCHIVE
# TRANSITIONS 30  GLACIER
#### Configure S3 Bucket to Host a Static Website with a Custom Domain
## Route 53 List Hosted Zones
aws --region="${AWS_DEFAULT_REGION}" route53 list-hosted-zones --output json | jq
# {
#   "HostedZones": [
#     {
#       "Id": "/hostedzone/Z06776831VVYJZODRDBD9",
#       "Name": "xxxremovedxxx.info.",
#       "CallerReference": "xxxremovedxxx.info2020-05-05 18:08:38.260245",
#       "Config": {
#         "Comment": "",
#         "PrivateZone": false
#       },
#       "ResourceRecordSetCount": 2
#     }
#   ]
# }
## Route 53 List Records of Hosted Zone
aws --region="${AWS_DEFAULT_REGION}" route53 list-resource-record-sets --hosted-zone-id Z06776831VVYJZODRDBD9 --output json | jq
# {
#   "ResourceRecordSets": [
#     {
#       "Name": "xxxremovedxxx.info.",
#       "Type": "NS",
#       "TTL": 172800,
#       "ResourceRecords": [
#         {
#           "Value": "ns-1162.awsdns-17.org."
#         }
#       ]
#     },
#     {
#       "Name": "xxxremovedxxx.info.",
#       "Type": "SOA",
#       "TTL": 900,
#       "ResourceRecords": [
#         {
#           "Value": "ns-1162.awsdns-17.org. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400"
#         }
#       ]
#     }
#   ]
# }
## Create S3 bucket with the name of the public domain and public access
aws --region="${AWS_DEFAULT_REGION}" s3api create-bucket --bucket xxxremovedxxx.info --acl public-read --output text | cat
## Upload static website files
for item in *.html; do aws --region="${AWS_DEFAULT_REGION}" s3 cp "./${item}" s3://xxxremovedxxx.info/; done
## Enable S3 Bucket status website hosting
aws --region="${AWS_DEFAULT_REGION}" s3 website s3://xxxremovedxxx.info/ --index-document index.html --error-document error.html
## Route 53 Create Alias A record
# S3 Hosted Zone ID Reference https://docs.aws.amazon.com/general/latest/gr/s3.html
# ELB Hosted Zone ID Reference https://docs.aws.amazon.com/general/latest/gr/elb.html
cat<<EOF>xxxremovedxxx.info_create_s3_record.json
{
  "Comment": "Create Alias xxxremovedxxx.info",
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
            "Name": "xxxremovedxxx.info",
            "Type": "A",
            "AliasTarget": {
                "HostedZoneId": "Z3AQBSTGFYJSTF",
                "DNSName": "xxxremovedxxx.info.s3-website-us-east-1.amazonaws.com",
                "EvaluateTargetHealth": false
            }
        }
    }
  ]
}
EOF
aws --region="${AWS_DEFAULT_REGION}" route53 change-resource-record-sets --hosted-zone-id Z06776831VVYJZODRDBD9 --change-batch file://xxxremovedxxx.info_create_s3_record.json --output json | jq
# {
#   "ChangeInfo": {
#     "Id": "/change/C083286627PAAPSDU2CRX",
#     "Status": "PENDING",
#     "SubmittedAt": "2022-02-23T22:17:49.467000+00:00",
#     "Comment": "Creating Alias xxxremovedxxx.info"
#   }
# }
### Errors
# Parameter Validation failed: Missing required parameter in ChangeBatch.Changes[0]: "ResourceRecordSet"
# Unknown parameter in ChangeBatch.Changes[0].ResourceRecordSet: "ResourceRecord", must be one of: Name, Type, SetIdentifier, Weight, Region, GeoLocation, Failover, MultiValueAnswer, TTL, ResourceRecords, AliasTarget, HealthCheckId, TrafficPolicyInstanceId
### Invalid JSON
# Error parsing parameter '--change-batch': Invalid JSON: Expecting ',' delimiter: line 10 column 13 (char 227)
### Missing mandatory fields All of TTL, ResourceRecords
# An error occurred (InvalidInput) when calling the ChangeResourceRecordSets operation: Invalid request: Expected exactly one of [AliasTarget, all of [TTL, and ResourceRecords], or TrafficPolicyInstanceId], but found none in Change with [Action=CREATE, Name=xxxremovedxxx.info, Type=CNAME, SetIdentifier=null]
### Invalid change batch (permissions)
# An error occurred (InvalidChangeBatch) when calling the ChangeResourceRecordSets operation: [RRSet of type CNAME with DNS name xxxremovedxxx.info. is not permitted at apex in zone xxxremovedxxx.info.]
### Record already exists. To resolve, delete existint record and recreate
# An error occurred (InvalidChangeBatch) when calling the ChangeResourceRecordSets operation: [Tried to create resource record set [name='xxxremovedxxx.info.', type='A'] but it already exists]

## Route 53 Delete record
cat<<EOF>xxxremovedxxx.info_delete_s3_record.json
{
  "Comment": "Delete Alias xxxremovedxxx.info",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
            "Name": "xxxremovedxxx.info",
            "Type": "A",
            "AliasTarget": {
                "HostedZoneId": "Z3AQBSTGFYJSTF",
                "DNSName": "xxxremovedxxx.info.s3-website-us-east-1.amazonaws.com",
                "EvaluateTargetHealth": false
            }
        }
    }
  ]
}
EOF
aws --region="${AWS_DEFAULT_REGION}" route53 change-resource-record-sets --hosted-zone-id Z06776831VVYJZODRDBD9 --change-batch file://xxxremovedxxx.info_delete_s3_record.json --output json | jq
# {
#   "ChangeInfo": {
#     "Id": "/change/C08882171JXGD4EIJJZT8",
#     "Status": "PENDING",
#     "SubmittedAt": "2022-02-23T22:27:42.461000+00:00",
#     "Comment": "Delete Alias xxxremovedxxx.info"
#   }
# }
### Errors
### Record doesn't exist: not found
# An error occurred (InvalidChangeBatch) when calling the ChangeResourceRecordSets operation: [Tried to delete resource record set [name='xxxremovedxxx.info.', type='A'] but it was not found]
### Record doesn't match
# Error: Tried to delete resource record set [name='xxxremovedxxx.info.', type='A'] but the values provided do not match the current values

### Route 53 retrieve resource record sets
aws --region="${AWS_DEFAULT_REGION}" route53 list-resource-record-sets --hosted-zone-id Z06776831VVYJZODRDBD9 --output json | jq
# {
#     "Name": "xxxremovedxxx.info.",
#     "Type": "A",
#     "AliasTarget": {
#     "HostedZoneId": "Z3AQBSTGFYJSTF",
#     "DNSName": "xxxremovedxxx.info.s3-website-us-east-1.amazonaws.com.",
#     "EvaluateTargetHealth": false
#     }
# },
