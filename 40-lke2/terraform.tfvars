k8s_version = "1.25"
region = "us-east"
pools = [
  {
    type : "g6-standard-1"
    count : 2
  }
]

# comment these two when you're sure you're getting a Let's Encrypt (STAGING) cert in the expected places
#  this protects you from the hard rate limit
cluster_issuer_name = "cert-manager-staging"
cluster_issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"