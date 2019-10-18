#!/bin/sh
set -e

dockerRegistryPod=$(kubectl get pod -o custom-columns=NAME:.metadata.name | grep docker-registry)
#dockerRegistry="http://docker-registry.webui.34.74.59.50.nip.io"
dockerRegistry="http://$(kubectl get svc -o custom-columns=NAME:.metadata.name,CLUSTER-IP:.spec.clusterIP | grep docker-registry | awk '{print $2}'):5000"

function execDockerRegistry () {
  kubectl exec $dockerRegistryPod -- $1
}

function space () {
  execDockerRegistry "df -h" | grep 'Filesystem\|/var/lib/registry'
}

function used () {
  execDockerRegistry "df" | grep '/var/lib/registry' | awk '{print$3}'
}

echo '=========================='
echo '- Purge closed PR images -'
echo '=========================='
echo "\n$dockerRegistry\n"
echo 'Space before cleanup:'
space
echo

usedBefore=$(used)

images=$(curl --silent $dockerRegistry/v2/_catalog | jq -r '.repositories | .[]?')
echo 'Images to handle:'
cat << EOF
$images
EOF
echo

for image in $images
do
  echo "# $image"
  # assumes image name matches org/repository/....
  openPR=$(curl --silent "https://api.github.com/search/issues?q=is:open%20is:pr%20repo:$image" | jq -r '.items | .[]?.number | tostring | "PR-" + .')
  echo "Open PR:"
  cat << EOF
$openPR
EOF
  pattern=$(echo "$openPR" | tr ' ' '\|')
  # filter tags with PR- and then exclude open PR
  tags=$(curl --silent $dockerRegistry/v2/$image/tags/list  | jq -r '.tags | .[]?' | grep 'PR-' | grep -v '$pattern' || true)
  if [ -z "$tags" ]; then
    continue
  fi
  echo
  for tag in $tags
  do
    rawDigest=$(curl -v --silent -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' $dockerRegistry/v2/$image/manifests/$tag 2>&1 | grep Docker-Content-Digest | awk '{print $3}')
    digest=${rawDigest%$'\r'}
    echo "Delete digest of image $image:$tag      $digest"
    curl --silent -X DELETE $dockerRegistry/v2/$image/manifests/$digest
  done
  echo
done
echo

echo 'Garbage collection:'
execDockerRegistry "/bin/registry garbage-collect /etc/docker/registry/config.yml"
echo

echo 'Space after cleanup:'
space
echo

usedAfter=$(used)
cleanedUp=$((($usedBefore - $usedAfter) / 1024))

echo "Cleaned up $cleanedUp Mo"
echo
