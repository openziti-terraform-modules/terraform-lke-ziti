label = "kentest-11"
k8s_version = "1.25"
region = "us-east"
pools = [
  {
    type : "g6-standard-1"
    count : 2
  }
]
email = "w2@qrk.us"
domain_name = "lke.bingnet.cloud"
# cluster_issuer_name = "cert-manager-staging"
# cluster_issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"