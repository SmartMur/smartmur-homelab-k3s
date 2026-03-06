# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] - 2026-02-28

### Added

- Terraform provisioning for K3s nodes on Proxmox VE (2 servers)
- Ansible playbooks for K3s cluster bootstrap, NFS storage, and app deployment
- 13 app manifests: Authentik, Chirpy, Code Server, Discourse, Dockhand, Headlamp, Homepage, n8n, Nginx Proxy Manager, Notify, Obsidian, Pangolin, Vaultwarden
- NFS-backed persistent storage via TrueNAS
- Ingress configuration with TLS
- Sealed Secrets for secret management
- Namespace isolation per app
- GitHub Actions CI pipeline with Terraform validation, Ansible lint, and manifest checks
- Security policy, contributing guide, and support docs
- Makefile for common operations
