# Portfolio NAT Gateway Manager - Complete Guide

## Quick Start

After Claude Code setup completes, you can manage your NAT Gateway with simple commands:

```bash
# Check status
./portfolio-nat-manager.sh status

# Stop NAT Gateway (delete it, save ~$40/month)
./portfolio-nat-manager.sh stop primary-nat

# Start NAT Gateway (recreate it, takes 2-3 minutes)
./portfolio-nat-manager.sh start primary-nat

# View cost savings potential
./portfolio-nat-manager.sh cost-estimate
```

---

## What It Does

The Portfolio NAT Gateway Manager helps you manage NAT Gateway lifecycle during prototyping:

**Stop (Delete)**:
- Deletes the NAT Gateway
- Preserves Elastic IP address
- Stops all charges (~$40/month saved)
- Takes ~30 seconds
- **Result**: Private subnets lose outbound internet

**Start (Recreate)**:
- Recreates NAT Gateway with same configuration
- Uses the preserved Elastic IP
- Resumes normal operation
- Takes 2-3 minutes
- **Result**: Private subnets have outbound internet again

---

## Cost Breakdown

### Monthly Costs

**NAT Gateway Running**:
- Hourly charge: ~$0.032/hour × 730 hours = ~$32/month
- Data processing: ~$0.045 per GB (varies by usage)
- **Total: $40-100/month depending on data usage**

**NAT Gateway Deleted**:
- Hourly charge: $0
- Elastic IP storage: ~$0.32/month (preserved for reuse)
- **Total: ~$0.32/month**

### Savings Examples

| Usage | Monthly Cost | Monthly Savings |
|-------|-------------|-----------------|
| Running all month | $40 | — |
| 50% of time | $20 | $20 |
| 25% of time | $10 | $30 |
| 10% of time | $4 | $36 |
| 5% of time | $2 | $38 |

**For prototyping (use 25% of the time): Save ~$30/month**

---

## Configuration

Edit `nat-portfolio-config.yaml` to configure your NAT Gateways.

### Required Fields

```yaml
nat_gateways:
  - name: "primary-nat"                    # Short name for your NAT Gateway
    availability_zone: "us-east-1a"        # AZ where it runs
    subnet_id: "subnet-xxxxxxxx"           # Public subnet for NAT Gateway
    allocation_id: "eipalloc-xxxxxxxx"     # Elastic IP allocation ID
    route_tables:
      - "rtb-xxxxxxxx"                     # Private subnet route tables
    route_destination: "0.0.0.0/0"         # Destination for route (usually all internet)
```

### Finding Your Configuration

**Get Subnet IDs**:
```bash
aws ec2 describe-subnets --query 'Subnets[].{Name:Tags[0].Value,SubnetId:SubnetId}' --output table
```

**Get Elastic IP Allocation IDs**:
```bash
aws ec2 describe-addresses --domain vpc
```

**Get Route Table IDs**:
```bash
aws ec2 describe-route-tables --query 'RouteTables[].{Name:Tags[0].Value,RouteTableId:RouteTableId}' --output table
```

---

## CLI Commands

### Status

Shows current status of all NAT Gateways and costs:

```bash
./portfolio-nat-manager.sh status
```

**Output**:
```
ℹ Portfolio NAT Gateway Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Running
    Name:     primary-nat
    AZ:       us-east-1a
    Status:   available
    NAT ID:   ngw-xxxxxxxx
    EIP:      203.0.113.12
    Cost:     ~$40/month

  ✗ Deleted
    Name:     backup-nat
    AZ:       us-east-1b
    Status:   deleted
    Cost:     ~$0.32/month (EIP only)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Cost Summary
  Running:  $40/month
  Deleted:  $1/month
  Total:    $41/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### List

Lists all configured NAT Gateways:

```bash
./portfolio-nat-manager.sh list
```

**Output**:
```
ℹ Available NAT Gateways:

  • primary-nat
    AZ:     us-east-1a
    Subnet: subnet-12345678

  • backup-nat
    AZ:     us-east-1b
    Subnet: subnet-87654321
```

### Stop

Deletes a NAT Gateway to save costs:

```bash
./portfolio-nat-manager.sh stop primary-nat
```

**What happens**:
1. Confirms with you
2. Removes NAT Gateway route from route tables
3. Deletes the NAT Gateway
4. Waits for deletion to complete
5. Saves state for later recreation

**Result**:
- ✅ NAT Gateway deleted
- ✅ Elastic IP preserved
- ✅ Charges stop (~$40/month saved)
- ❌ Private subnets lose outbound internet

### Start

Recreates a deleted NAT Gateway:

```bash
./portfolio-nat-manager.sh start primary-nat
```

**What happens**:
1. Creates new NAT Gateway in configured subnet
2. Uses preserved Elastic IP allocation
3. Waits for NAT Gateway to be available (2-3 minutes)
4. Updates route tables to point to new NAT Gateway
5. Saves state

**Result**:
- ✅ NAT Gateway created and available
- ✅ Same Elastic IP address
- ✅ Route tables updated
- ✅ Private subnets have outbound internet again
- ✅ Monthly cost resumes (~$40/month)

### Cost Estimate

Shows monthly costs and savings potential:

```bash
./portfolio-nat-manager.sh cost-estimate
```

**Output**:
```
ℹ Monthly Cost Estimates
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  primary-nat
    Running:  $40/month (all month)
    Deleted:  $1/month (EIP only)
    If 25% uptime: $10/month ($30 saved)
    If 10% uptime: $4/month ($36 saved)

  backup-nat
    Running:  $40/month (all month)
    Deleted:  $1/month (EIP only)
    If 25% uptime: $10/month ($30 saved)
    If 10% uptime: $4/month ($36 saved)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Total Monthly Costs
  All running:  $80/month
  All deleted:  $2/month

💡 Recommendation for prototyping:
  Delete when not developing/testing
  Recreate when you need it (2-3 minutes)
  Potential savings: ~$60-70/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Workflow Examples

### Scenario 1: Daily Development

```bash
# Morning: Start work
./portfolio-nat-manager.sh start primary-nat
# Waits 2-3 minutes for NAT Gateway to be ready
# You can now develop/test

# Evening: Done for the day
./portfolio-nat-manager.sh stop primary-nat
# Immediately saves ~$40/month
```

### Scenario 2: Production Demo

```bash
# Before demo
./portfolio-nat-manager.sh start primary-nat

# During demo: Everything works normally

# After demo
./portfolio-nat-manager.sh stop primary-nat
```

### Scenario 3: Monitor Costs

```bash
# Check current spending
./portfolio-nat-manager.sh cost-estimate

# Output shows savings if running 25% of time
# Helps you understand your potential savings
```

---

## State Management

The tool tracks state in `.portfolio-nat-state.json`:

```json
{
  "primary-nat": {
    "nat_gateway_id": "ngw-12345678",
    "elastic_ip": "eipalloc-87654321",
    "status": "available",
    "public_ip": "203.0.113.12",
    "last_action": "Created at 2026-03-13T14:30:00Z"
  },
  "backup-nat": {
    "nat_gateway_id": "",
    "elastic_ip": "eipalloc-11111111",
    "status": "deleted",
    "public_ip": "",
    "last_action": "Deleted at 2026-03-13T10:00:00Z"
  }
}
```

This state file allows the tool to:
- Remember which NAT Gateway is which
- Preserve Elastic IP allocation IDs
- Track creation/deletion dates
- Manage multiple NAT Gateways independently

---

## Troubleshooting

### "NAT Gateway not found"

```
Error: NAT Gateway not found: primary-nat
```

**Solution**: Check that the name matches exactly in `nat-portfolio-config.yaml`

```bash
./portfolio-nat-manager.sh list  # Show configured NAT Gateways
```

### "Failed to delete NAT Gateway"

**Solution**: Wait a moment and try again. NAT Gateways sometimes have dependencies.

```bash
# Wait 30 seconds
sleep 30

# Try again
./portfolio-nat-manager.sh stop primary-nat
```

### "Timeout waiting for NAT Gateway"

**Solution**: This can happen if the NAT Gateway creation/deletion is slow. Try again:

```bash
./portfolio-nat-manager.sh start primary-nat
```

### "Route table update failed"

**Solution**: This is usually non-fatal. The NAT Gateway was created but route updating failed.

```bash
# Manually update route tables:
aws ec2 replace-route \
  --route-table-id rtb-xxxxxxxx \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id ngw-xxxxxxxx
```

### "Elastic IP not configured"

**Solution**: The state file or config is missing the Elastic IP allocation ID.

```bash
# Get your Elastic IP allocation ID:
aws ec2 describe-addresses --domain vpc

# Update nat-portfolio-config.yaml with the allocation_id
# Or recreate the state file and rerun setup
```

---

## Integration with RDS Manager

You can use both managers together:

```bash
# Example: Stop everything before vacation
./portfolio-rds-manager.sh stop bloom-prototype
./portfolio-rds-manager.sh stop snomass
./portfolio-nat-manager.sh stop primary-nat

# Result: Only paying for storage
# Estimated monthly cost: ~$5-10 (vs $80+ when running)

# When you return:
./portfolio-nat-manager.sh start primary-nat
./portfolio-rds-manager.sh start bloom-prototype
./portfolio-rds-manager.sh start snomass
```

---

## Advanced: Multiple NAT Gateways

If you have multiple NAT Gateways (for high availability):

```yaml
nat_gateways:
  - name: "primary-nat"
    availability_zone: "us-east-1a"
    # ... config ...
  
  - name: "backup-nat"
    availability_zone: "us-east-1b"
    # ... config ...
```

Manage them independently:

```bash
./portfolio-nat-manager.sh stop primary-nat    # Stop just one
./portfolio-nat-manager.sh status               # See both statuses
./portfolio-nat-manager.sh cost-estimate       # See total costs
```

---

## Security Considerations

- **No credentials in config**: The tool uses AWS CLI, which uses your AWS credentials
- **Elastic IPs preserved**: Your EIP is never deleted, just unassociated
- **Route tables updated automatically**: No manual route management needed
- **State file is local**: `.portfolio-nat-state.json` stays on your machine

---

## Switching to Lambda Automation

Later, if you want full automation (Lambda auto-restarts on traffic), I can add:

1. **CloudWatch monitoring** for NAT Gateway traffic
2. **Lambda function** that auto-recreates NAT if traffic detected
3. **Lambda function** that auto-deletes NAT if idle for N hours
4. **SNS notifications** when auto-managing

For now, this manual CLI tool gives you simple, predictable control.

---

## Next Steps

1. **Run Claude Code setup** using `CLAUDE-CODE-NAT-PROMPT.txt`
2. **Test it works**: `./portfolio-nat-manager.sh status`
3. **Use it**: Stop when not needed, start when developing
4. **Track savings**: Run `./portfolio-nat-manager.sh cost-estimate` monthly

---

**Ready to save $30-70/month on NAT Gateway costs?** 🚀

Start with the Claude Code setup prompt!
