#!/bin/bash -eu

# (C) Copyright 2020 Nuxeo SA (http://nuxeo.com/) and contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Contributors:
#   Antoine Taillefer
#   Julien Carsique

# Patch the team pod templates' XML config maps to define tolerations and allow the pods being
# scheduled on a dedicated node pool, see https://jira.nuxeo.com/browse/NXBT-3277.
# Unfortunately, tolerations cannot be defined through values.yaml because the Kubernetes plugin for
# Jenkins doesn't take them into account when reading a pod template.
# The solution is to use a `yaml` field in the pod template, yet it isn't taken into account by the jenkins-x-platform chart.
# Thus this patch.
for configmap in $(kubectl -n "${NAMESPACE}" get configmap -l jenkins.io/kind=podTemplateXml -o name); do
    echo "Reading $configmap ..."
    name=${configmap#*pod-xml-}
    configXML=$(kubectl -n "${NAMESPACE}" get $configmap -o jsonpath='{.data.config\.xml}')
    if ! (echo "$configXML" | grep -q '<nodeSelector>team=ui</nodeSelector>'); then
        continue
    fi
    yamlPatch="$(cat templates/jenkins-pod-xml-toleration-patch.xml)"
    export CONFIG_XML_PATCHED=$(echo "$configXML" | awk -v yaml="$yamlPatch" "/<name>$name<\/name>/ { print; print yaml; next }1" | awk '{print "    "$0}')
    envsubst '$$CONFIG_XML_PATCHED' <templates/jenkins-pod-xml-toleration-patch.yaml >templates/jenkins-pod-xml-toleration-patch.yaml~gen
    kubectl -n "${NAMESPACE}" patch "$configmap" --patch "$(cat templates/jenkins-pod-xml-toleration-patch.yaml~gen)"
    echo
done
