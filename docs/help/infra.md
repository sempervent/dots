# Infrastructure tooling

```bash
./setup.sh --packages infra
./dots check infra
./dots check infra gate
```

IaC CLIs (Terraform ecosystem, Ansible, Vault, Packer, Infracost). DOTS never
applies infrastructure, logs into Vault, builds images, or calls cost APIs by
default.

See `docs/using/infra-tooling.md`.
