#!/bin/bash

# Checking the arguments
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <project_name> <role_name> <service_account_name>"
    echo "<project_name>: name of the project you want to have Qovery Secret Manager Access in"
    echo "<role_name>: name of the role to be created for Qovery Secret Manager Access "
    echo "<service_account_name>: name of the service account to be created for Qovery Secret Manager Access"

    exit 1
fi

project_name=$1
role_name=$2
service_account_name=$3

concat_array_to_string() {
    array_ref=("${!1}")  # Create a copy of the array
    result=""
    delimiter="$2"

    for (( i=0; i<${#array_ref[@]}; i++ )); do
        if [ $i -eq 0 ]; then
            result="${array_ref[i]}"
        else
            result="${result}${delimiter}${array_ref[i]}"
        fi
    done

    echo "$result"
}

permissions=(
  "secretmanager.secrets.get"
  "secretmanager.secrets.list"
  "secretmanager.versions.access"
  "secretmanager.versions.get"
  "secretmanager.versions.list"
)

# ROLE
role_id=$(gcloud iam roles describe $role_name --project=$project_name --format=json --verbosity=none --quiet | jq -r '.name // ""')
if [ -z "$role_id" ]; then
    echo "Role ${role_name} doesn't exist, creating it"
    gcloud iam roles create ${role_name} --description="Qovery Secret Manager Access role" --permissions="$(concat_array_to_string permissions[@] ',')" --project=$project_name --format=json --quiet
    if [ $? -ne 0 ]; then
        echo "Cannot create role"
        exit 1
    fi
    role_id=$(gcloud iam roles describe $role_name --project=$project_name --format=json --verbosity=none | jq -r '.name // ""')
else
    echo "Role ${role_name} exists, updating permissions"
    gcloud iam roles update $role_name --permissions="$(concat_array_to_string permissions[@] ',')" --project=$project_name --format=json --quiet
    if [ $? -ne 0 ]; then
        echo "Cannot update role permissions"
        exit 1
    fi
fi

# SERVICE ACCOUNT
existing_service_account_email=$(gcloud iam service-accounts describe "$service_account_name@$project_name.iam.gserviceaccount.com" --project=$project_name --format=json --verbosity=none | jq -r '.email // ""')
if [ -z "$existing_service_account_email" ]; then
    echo "Service account $service_account_name doesn't exist, creating it"
    gcloud iam service-accounts create $service_account_name --display-name="$service_account_name" --project=$project_name --quiet
    if [ $? -ne 0 ]; then
        echo "Cannot create service account"
        exit 1
    fi
    existing_service_account_email=$(gcloud iam service-accounts describe "$service_account_name@$project_name.iam.gserviceaccount.com" --project=$project_name --format=json --verbosity=none | jq -r '.email // ""')
else
    echo "Service account $service_account_name already exists, skipping creation"
fi

# ROLE BINDING
binding_exists=$(gcloud projects get-iam-policy $project_name --flatten="bindings[].members" --format="json" --filter="bindings.role:$role_name bindings.members:$existing_service_account_email" --verbosity=none --project=$project_name --quiet | jq -r '.[0].etag // ""')
if [ -z "$binding_exists" ]; then
   echo "Binding between $role_id and $service_account_name doesnt exist, creating it"
   gcloud projects add-iam-policy-binding $project_name --member="serviceAccount:$existing_service_account_email" --role="$role_id" --project=$project_name --quiet
   if [ $? -ne 0 ]; then
      echo "Cannot create role binding"
      exit 1
   fi
else
    echo "Binding of $role_id to $service_account_name already exists, skipping"
fi

# Generate key for the service account
echo "Generating key for the service account"
gcloud iam service-accounts keys create key.json \
  --iam-account="$service_account_name@$project_name.iam.gserviceaccount.com" --quiet
if [ $? -eq 0 ]; then
    echo "Operations completed. You can now download your json key to upload in Qovery Secret Manager Access"
else
    echo "Cannot create keys for service account, service account can have 10 keys maximum, you have to delete unused keys for this account to recreate one."
    exit 1
fi
