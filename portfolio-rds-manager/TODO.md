# Portfolio RDS & NAT Manager — TODO / Progress Tracker

## Status Legend
- `[x]` Done
- `[-]` In progress
- `[ ]` Not started

---

## NAT Gateway Manager (`portfolio-nat-manager.sh`)

### Bugs Fixed (2026-03-31)
- [x] **Silent auth failure** — AWS CLI was silencing errors (`2>/dev/null || echo "deleted"`), causing unauthenticated sessions to falsely report gateways as deleted. Fixed by adding `--profile "$AWS_PROFILE"` to all AWS calls.
- [x] **Stale state file** — `stop` command now syncs `.portfolio-nat-state.json` when it detects the saved NAT ID is no longer active in AWS.
- [x] **Stale ID fallback** — If saved ID is wrong/old, `stop` now does a secondary lookup by Name tag to find the real active gateway.
- [x] **Hardcoded profile** — Added `AWS_PROFILE="${AWS_PROFILE:-housing-prototype}"` config var; can be overridden at runtime.

### Pending / Next Steps
- [ ] **End-to-end test** — Run `stop` after `aws sso login` to confirm full delete flow works
- [ ] **Test `start`** — After stop succeeds, test that `start` recreates the gateway and updates route tables
- [ ] **Verify route table cleanup** — Confirm routes are removed on stop and re-added on start
- [ ] **Add `sync` command** — Utility to reconcile all state file entries against AWS reality (useful after manual console changes)
- [ ] **Add profile validation** — Warn on startup if SSO session is expired rather than failing silently mid-command

---

## RDS Manager (`portfolio-rds-manager.sh`)

### Status
- [ ] **Verify AWS profile** — Check if RDS manager also needs `--profile housing-prototype` added (same auth issue pattern as NAT manager)
- [ ] **Test stop/start** — Confirm RDS stop/start works end-to-end with SSO profile

---

## Infrastructure / Setup

### Completed
- [x] NAT Gateway `portfolio-managed-nat` configured in `nat-portfolio-config.yaml`
- [x] State file initialized with EIP `52.72.164.240` / allocation `eipalloc-0291dcb8d314f016c`
- [x] CloudFormation infrastructure deployed (RDS manager)

### Pending
- [ ] Confirm CloudFormation stack is still healthy: `aws cloudformation describe-stacks --stack-name portfolio-rds-manager --profile housing-prototype`
- [ ] Confirm Lambda auto-restart is running (EventBridge rule active)

---

## Documentation
- [x] `CLAUDE.md` created — project context for Claude Code sessions
- [x] `TODO.md` created — this file
- [ ] Update `README-NAT-GATEWAY-MANAGER.md` troubleshooting section with SSO/profile instructions
- [ ] Update `QUICK-START-NAT-MANAGER.md` prerequisites to mention SSO login step

---

## Cost Tracking

| Resource | Monthly Cost (running) | Monthly Cost (stopped) |
|----------|----------------------|----------------------|
| NAT Gateway (`portfolio-managed-nat`) | ~$40 | ~$0.32 (EIP only) |
| RDS `bloom-prototype` | ~$13 | ~$6.50 (storage) |
| RDS `snomass` | ~$13 | ~$6.50 (storage) |
| **Total** | **~$66** | **~$13** |

**Max monthly savings when everything stopped: ~$53/month**
