#!/bin/bash

# Directory containing the JSON files
SOURCE_DIRECTORY="./exports"
# Directory to save the output CSV file
OUTPUT_DIRECTORY="./output"
# Output CSV file for detailed data
OUTPUT_FILE="$OUTPUT_DIRECTORY/deployments_and_configs.csv"
# Output CSV file for image occurrences
IMAGE_OCCURRENCES_FILE="$OUTPUT_DIRECTORY/image_occurences.csv"
# Debug log file
DEBUG_LOG_FILE="$OUTPUT_DIRECTORY/debug_log.txt"
# Temporary file to store image counts
TEMP_IMAGE_COUNTS_FILE="$OUTPUT_DIRECTORY/temp_image_counts.txt"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIRECTORY"

# Check if the source directory exists
if [ ! -d "$SOURCE_DIRECTORY" ]; then
  echo "Source directory $SOURCE_DIRECTORY does not exist."
  exit 1
fi

# Initialize the CSV file with headers
echo "ResourceType,Namespace,Environment,Name,Replicas,ContainerName,Image,ImageName,Tag,DeploymentTool" > "$OUTPUT_FILE"
# Initialize the debug log file
echo "Debug Log" > "$DEBUG_LOG_FILE"
# Initialize the temporary image counts file
echo "" > "$TEMP_IMAGE_COUNTS_FILE"

# Function to extract namespace and environment
extract_namespace_parts() {
  local namespace=$1
  local namespace_prefix="${namespace%-*}"
  local environment="${namespace##*-}"
  echo "$namespace_prefix,$environment"
}

# Function to extract image parts
extract_image_parts() {
  local image=$1
  local tag=""
  if [[ "$image" == *@* ]]; then
    local image_full="${image%@*}"
    tag="${image##*@}"
  elif [[ "$image" == *:* ]]; then
    local image_full="${image%:*}"
    tag="${image##*:}"
  else
    local image_full="$image"
  fi

  if [[ "$image_full" == */* ]]; then
    local image_path="${image_full%/*}"
    local image_name="${image_full##*/}"
  else
    local image_path=""
    local image_name="$image_full"
  fi

  echo "$image_full,$image_name,$tag"
}

# Function to extract deployment tool
extract_deployment_tool() {
  local annotations=$1
  local labels=$2
  local deployment_tool=""

  if [[ "$annotations" == *"openshift.io"* ]]; then
    deployment_tool="openshift"
  elif echo "$annotations" | jq -e 'has("provisioned-by") and .["provisioned-by"] == "argocd"' > /dev/null; then
    deployment_tool="argocd"
  elif echo "$labels" | jq -e 'has("app.kubernetes.io/managed-by") and .["app.kubernetes.io/managed-by"] == "Helm"' > /dev/null; then
    deployment_tool="Helm"
  elif echo "$labels" | jq -e 'has("app.kubernetes.io/managed-by") and .["app.kubernetes.io/managed-by"] == "Kustomize"' > /dev/null; then
    deployment_tool="Kustomize"
  elif echo "$labels" | jq -e 'has("app.kubernetes.io/managed-by") and .["app.kubernetes.io/managed-by"] == "template"' > /dev/null; then
    deployment_tool="template"
  fi

  echo "$deployment_tool"
}

# Function to update image counts
update_image_counts() {
  local image_name=$1
  local tag=$2
  local namespace_prefix=$3
  local environment=$4

  echo "Updating count for image: $image_name with tag: $tag in namespace: $namespace_prefix and environment: $environment" >> "$DEBUG_LOG_FILE"

  # Use grep to check if the image, tag, namespace, and environment exist in the temporary file
  if grep -q "^$image_name,$tag,$namespace_prefix,$environment," "$TEMP_IMAGE_COUNTS_FILE"; then
    # Increment the count for the existing image, tag, namespace, and environment
    awk -F, -v img="$image_name" -v tg="$tag" -v ns="$namespace_prefix" -v env="$environment" 'BEGIN{OFS=","} $1 == img && $2 == tg && $3 == ns && $4 == env {$5 += 1} {print}' "$TEMP_IMAGE_COUNTS_FILE" > "$TEMP_IMAGE_COUNTS_FILE.tmp" && mv "$TEMP_IMAGE_COUNTS_FILE.tmp" "$TEMP_IMAGE_COUNTS_FILE"
  else
    # Add a new entry for the new image, tag, namespace, and environment with count 1
    echo "$image_name,$tag,$namespace_prefix,$environment,1" >> "$TEMP_IMAGE_COUNTS_FILE"
  fi

  echo "Updated image counts:" >> "$DEBUG_LOG_FILE"
  cat "$TEMP_IMAGE_COUNTS_FILE" >> "$DEBUG_LOG_FILE"
}

# Process each JSON file in the directory
for FILE in "$SOURCE_DIRECTORY"/*.json; do
  if [ -f "$FILE" ]; then
    jq -c '.items[]' "$FILE" | while read -r item; do
      kind=$(echo "$item" | jq -r '.kind')
      namespace=$(echo "$item" | jq -r '.metadata.namespace')
      name=$(echo "$item" | jq -r '.metadata.name')
      annotations=$(echo "$item" | jq -r '.metadata.annotations | @json')
      labels=$(echo "$item" | jq -r '.metadata.labels | @json')

      if [[ "$kind" =~ ^(Deployment|DeploymentConfig|StatefulSet|CronJob)$ ]]; then
        if [[ "$kind" != "CronJob" ]]; then
          replicas=$(echo "$item" | jq -r '.spec.replicas // ""')
          containers=$(echo "$item" | jq -c '.spec.template.spec.containers[]')
        else
          replicas=""
          containers=$(echo "$item" | jq -c '.spec.jobTemplate.spec.template.spec.containers[]')
        fi

        deployment_tool=$(extract_deployment_tool "$annotations" "$labels")

        echo "$containers" | while read -r container; do
          container_name=$(echo "$container" | jq -r '.name')
          image=$(echo "$container" | jq -r '.image')

          IFS=',' read -r namespace_prefix environment <<< "$(extract_namespace_parts "$namespace")"
          IFS=',' read -r full_image image_name tag <<< "$(extract_image_parts "$image")"

          # Update the image count
          update_image_counts "$image_name" "$tag" "$namespace_prefix" "$environment"

          echo "$kind,$namespace_prefix,$environment,$name,$replicas,$container_name,$full_image,$image_name,$tag,$deployment_tool" >> "$OUTPUT_FILE"
        done
      fi
    done
  else
    echo "No JSON files found in $SOURCE_DIRECTORY." >> "$DEBUG_LOG_FILE"
  fi
done

# Write the image occurrences to the CSV file
echo "Image,Tag,Namespace,Environment,Count" > "$IMAGE_OCCURRENCES_FILE"
# Sort the image counts by count (numeric) and write to the file
sort -t, -k5,5n "$TEMP_IMAGE_COUNTS_FILE" >> "$IMAGE_OCCURRENCES_FILE"

# Clean up temporary file
rm "$TEMP_IMAGE_COUNTS_FILE"

echo "All data has been extracted and saved to $OUTPUT_FILE"
echo "Image occurrences have been saved to $IMAGE_OCCURRENCES_FILE"

