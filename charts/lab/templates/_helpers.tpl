{{- define "lab.labels" -}}
app.kubernetes.io/part-of: lab-commit
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "lab.selector" -}}
app.kubernetes.io/name: {{ . }}
{{- end -}}

{{- define "lab.tag" -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{- define "lab.image" -}}
{{- $root := index . 0 -}}
{{- $repository := index . 1 -}}
{{- if $root.Values.image.registry -}}
{{- printf "%s/%s:%s" $root.Values.image.registry $repository (include "lab.tag" $root) -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "lab.tag" $root) -}}
{{- end -}}
{{- end -}}

{{- define "lab.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "lab.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end -}}

{{- define "lab.albAnnotations" -}}
{{- $root := index . 0 -}}
{{- $scheme := index . 1 -}}
{{- $group := index . 2 -}}
{{- $securityGroupId := index . 3 -}}
alb.ingress.kubernetes.io/scheme: {{ $scheme }}
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/group.name: {{ $group }}
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
alb.ingress.kubernetes.io/ssl-redirect: "443"
alb.ingress.kubernetes.io/ssl-policy: {{ $root.Values.ingress.sslPolicy }}
alb.ingress.kubernetes.io/certificate-arn: {{ required "ingress.certificateArn is required" $root.Values.ingress.certificateArn }}
{{- with $securityGroupId }}
alb.ingress.kubernetes.io/security-groups: {{ . }}
alb.ingress.kubernetes.io/manage-backend-security-group-rules: "false"
{{- end }}
{{- end -}}
