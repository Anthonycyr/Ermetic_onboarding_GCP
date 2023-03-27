###############################################################
# Local Variable
###############################################################
locals {
  org_id = "153899115474"
  project_id = "ermeticproject-379819"
  member = "ermetic-sa@ermeticproject-379819.iam.gserviceaccount.com"
  region = "us-east1"
  
  roles_list = ["roles/appengine.appViewer",
  "roles/artifactregistry.reader",
  "roles/bigquery.metadataViewer",
  "roles/cloudasset.viewer",
  "roles/compute.networkViewer",
  "roles/compute.viewer",
  "roles/container.viewer",
  "roles/orgpolicy.policyViewer",
  "roles/iam.securityReviewer",
  "roles/resourcemanager.organizationViewer"
  ]

  inclusion_list = [
    "activity",
    "data_access",
    "policy"
    ]
  
  exclusion_list = [
  "-:*",
  "=~\"^system:\"",
  "=~\"@container-engine-robot.iam.gserviceaccount.com$\"",
  "=~\"@security-center-api.iam.gserviceaccount.com$\""
  ]

}

provider "google" {
  project     = local.project_id
  region      = local.region
}

###############################################################
# Add read only access to the GCP principal(member) for Ermetic
###############################################################
resource "google_organization_iam_member" "adding-role-sa" {
  for_each = toset(local.roles_list)

  org_id  = local.org_id
  role    = each.value
  member  = "service_account:${local.member}"
}

###############################################################
# Create a Topic
###############################################################
resource "google_pubsub_topic" "ermetic-topic" {
  name = "ermetic-topic"

  message_retention_duration = "259200s"
}

###############################################################
# Create a Sink with filter IN
###############################################################
resource "google_logging_organization_sink" "ermetic-audit-log" {
  name   = "ermetic-audit-log"
  description = "Sink created for the Ermetic Solution"
  org_id = local.org_id

  # Can export to pubsub, cloud storage, or bigquery
  destination = "pubsub.googleapis.com/projects/${local.project_id}/topics/${google_pubsub_topic.ermetic-topic.name}"
  for_each = toset(local.inclusion_list)
  filter = "LOG_ID(cloudaudit.googleapis.com/${each.value}) OR"
}

###############################################################
# Add sink exclusion 
###############################################################
resource "google_logging_organization_exclusion" "sink-exclusion" {
  
  name = "exclude-k8s-logs"
  org_id = local.org_id

  description = "Exclude kubernetes logs"
  
  for_each = toset(local.exclusion_list)
  # Exclude all DEBUG or lower severity messages relating to instances
  filter = "protoPayload.authenticationInfo.principalEmail${each.value} OR"
}

###############################################################
# Create a Subscription
###############################################################
resource "google_pubsub_subscription" "ermtetic-topic-sub" {
  name  = "ermetic-topic-sub"
  topic = google_pubsub_topic.ermetic-topic.name

  #3 days
  message_retention_duration = "259200s"

  ack_deadline_seconds = 10
  
  #never expired
  expiration_policy {
    ttl = ""
  }
  retry_policy {
    minimum_backoff = "10s"
  }

  enable_message_ordering    = false
}

###############################################################
# Add subscription role to the principal(member)
###############################################################
resource "google_pubsub_subscription_iam_member" "pubsub-subsciption-role" {
  subscription = google_pubsub_subscription.ermtetic-topic-sub.name
  role         = "roles/pubsub.subscriber"
  member       = "service_account:${local.member}"
}

output "subscription-id" {
  value = "projects/${local.project_id}/subscriptions/${google_pubsub_subscription.ermtetic-topic-sub.name}"
}
