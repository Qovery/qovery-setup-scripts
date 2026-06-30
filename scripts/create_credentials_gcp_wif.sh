#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 <project_id> <service_account_name> [organization_id]

Arguments:
  project_id:              GCP project where Qovery will manage GKE resources.
  service_account_name:    GCP service account name to create/use.
  organization_id:         Optional override. By default, the script resolves the GCP
                           organization ID from the project_id and uses it to allow
                           this service account to receive 4h access tokens.

Optional environment variables:
  QOVERY_GCP_ROLE_ID:                Existing custom role ID to bind to the Qovery
                                     service account. Default: qovery_role
  QOVERY_GCP_WIF_POOL_ID:            Workload Identity Pool ID to create/use.
                                     Default: qovery-wif-pool
  QOVERY_GCP_WIF_PROVIDER_ID:        Workload Identity Provider ID to create/use.
                                     Default: qovery-aws

Output:
  Values to store in Qovery:
    service_account_email
    workload_identity_provider_resource

Notes:
  This script does not create a service account key.
  It configures WIF + service account impersonation for the AWS-like STS flow.
EOF
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 1
fi

QOVERY_AWS_ACCOUNT_ID="283389881690"
QOVERY_AWS_PRINCIPAL_NAME="qovery-deployer-federation"

PROJECT_ID="$1"
SERVICE_ACCOUNT_NAME="$2"
ORGANIZATION_ID="${3:-}"

ROLE_ID="${QOVERY_GCP_ROLE_ID:-qovery_role}"
POOL_ID="${QOVERY_GCP_WIF_POOL_ID:-qovery-wif-pool}"
PROVIDER_ID="${QOVERY_GCP_WIF_PROVIDER_ID:-qovery-aws}"

LOCATION="global"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

concat_array_to_string() {
    array_ref=("${!1}")
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
    # IAM
    "iam.serviceAccounts.create"
    "iam.serviceAccounts.delete"
    "iam.serviceAccounts.disable"
    "iam.serviceAccounts.enable"
    "iam.serviceAccounts.get"
    "iam.serviceAccounts.getIamPolicy"
    "iam.serviceAccounts.list"
    "iam.serviceAccounts.setIamPolicy"
    "iam.serviceAccounts.undelete"
    "iam.serviceAccounts.update"
    "iam.serviceAccounts.actAs"
    # Resource manager
    "resourcemanager.projects.get"
    "resourcemanager.projects.setIamPolicy"
    "resourcemanager.projects.getIamPolicy"
    # Kubernetes Engine
    "container.apiServices.create"
    "container.apiServices.delete"
    "container.apiServices.get"
    "container.apiServices.getStatus"
    "container.apiServices.list"
    "container.apiServices.update"
    "container.apiServices.updateStatus"
    "container.auditSinks.create"
    "container.auditSinks.delete"
    "container.auditSinks.get"
    "container.auditSinks.list"
    "container.auditSinks.update"
    "container.backendConfigs.create"
    "container.backendConfigs.delete"
    "container.backendConfigs.get"
    "container.backendConfigs.list"
    "container.backendConfigs.update"
    "container.bindings.create"
    "container.certificateSigningRequests.approve"
    "container.certificateSigningRequests.create"
    "container.certificateSigningRequests.delete"
    "container.certificateSigningRequests.get"
    "container.certificateSigningRequests.getStatus"
    "container.certificateSigningRequests.list"
    "container.certificateSigningRequests.update"
    "container.certificateSigningRequests.updateStatus"
    "container.clusterRoleBindings.create"
    "container.clusterRoleBindings.delete"
    "container.clusterRoleBindings.get"
    "container.clusterRoleBindings.list"
    "container.clusterRoleBindings.update"
    "container.clusterRoles.bind"
    "container.clusterRoles.create"
    "container.clusterRoles.delete"
    "container.clusterRoles.escalate"
    "container.clusterRoles.get"
    "container.clusterRoles.list"
    "container.clusterRoles.update"
    "container.clusters.connect"
    "container.clusters.create"
    "container.clusters.createTagBinding"
    "container.clusters.delete"
    "container.clusters.deleteTagBinding"
    "container.clusters.get"
    "container.clusters.getCredentials"
    "container.clusters.list"
    "container.clusters.listEffectiveTags"
    "container.clusters.listTagBindings"
    "container.clusters.update"
    "container.componentStatuses.get"
    "container.componentStatuses.list"
    "container.configMaps.create"
    "container.configMaps.delete"
    "container.configMaps.get"
    "container.configMaps.list"
    "container.configMaps.update"
    "container.controllerRevisions.create"
    "container.controllerRevisions.delete"
    "container.controllerRevisions.get"
    "container.controllerRevisions.list"
    "container.controllerRevisions.update"
    "container.cronJobs.create"
    "container.cronJobs.delete"
    "container.cronJobs.get"
    "container.cronJobs.getStatus"
    "container.cronJobs.list"
    "container.cronJobs.update"
    "container.cronJobs.updateStatus"
    "container.csiDrivers.create"
    "container.csiDrivers.delete"
    "container.csiDrivers.get"
    "container.csiDrivers.list"
    "container.csiDrivers.update"
    "container.csiNodeInfos.create"
    "container.csiNodeInfos.delete"
    "container.csiNodeInfos.get"
    "container.csiNodeInfos.list"
    "container.csiNodeInfos.update"
    "container.csiNodes.create"
    "container.csiNodes.delete"
    "container.csiNodes.get"
    "container.csiNodes.list"
    "container.csiNodes.update"
    "container.customResourceDefinitions.create"
    "container.customResourceDefinitions.delete"
    "container.customResourceDefinitions.get"
    "container.customResourceDefinitions.getStatus"
    "container.customResourceDefinitions.list"
    "container.customResourceDefinitions.update"
    "container.customResourceDefinitions.updateStatus"
    "container.daemonSets.create"
    "container.daemonSets.delete"
    "container.daemonSets.get"
    "container.daemonSets.getStatus"
    "container.daemonSets.list"
    "container.daemonSets.update"
    "container.daemonSets.updateStatus"
    "container.deployments.create"
    "container.deployments.delete"
    "container.deployments.get"
    "container.deployments.getScale"
    "container.deployments.getStatus"
    "container.deployments.list"
    "container.deployments.rollback"
    "container.deployments.update"
    "container.deployments.updateScale"
    "container.deployments.updateStatus"
    "container.endpointSlices.create"
    "container.endpointSlices.delete"
    "container.endpointSlices.get"
    "container.endpointSlices.list"
    "container.endpointSlices.update"
    "container.endpoints.create"
    "container.endpoints.delete"
    "container.endpoints.get"
    "container.endpoints.list"
    "container.endpoints.update"
    "container.events.create"
    "container.events.delete"
    "container.events.get"
    "container.events.list"
    "container.events.update"
    "container.frontendConfigs.create"
    "container.frontendConfigs.delete"
    "container.frontendConfigs.get"
    "container.frontendConfigs.list"
    "container.frontendConfigs.update"
    "container.horizontalPodAutoscalers.create"
    "container.horizontalPodAutoscalers.delete"
    "container.horizontalPodAutoscalers.get"
    "container.horizontalPodAutoscalers.getStatus"
    "container.horizontalPodAutoscalers.list"
    "container.horizontalPodAutoscalers.update"
    "container.horizontalPodAutoscalers.updateStatus"
    "container.hostServiceAgent.use"
    "container.ingresses.create"
    "container.ingresses.delete"
    "container.ingresses.get"
    "container.ingresses.getStatus"
    "container.ingresses.list"
    "container.ingresses.update"
    "container.ingresses.updateStatus"
    "container.jobs.create"
    "container.jobs.delete"
    "container.jobs.get"
    "container.jobs.getStatus"
    "container.jobs.list"
    "container.jobs.update"
    "container.jobs.updateStatus"
    "container.leases.create"
    "container.leases.delete"
    "container.leases.get"
    "container.leases.list"
    "container.leases.update"
    "container.limitRanges.create"
    "container.limitRanges.delete"
    "container.limitRanges.get"
    "container.limitRanges.list"
    "container.limitRanges.update"
    "container.localSubjectAccessReviews.create"
    "container.managedCertificates.create"
    "container.managedCertificates.delete"
    "container.managedCertificates.get"
    "container.managedCertificates.list"
    "container.managedCertificates.update"
    "container.mutatingWebhookConfigurations.create"
    "container.mutatingWebhookConfigurations.delete"
    "container.mutatingWebhookConfigurations.get"
    "container.mutatingWebhookConfigurations.list"
    "container.mutatingWebhookConfigurations.update"
    "container.namespaces.create"
    "container.namespaces.delete"
    "container.namespaces.get"
    "container.namespaces.getStatus"
    "container.namespaces.list"
    "container.namespaces.update"
    "container.namespaces.updateStatus"
    "container.networkPolicies.create"
    "container.networkPolicies.delete"
    "container.networkPolicies.get"
    "container.networkPolicies.list"
    "container.networkPolicies.update"
    "container.nodes.create"
    "container.nodes.delete"
    "container.nodes.get"
    "container.nodes.getStatus"
    "container.nodes.list"
    "container.nodes.proxy"
    "container.nodes.update"
    "container.nodes.updateStatus"
    "container.operations.get"
    "container.operations.list"
    "container.persistentVolumeClaims.create"
    "container.persistentVolumeClaims.delete"
    "container.persistentVolumeClaims.get"
    "container.persistentVolumeClaims.getStatus"
    "container.persistentVolumeClaims.list"
    "container.persistentVolumeClaims.update"
    "container.persistentVolumeClaims.updateStatus"
    "container.persistentVolumes.create"
    "container.persistentVolumes.delete"
    "container.persistentVolumes.get"
    "container.persistentVolumes.getStatus"
    "container.persistentVolumes.list"
    "container.persistentVolumes.update"
    "container.persistentVolumes.updateStatus"
    "container.podDisruptionBudgets.create"
    "container.podDisruptionBudgets.delete"
    "container.podDisruptionBudgets.get"
    "container.podDisruptionBudgets.getStatus"
    "container.podDisruptionBudgets.list"
    "container.podDisruptionBudgets.update"
    "container.podDisruptionBudgets.updateStatus"
    "container.podSecurityPolicies.create"
    "container.podSecurityPolicies.delete"
    "container.podSecurityPolicies.get"
    "container.podSecurityPolicies.list"
    "container.podSecurityPolicies.update"
    "container.podTemplates.create"
    "container.podTemplates.delete"
    "container.podTemplates.get"
    "container.podTemplates.list"
    "container.podTemplates.update"
    "container.pods.attach"
    "container.pods.create"
    "container.pods.delete"
    "container.pods.evict"
    "container.pods.exec"
    "container.pods.get"
    "container.pods.getLogs"
    "container.pods.getStatus"
    "container.pods.list"
    "container.pods.portForward"
    "container.pods.proxy"
    "container.pods.update"
    "container.pods.updateStatus"
    "container.priorityClasses.create"
    "container.priorityClasses.delete"
    "container.priorityClasses.get"
    "container.priorityClasses.list"
    "container.priorityClasses.update"
    "container.replicaSets.create"
    "container.replicaSets.delete"
    "container.replicaSets.get"
    "container.replicaSets.getScale"
    "container.replicaSets.getStatus"
    "container.replicaSets.list"
    "container.replicaSets.update"
    "container.replicaSets.updateScale"
    "container.replicaSets.updateStatus"
    "container.replicationControllers.create"
    "container.replicationControllers.delete"
    "container.replicationControllers.get"
    "container.replicationControllers.getScale"
    "container.replicationControllers.getStatus"
    "container.replicationControllers.list"
    "container.replicationControllers.update"
    "container.replicationControllers.updateScale"
    "container.replicationControllers.updateStatus"
    "container.resourceQuotas.create"
    "container.resourceQuotas.delete"
    "container.resourceQuotas.get"
    "container.resourceQuotas.getStatus"
    "container.resourceQuotas.list"
    "container.resourceQuotas.update"
    "container.resourceQuotas.updateStatus"
    "container.roleBindings.create"
    "container.roleBindings.delete"
    "container.roles.escalate"
    "container.roleBindings.get"
    "container.roleBindings.list"
    "container.roleBindings.update"
    "container.roles.bind"
    "container.roles.create"
    "container.roles.delete"
    "container.roles.get"
    "container.roles.list"
    "container.roles.update"
    "container.runtimeClasses.create"
    "container.runtimeClasses.delete"
    "container.runtimeClasses.get"
    "container.runtimeClasses.list"
    "container.runtimeClasses.update"
    "container.secrets.create"
    "container.secrets.delete"
    "container.secrets.get"
    "container.secrets.list"
    "container.secrets.update"
    "container.selfSubjectAccessReviews.create"
    "container.selfSubjectRulesReviews.create"
    "container.serviceAccounts.create"
    "container.serviceAccounts.createToken"
    "container.serviceAccounts.delete"
    "container.serviceAccounts.get"
    "container.serviceAccounts.list"
    "container.serviceAccounts.update"
    "container.services.create"
    "container.services.delete"
    "container.services.get"
    "container.services.getStatus"
    "container.services.list"
    "container.services.proxy"
    "container.services.update"
    "container.services.updateStatus"
    "container.statefulSets.create"
    "container.statefulSets.delete"
    "container.statefulSets.get"
    "container.statefulSets.getScale"
    "container.statefulSets.getStatus"
    "container.statefulSets.list"
    "container.statefulSets.update"
    "container.statefulSets.updateScale"
    "container.statefulSets.updateStatus"
    "container.storageClasses.create"
    "container.storageClasses.delete"
    "container.storageClasses.get"
    "container.storageClasses.list"
    "container.storageClasses.update"
    "container.storageStates.create"
    "container.storageStates.delete"
    "container.storageStates.get"
    "container.storageStates.getStatus"
    "container.storageStates.list"
    "container.storageStates.update"
    "container.storageStates.updateStatus"
    "container.storageVersionMigrations.create"
    "container.storageVersionMigrations.delete"
    "container.storageVersionMigrations.get"
    "container.storageVersionMigrations.getStatus"
    "container.storageVersionMigrations.list"
    "container.storageVersionMigrations.update"
    "container.storageVersionMigrations.updateStatus"
    "container.subjectAccessReviews.create"
    "container.thirdPartyObjects.create"
    "container.thirdPartyObjects.delete"
    "container.thirdPartyObjects.get"
    "container.thirdPartyObjects.list"
    "container.thirdPartyObjects.update"
    "container.tokenReviews.create"
    "container.updateInfos.create"
    "container.updateInfos.delete"
    "container.updateInfos.get"
    "container.updateInfos.list"
    "container.updateInfos.update"
    "container.validatingWebhookConfigurations.create"
    "container.validatingWebhookConfigurations.delete"
    "container.validatingWebhookConfigurations.get"
    "container.validatingWebhookConfigurations.list"
    "container.validatingWebhookConfigurations.update"
    "container.volumeAttachments.create"
    "container.volumeAttachments.delete"
    "container.volumeAttachments.get"
    "container.volumeAttachments.getStatus"
    "container.volumeAttachments.list"
    "container.volumeAttachments.update"
    "container.volumeAttachments.updateStatus"
    "container.volumeSnapshotClasses.create"
    "container.volumeSnapshotClasses.delete"
    "container.volumeSnapshotClasses.get"
    "container.volumeSnapshotClasses.list"
    "container.volumeSnapshotClasses.update"
    "container.volumeSnapshotContents.create"
    "container.volumeSnapshotContents.delete"
    "container.volumeSnapshotContents.get"
    "container.volumeSnapshotContents.getStatus"
    "container.volumeSnapshotContents.list"
    "container.volumeSnapshotContents.update"
    "container.volumeSnapshotContents.updateStatus"
    "container.volumeSnapshots.create"
    "container.volumeSnapshots.delete"
    "container.volumeSnapshots.get"
    "container.volumeSnapshots.getStatus"
    "container.volumeSnapshots.list"
    "container.volumeSnapshots.update"
    "container.volumeSnapshots.updateStatus"
    # Artifact registry
    "artifactregistry.dockerimages.get"
    "artifactregistry.dockerimages.list"
    "artifactregistry.locations.get"
    "artifactregistry.locations.list"
    "artifactregistry.repositories.create"
    "artifactregistry.repositories.createTagBinding"
    "artifactregistry.repositories.delete"
    "artifactregistry.repositories.deleteArtifacts"
    "artifactregistry.repositories.deleteTagBinding"
    "artifactregistry.repositories.downloadArtifacts"
    "artifactregistry.repositories.get"
    "artifactregistry.repositories.getIamPolicy"
    "artifactregistry.repositories.list"
    "artifactregistry.repositories.listEffectiveTags"
    "artifactregistry.repositories.listTagBindings"
    "artifactregistry.repositories.readViaVirtualRepository"
    "artifactregistry.repositories.setIamPolicy"
    "artifactregistry.repositories.update"
    "artifactregistry.repositories.uploadArtifacts"
    "artifactregistry.tags.create"
    "artifactregistry.tags.delete"
    "artifactregistry.tags.get"
    "artifactregistry.tags.list"
    "artifactregistry.tags.update"
    "artifactregistry.versions.delete"
    "artifactregistry.versions.get"
    "artifactregistry.versions.list"
    # Network compute
    "compute.networks.access"
    "compute.networks.create"
    "compute.networks.createTagBinding"
    "compute.networks.delete"
    "compute.networks.deleteTagBinding"
    "compute.firewalls.delete"
    "compute.firewalls.list"
    "compute.networks.get"
    "compute.networks.getEffectiveFirewalls"
    "compute.networks.getRegionEffectiveFirewalls"
    "compute.networks.list"
    "compute.networks.listEffectiveTags"
    "compute.networks.listPeeringRoutes"
    "compute.networks.listTagBindings"
    "compute.networks.mirror"
    "compute.networks.setFirewallPolicy"
    "compute.networks.updatePeering"
    "compute.networks.updatePolicy"
    "compute.networks.use"
    "compute.networks.useExternalIp"
    "compute.subnetworks.create"
    "compute.subnetworks.createTagBinding"
    "compute.subnetworks.delete"
    "compute.subnetworks.deleteTagBinding"
    "compute.subnetworks.expandIpCidrRange"
    "compute.subnetworks.get"
    "compute.subnetworks.getIamPolicy"
    "compute.subnetworks.list"
    "compute.subnetworks.listEffectiveTags"
    "compute.subnetworks.listTagBindings"
    "compute.subnetworks.mirror"
    "compute.subnetworks.setIamPolicy"
    "compute.subnetworks.setPrivateIpGoogleAccess"
    "compute.subnetworks.update"
    "compute.subnetworks.use"
    "compute.subnetworks.useExternalIp"
    "compute.instanceGroupManagers.get"
    "compute.instanceGroupManagers.list"
    "compute.instanceGroupManagers.listEffectiveTags"
    "compute.instanceGroupManagers.listTagBindings"
    "compute.instanceGroupManagers.update"
    "compute.instanceGroupManagers.use"
    "compute.instanceGroups.get"
    "compute.instanceGroups.list"
    "compute.instanceGroups.update"
    "compute.instanceGroups.use"
    "compute.regions.get"
    "compute.regions.list"
    "compute.addresses.create"
    "compute.addresses.delete"
    "compute.addresses.get"
    "compute.addresses.list"
    "compute.routers.create"
    "compute.routers.delete"
    "compute.routers.deleteRoutePolicy"
    "compute.routers.get"
    "compute.routers.getRoutePolicy"
    "compute.routers.list"
    "compute.routers.listBgpRoutes"
    "compute.routers.listRoutePolicies"
    "compute.routers.update"
    "compute.routers.updateRoutePolicy"
    "compute.routers.use"
    "compute.routes.create"
    "compute.routes.createTagBinding"
    "compute.routes.delete"
    "compute.routes.deleteTagBinding"
    "compute.routes.get"
    "compute.routes.list"
    "compute.routes.listEffectiveTags"
    "compute.routes.listTagBindings"
    # Storage
    "storage.bucketOperations.cancel"
    "storage.bucketOperations.get"
    "storage.bucketOperations.list"
    "storage.buckets.create"
    "storage.buckets.createTagBinding"
    "storage.buckets.delete"
    "storage.buckets.deleteTagBinding"
    "storage.buckets.enableObjectRetention"
    "storage.buckets.get"
    "storage.buckets.getIamPolicy"
    "storage.buckets.getObjectInsights"
    "storage.buckets.list"
    "storage.buckets.listEffectiveTags"
    "storage.buckets.listTagBindings"
    "storage.buckets.restore"
    "storage.buckets.setIamPolicy"
    "storage.buckets.update"
    "storage.managedFolders.create"
    "storage.managedFolders.delete"
    "storage.managedFolders.get"
    "storage.managedFolders.getIamPolicy"
    "storage.managedFolders.list"
    "storage.managedFolders.setIamPolicy"
    "storage.multipartUploads.abort"
    "storage.multipartUploads.create"
    "storage.multipartUploads.list"
    "storage.multipartUploads.listParts"
    "storage.objects.create"
    "storage.objects.delete"
    "storage.objects.get"
    "storage.objects.getIamPolicy"
    "storage.objects.list"
    "storage.objects.overrideUnlockedRetention"
    "storage.objects.restore"
    "storage.objects.setIamPolicy"
    "storage.objects.setRetention"
    "storage.objects.update"
    # Cloud Run
    "run.configurations.get"
    "run.configurations.list"
    "run.executions.cancel"
    "run.executions.delete"
    "run.executions.list"
    "run.executions.get"
    "run.jobs.create"
    "run.jobs.delete"
    "run.jobs.get"
    "run.jobs.getIamPolicy"
    "run.jobs.list"
    "run.jobs.listEffectiveTags"
    "run.jobs.listTagBindings"
    "run.jobs.run"
    "run.jobs.runWithOverrides"
    "run.jobs.update"
    "run.locations.list"
    "run.operations.delete"
    "run.operations.get"
    "run.operations.list"
    "run.revisions.delete"
    "run.revisions.get"
    "run.revisions.list"
    "run.routes.list"
    "run.routes.invoke"
    "run.routes.get"
    "run.services.create"
    "run.services.delete"
    "run.services.get"
    "run.services.getIamPolicy"
    "run.services.list"
    "run.services.listEffectiveTags"
    "run.services.listTagBindings"
    "run.services.update"
    # When using kms key
    "cloudkms.cryptoKeys.getIamPolicy"
)

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  if ! command_exists "$1"; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command gcloud

retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt=1
  until "$@"; do
    if [ "${attempt}" -ge "${attempts}" ]; then
      return 1
    fi

    echo "Command failed, retrying in ${delay_seconds}s (${attempt}/${attempts})"
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
  done
}

echo "Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Enabling required APIs"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  run.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
if [ -z "${PROJECT_NUMBER}" ]; then
  echo "Cannot resolve project number for project ${PROJECT_ID}"
  exit 1
fi

echo "Project number: ${PROJECT_NUMBER}"

if [ -z "${ORGANIZATION_ID}" ]; then
  PROJECT_PARENT_TYPE="$(gcloud projects describe "${PROJECT_ID}" --format="value(parent.type)")"
  PROJECT_PARENT_ID="$(gcloud projects describe "${PROJECT_ID}" --format="value(parent.id)")"

  if [ "${PROJECT_PARENT_TYPE}" = "organization" ] && [ -n "${PROJECT_PARENT_ID}" ]; then
    ORGANIZATION_ID="${PROJECT_PARENT_ID}"
  fi
fi

if [ -z "${ORGANIZATION_ID}" ]; then
  echo "Cannot resolve GCP organization ID from project ${PROJECT_ID}."
  echo "The project might be under a folder or not attached to an organization."
  echo "Please rerun the script with organization_id as the last argument."
  exit 1
fi

echo "Organization ID: ${ORGANIZATION_ID}"

echo "Checking organization policy access"
ORG_POLICY_DESCRIBE_OUTPUT="$(
  gcloud resource-manager org-policies describe \
    constraints/iam.allowServiceAccountCredentialLifetimeExtension \
    --organization="${ORGANIZATION_ID}" \
    --quiet 2>&1 || true
)"
if echo "${ORG_POLICY_DESCRIBE_OUTPUT}" | grep -qiE "PERMISSION_DENIED|does not have permission"; then
  echo "Cannot access organization policy constraints/iam.allowServiceAccountCredentialLifetimeExtension on organization ${ORGANIZATION_ID}."
  echo "Ask a GCP organization administrator to run this script, or grant your account Organization Policy Administrator (roles/orgpolicy.policyAdmin) on the organization."
  exit 1
fi

echo "Ensuring custom role: ${ROLE_ID}"
ROLE_NAME="$(gcloud iam roles describe "${ROLE_ID}" --project="${PROJECT_ID}" --format="value(name)" --quiet 2>/dev/null || true)"
if [ -z "${ROLE_NAME}" ]; then
  echo "Custom role ${ROLE_ID} does not exist, creating it"
  gcloud iam roles create "${ROLE_ID}" \
    --description="Qovery role" \
    --permissions="$(concat_array_to_string permissions[@] ',')" \
    --project="${PROJECT_ID}" \
    --format=json \
    --quiet >/dev/null
  ROLE_NAME="$(gcloud iam roles describe "${ROLE_ID}" --project="${PROJECT_ID}" --format="value(name)" --quiet)"
else
  echo "Custom role ${ROLE_ID} already exists, updating permissions"
  gcloud iam roles update "${ROLE_ID}" \
    --permissions="$(concat_array_to_string permissions[@] ',')" \
    --project="${PROJECT_ID}" \
    --format=json \
    --quiet >/dev/null
fi

echo "Ensuring service account exists: ${SERVICE_ACCOUNT_EMAIL}"
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" --quiet >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --display-name="${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --quiet
else
  echo "Service account already exists, skipping creation"
fi

echo "Waiting for service account propagation"
retry_command 12 5 \
  gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null

echo "Binding custom role ${ROLE_NAME} to ${SERVICE_ACCOUNT_EMAIL}"
retry_command 12 5 \
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${ROLE_NAME}" \
    --project="${PROJECT_ID}" \
    --quiet >/dev/null

echo "Ensuring Workload Identity Pool exists: ${POOL_ID}"
if ! gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --quiet >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --display-name="Qovery WIF Pool" \
    --description="Allows the Qovery AWS identity to impersonate the Qovery GCP service account" \
    --quiet
else
  echo "Workload Identity Pool already exists, skipping creation"
fi

ATTRIBUTE_MAPPING="google.subject=assertion.arn,attribute.account=assertion.account,attribute.aws_user=assertion.arn.extract('user/{user_name}'),attribute.aws_role=assertion.arn.extract('assumed-role/{role_name}/')"
ATTRIBUTE_CONDITION="assertion.account == '${QOVERY_AWS_ACCOUNT_ID}' && (assertion.arn.extract('user/{user_name}') == '${QOVERY_AWS_PRINCIPAL_NAME}' || assertion.arn.extract('assumed-role/{role_name}/') == '${QOVERY_AWS_PRINCIPAL_NAME}')"

echo "Ensuring AWS Workload Identity Provider exists: ${PROVIDER_ID}"
if ! gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --workload-identity-pool="${POOL_ID}" \
  --quiet >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-aws "${PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --workload-identity-pool="${POOL_ID}" \
    --display-name="Qovery AWS identity" \
    --description="Trusts the Qovery AWS identity" \
    --account-id="${QOVERY_AWS_ACCOUNT_ID}" \
    --attribute-mapping="${ATTRIBUTE_MAPPING}" \
    --attribute-condition="${ATTRIBUTE_CONDITION}" \
    --quiet
else
  echo "Workload Identity Provider already exists, updating mapping and condition"
  gcloud iam workload-identity-pools providers update-aws "${PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --workload-identity-pool="${POOL_ID}" \
    --account-id="${QOVERY_AWS_ACCOUNT_ID}" \
    --attribute-mapping="${ATTRIBUTE_MAPPING}" \
    --attribute-condition="${ATTRIBUTE_CONDITION}" \
    --quiet
fi

WIF_USER_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/attribute.aws_user/${QOVERY_AWS_PRINCIPAL_NAME}"
WIF_ROLE_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/attribute.aws_role/${QOVERY_AWS_PRINCIPAL_NAME}"
WORKLOAD_IDENTITY_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo "Allowing Qovery AWS identity to impersonate ${SERVICE_ACCOUNT_EMAIL}"
retry_command 12 5 \
  gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${WIF_USER_MEMBER}" \
    --quiet >/dev/null

retry_command 12 5 \
  gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${WIF_ROLE_MEMBER}" \
    --quiet >/dev/null

echo "Allowing 4h access tokens for ${SERVICE_ACCOUNT_EMAIL} at organization ${ORGANIZATION_ID}"
retry_command 12 5 \
  gcloud resource-manager org-policies allow \
    constraints/iam.allowServiceAccountCredentialLifetimeExtension \
    "${SERVICE_ACCOUNT_EMAIL}" \
    --organization="${ORGANIZATION_ID}" \
    --quiet

cat <<EOF

Operations completed.

Store these values in Qovery:

service_account_email=${SERVICE_ACCOUNT_EMAIL}
workload_identity_provider_resource=${WORKLOAD_IDENTITY_PROVIDER_RESOURCE}
aws_account_id=${QOVERY_AWS_ACCOUNT_ID}
aws_principal_name=${QOVERY_AWS_PRINCIPAL_NAME}

No JSON service account key was created.
EOF
