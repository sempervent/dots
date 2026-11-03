# Overview

DOTS is a **desired-state environment manager** — profile-driven workstation setup,
not a casual dump of identical packages.

This screen reflects **this machine** when opened via `dots-help`.

## Mental model

```text
Profile        → machine role (home / work / server / …)
Package groups → baseline capabilities (core, modern, …)
Components     → optional features (--with ids)
Supergroups    → aggregates of components (e.g. ai)
Setup          → converges the machine toward desired state
```

## Quick commands

```bash
./dots status
./dots check
./dots help
dots-help
man dots
```
