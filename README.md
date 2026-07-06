# remote-development-poc

Terraform code for my Azure-native Remote Development Environment POC.

After `terraform plan` and `terraform apply`ing, you may need to:

1. Grant admin consent for the Storage Account

2. If using cloud-only identities:

```
 az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/<appObjectId>" \
    --headers "Content-Type=application/json" \
    --body '{"tags":["kdc_enable_cloud_group_sids"]}'
```

Blog post: https://blog.bl-lab.net/posts/remote-development-environments-in-azure