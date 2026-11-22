# Lesson 31 — AWS Load Balancer Controller Deep Dive

> **Track:** AWS Networking  
> **Prerequisites:** [Lesson 20 — Cloud Load Balancers](20-cloud-load-balancers.md), [Lesson 29 — EKS Networking](29-aws-eks-networking.md)  
> **Duration:** ~2.5 hours

---

## Practice Setup

```bash
# Terminal 1 — Mac (kubectl)
kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null || \
  echo "AWS LBC not installed — see section 2 for installation"
kubectl get ingressclass
kubectl get targetgroupbindings -A 2>/dev/null

# Terminal 2 — Mac (aws CLI)
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[*].[LoadBalancerName,Type,State.Code]' \
  --output table 2>/dev/null || echo "Configure AWS CLI first"
```

---

## 1. AWS LBC vs In-Tree CCM

| Feature | In-tree CCM (legacy) | AWS Load Balancer Controller |
|---------|---------------------|------------------------------|
| NLB type | Classic LB or NLB | NLB (Network Load Balancer) |
| ALB | No | Yes (via Ingress) |
| Target type | Instance only | Instance or IP (pod-level) |
| Annotations | Limited | 50+ annotations |
| Maintenance | Deprecated | Actively developed |

---

## 2. NLB via Service (type: LoadBalancer)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  annotations:
    # Required: use external controller, not CCM
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"

    # Scheme
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    # or: "internal" for private NLB

    # Health check
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/healthz"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "10"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"

    # Cross-zone LB (distributes traffic evenly across AZs)
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"

    # Preserve client IP
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "preserve_client_ip.enabled=true"

    # Static IP via Elastic IP
    service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "eipalloc-xxxxx,eipalloc-yyyyy"

    # TLS
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:123:certificate/xxx"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"

    # Access logging
    service.beta.kubernetes.io/aws-load-balancer-access-log-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-name: "my-nlb-logs"
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 8080
```

### Instance vs IP Target Type

**Instance mode:** NLB → NodePort → kube-proxy → pod
```yaml
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
```

**IP mode:** NLB → pod IP directly (requires VPC CNI)
```yaml
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
# Lower latency — skips NodePort and kube-proxy
# Client IP preserved natively
```

---

## 3. ALB via Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip

    # TLS
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123:certificate/xxx
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"

    # Health check
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/success-codes: "200-399"

    # Stickiness
    alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400

    # WAF
    alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:us-east-1:123:regional/webacl/xxx

    # Access logs
    alb.ingress.kubernetes.io/load-balancer-attributes: "access_logs.s3.enabled=true,access_logs.s3.bucket=my-alb-logs"

spec:
  ingressClassName: alb
  rules:
    - host: web.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
```

---

## 4. IngressGroup — Share One ALB Across Ingresses

```yaml
# Multiple Ingress resources share one ALB (cost saving)
metadata:
  annotations:
    alb.ingress.kubernetes.io/group.name: "production"   # same group = same ALB
    alb.ingress.kubernetes.io/group.order: "10"          # rule priority order
```

```bash
# All Ingresses with group.name=production share one ALB
kubectl get ingress -A | grep production
# web-ingress     web.example.com
# api-ingress     api.example.com
# → both served by the same ALB DNS name
```

---

## 5. TargetGroupBinding — Attach External Target Groups

```yaml
# Register pods directly to an existing Target Group (useful for blue/green)
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: web-tgb
spec:
  serviceRef:
    name: web
    port: 8080
  targetGroupARN: arn:aws:elasticloadbalancing:us-east-1:123:targetgroup/web/xxx
  targetType: ip
```

---

## 6. Weighted Routing for Canary Deployments

```yaml
# Two services, weighted via annotations
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-canary
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/actions.weighted-routing: |
      {"type":"forward","forwardConfig":{"targetGroups":[
        {"serviceName":"web-v1","servicePort":"80","weight":90},
        {"serviceName":"web-v2","servicePort":"80","weight":10}
      ]}}
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: weighted-routing
                port:
                  name: use-annotation
```

---

## 7. IAM Permissions

The LBC needs IAM permissions to manage ALBs and NLBs:

```bash
# Create IAM policy
curl -o iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

# Create IRSA service account
eksctl create iamserviceaccount \
  --cluster my-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::ACCOUNT:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

---

## 8. Troubleshooting

```bash
# 1. Check controller logs
kubectl logs -n kube-system deploy/aws-load-balancer-controller | tail -50

# 2. Is the Ingress being reconciled?
kubectl describe ingress web-ingress | grep -A10 "Events"
# Events:
#   Normal  SuccessfullyReconciled  Reconciled

# 3. What ALB was created?
kubectl get ingress web-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# 4. Are target groups healthy?
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# 5. IAM issues
kubectl logs -n kube-system deploy/aws-load-balancer-controller | grep -i "unauthorized\|AccessDenied"

# 6. Subnet not found
kubectl logs -n kube-system deploy/aws-load-balancer-controller | grep "subnet"
# → Check subnet tags (kubernetes.io/role/elb)

# Common issues:
# 1. Missing subnet tags → LBC can't find subnets
# 2. Missing IAM permissions → "AccessDenied" in logs
# 3. Wrong ingressClassName → LBC ignores the Ingress
# 4. Target group health check failing → pods not ready or wrong path
# 5. Certificate ARN in wrong region → 400 from ACM
```

---

## 9. Summary

| Resource | AWS Component | Use Case |
|---------|--------------|---------|
| Service (ip target) | NLB → pods directly | TCP/UDP, low latency |
| Service (instance target) | NLB → NodePort | Simple setup |
| Ingress | ALB → pods | HTTP/S, path routing, WAF |
| IngressGroup | Shared ALB | Multiple services, one LB |
| TargetGroupBinding | Existing TG | Blue/green, external traffic |

---

**Next:** [Lesson 32 — AWS Hybrid and Multi-Cluster Networking](32-aws-hybrid-multicluster.md)
