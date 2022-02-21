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
aws s3 sync ./ "s3://${S3_BUCKET_NAME}"
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
aws s3api put-bucket-lifecycle-configuration --bucket "${S3_BUCKET_NAME}" --lifecycle-configuration file://pinehead_lifecycle.json
# SILENT SUCCESS: No output given
aws s3api get-bucket-lifecycle-configuration --bucket "${S3_BUCKET_NAME}" | cat
# RULES   sample-s3-to-glacier-rule   Enabled
# EXPIRATION  730
# FILTER  pinehead
# NONCURRENTVERSIONTRANSITIONS    1   15  DEEP_ARCHIVE
# TRANSITIONS 30  GLACIER
